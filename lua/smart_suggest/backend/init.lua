-- Backend resolution. A "backend" is a Lua module (`smart_suggest.backend.<name>`)
-- exposing one function:
--
--   M.rank(request, callback)
--
-- request = {
--   partial     = string,   -- line text before the cursor
--   keyword     = string,   -- trailing identifier ("" when none)
--   candidates  = { { text = string, repl = number } },  -- from the engine
--   context     = string,   -- enclosing function around cursor (◈ marks it)
--   cursor_line = number,   -- 1-based
--   filetype    = string,
-- }
--
-- callback(result) where result = {
--   ok = boolean,
--   ranked = { { cand = { text, repl }, p = number } },  -- best first
-- }
--
-- The backend must always call the callback exactly once, and may do so
-- asynchronously. It must never generate new candidate text — it only ranks
-- what the local engine composed.
local config = require "smart_suggest.config"

local M = {}
local cache = {}

local function fallback_backend()
  local ok, m = pcall(require, "smart_suggest.backend.local")
  return ok and m or nil
end

function M.get()
  local name = config.backend or "decisions"
  if cache[name] then
    return cache[name]
  end
  local ok, mod = pcall(require, "smart_suggest.backend." .. name)
  if not ok then
    vim.schedule(function()
      vim.notify(
        string.format("[smart-suggest] backend '%s' not found; using 'local'", name),
        vim.log.levels.WARN
      )
    end)
    mod = fallback_backend()
  end
  cache[name] = mod
  return mod
end

function M.rank(request, callback)
  local mod = M.get()
  if not mod then
    callback { ok = false }
    return
  end
  local ok, err = pcall(mod.rank, request, callback)
  if not ok then
    vim.schedule(function()
      vim.notify("[smart-suggest] backend error: " .. tostring(err), vim.log.levels.WARN)
    end)
    callback { ok = false }
  end
end

return M
