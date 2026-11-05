-- smart-suggest.nvim: configuration
--
-- Priority (later wins): defaults < vim.g.smart_suggest_config < blink provider opts
--
-- The ranking "backend" is pluggable. `decisions` (Inception Labs Mercury
-- Decide) ships with the plugin; `local` is a deterministic no-network
-- fallback. See README for writing your own.

local defaults = {
  backend = "decisions",
  endpoint = "https://api.inceptionlabs.ai/v1/decisions",
  model = "mercury-decide",
  api_key_env = "INCEPTION_API_KEY",

  -- privacy: send only the enclosing function around the cursor
  max_context_lines = 60,

  enabled_ft = { "c", "cpp" },
  disabled = false, -- hard off; `:SmartSuggestToggle`

  -- max candidates sent/considered per request (one decision per candidate)
  max_candidates = 8,
  -- drop answers below this probability (noise filter)
  min_probability = 0.05,
  -- show probability in the completion menu label
  show_probability = true,
  -- decisions backend only: without an API key, still suggest in engine order
  local_only_fallback = true,
}

local M = { defaults = defaults }

local current = nil

function M.setup(opts)
  current = vim.tbl_deep_extend("force", defaults, vim.g.smart_suggest_config or {}, opts or {})
  return current
end

function M.get()
  if not current then
    return M.setup(nil)
  end
  return current
end

return setmetatable(M, {
  __index = function(_, k)
    local c = current
    if not c then
      c = M.setup(nil)
    end
    return c[k]
  end,
})
