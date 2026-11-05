-- smart-suggest.nvim — a blink.cmp source for AI-ranked line endings.
--
-- blink.cmp calls require("smart_suggest").new(); see `sources.providers.<id>` in
-- the README. Candidate composition is local and deterministic
-- (smart_suggest/engine.lua); a pluggable backend (smart_suggest.backend.*) ranks them
-- asynchronously; the best candidates are returned as textEdit items.

local config = require "smart_suggest.config"
local engine = require "smart_suggest.engine"
local context = require "smart_suggest.context"
local backend = require "smart_suggest.backend"

local source = {}

-- blink.CompletionItemKind.Keyword; 14 is the same value from the LSP spec
local KIND
do
  local ok, types = pcall(require, "blink.cmp.types")
  KIND = ok and types.CompletionItemKind.Keyword or 14
end

function source.new(opts, _provider)
  local self = setmetatable({}, { __index = source })
  self.opts = opts or {}
  config.setup(self.opts)
  return self
end

function source:enabled()
  local cfg = config.get()
  if cfg.disabled then
    return false
  end
  for _, ft in ipairs(cfg.enabled_ft) do
    if vim.bo.filetype == ft then
      return true
    end
  end
  return false
end

function source:get_trigger_characters()
  -- punctuation that typically "opens" a decision about how a line ends
  return { ";", "(", ")", "=", "<", ">", "[", "]", "{", "}", '"', "'", "," }
end

-- ---------- helpers ----------

local function partial_line()
  local row1, col = unpack(vim.api.nvim_win_get_cursor(0)) -- row1 is 1-based
  local row = row1 - 1 -- 0-based for the buffer/em APIs
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, true)[1] or ""
  return line:sub(1, col), row, col
end

local function keyword_before(partial)
  return partial:match("[%w_]+$") or ""
end

local function make_item(cand, prob, row, col, rank, keyword, show_prob)
  local label = cand.text
  if show_prob then
    label = cand.text .. "  ✦" .. string.format("%.2f", prob)
  end
  return {
    label = label,
    kind = KIND,
    -- always "fuzzy-match" against whatever is typed so the item never hides
    filterText = keyword,
    -- ranked order within this provider
    sortText = string.format("aaa%03d", rank),
    score_offset = -rank,
    insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
    -- repl = 0 → insert at cursor; repl = n → replace the n chars before it
    textEdit = {
      newText = cand.text,
      range = {
        start = { line = row, character = col - (cand.repl or 0) },
        ["end"] = { line = row, character = col },
      },
    },
  }
end

local function empty_result(callback)
  callback {
    items = {},
    -- recompose on every keystroke: candidates depend on the whole partial
    -- line, not just the keyword
    is_incomplete_backward = true,
    is_incomplete_forward = true,
  }
end

-- ---------- blink source API ----------

function source:get_completions(_ctx, callback)
  local partial, row, col = partial_line()
  if #partial == 0 then
    empty_result(callback)
    return function() end
  end

  -- nothing to decide on comment/preprocessor-only lines
  if partial:match("^%s*//") or partial:match("^%s*#") then
    empty_result(callback)
    return function() end
  end

  local candidates = engine.candidates(partial)
  if not candidates or #candidates == 0 then
    empty_result(callback)
    return function() end
  end

  local keyword = keyword_before(partial)
  local row1 = row + 1

  -- fire the ranking; keep our own snapshot coordinates for the textEdit
  -- (blink applies textEdits against its request snapshot, so this is correct
  -- even if the model answers after the user typed more)
  local cancel = backend.rank({
    partial = partial,
    keyword = keyword,
    candidates = candidates,
    context = context.context(config.max_context_lines),
    cursor_line = row1,
    filetype = vim.bo.filetype,
  }, function(result)
    if not result or not result.ok or not result.ranked or #result.ranked == 0 then
      empty_result(callback)
      return
    end

    local ranked = result.ranked
    table.sort(ranked, function(x, y)
      return x.p > y.p
    end)

    -- filter noise, but never return zero: a hedged best-guess beats an
    -- empty menu (only when the backend found nothing plausible)
    local kept = {}
    for _, r in ipairs(ranked) do
      if r.p >= config.min_probability then
        kept[#kept + 1] = r
      end
    end
    if #kept == 0 then
      kept = { ranked[1] }
      if ranked[2] then
        kept[2] = ranked[2]
      end
    end

    local items = {}
    for rank, r in ipairs(kept) do
      items[#items + 1] = make_item(r.cand, r.p, row, col, rank - 1, keyword, config.show_probability)
    end
    callback({
      items = items,
      is_incomplete_backward = true,
      is_incomplete_forward = true,
    })
  end)

  -- cancellation: blink calls this on retrigger/cursor movement
  return function()
    if cancel then
      cancel()
    end
  end
end

return source
