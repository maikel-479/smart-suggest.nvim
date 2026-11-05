-- Inception Labs "Decisions" backend (mercury-decide).
-- Classifies each candidate with an independent `noul` question against a
-- shared state (the code around the cursor). One HTTP round-trip per request.
--
-- API docs: https://docs.inceptionlabs.ai/capabilities/decisions
local config = require "smart_suggest.config"

local M = {}

local pending_seq = 0

local function build_questions(candidates)
  local questions = {}
  for i, cand in ipairs(candidates) do
    local repl = cand.repl or 0
    local repl_desc = repl == 0
      and "inserted directly at the cursor"
      or string.format(
        "replacing the %d characters immediately before the cursor (the half-typed text)",
        repl
      )
    questions["cand" .. i] = {
      type = "noul",
      instructions = string.format(
        "The cursor is at the ◈ marker in the code. Candidate: the text <%s> is %s. Would doing so correctly and naturally continue or end this line/statement of code, matching the author's intent?",
        cand.text,
        repl_desc
      ),
    }
  end
  return questions
end

function M.rank(request, callback)
  local api_key = os.getenv(config.api_key_env)
  if not api_key then
    if config.local_only_fallback then
      return require("smart_suggest.backend.local").rank(request, callback)
    end
    callback { ok = false }
    return
  end

  pending_seq = pending_seq + 1
  local my_seq = pending_seq

  local body = vim.json.encode {
    model = config.model,
    state = {
      language = request.filetype,
      cursor_line = request.cursor_line,
      context = request.context,
    },
    questions = build_questions(request.candidates),
  }

  pcall(vim.system, {
    "curl",
    "-sS",
    "--max-time",
    "8",
    config.endpoint,
    "-H",
    "Authorization: Bearer " .. api_key,
    "-H",
    "Content-Type: application/json",
    "-d",
    body,
  }, { text = true }, function(res)
    vim.schedule(function()
      if pending_seq ~= my_seq then
        return -- cancelled / superseded by a newer request
      end
      if not res or res.code ~= 0 or not res.stdout or res.stdout == "" then
        callback { ok = false }
        return
      end
      local decoded = vim.json.decode(res.stdout)
      local answers = decoded and decoded.answers
      if not answers then
        callback { ok = false }
        return
      end
      local ranked = {}
      for i, cand in ipairs(request.candidates) do
        local a = answers["cand" .. i]
        ranked[#ranked + 1] = { cand = cand, p = a and tonumber(a.noul) or 0 }
      end
      callback { ok = true, ranked = ranked }
    end)
  end)

  return function()
    pending_seq = pending_seq + 1
  end
end

return M
