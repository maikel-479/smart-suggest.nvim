-- smart-suggest.nvim user commands
if vim.g.loaded_smart_suggest then
  return
end
vim.g.loaded_smart_suggest = true

local create_cmd = vim.api.nvim_create_user_command

create_cmd("SmartSuggestToggle", function()
  local cfg = require("smart_suggest.config").get()
  cfg.disabled = not cfg.disabled
  vim.notify("[smart-suggest] " .. (cfg.disabled and "disabled" or "enabled"), vim.log.levels.INFO)
end, { desc = "Toggle smart-suggest completions on/off" })

create_cmd("SmartSuggestReload", function()
  package.loaded["smart_suggest"] = nil
  package.loaded["smart_suggest.backend.init"] = nil
  package.loaded["smart_suggest.backend.decisions"] = nil
  package.loaded["smart_suggest.backend.local"] = nil
  package.loaded["smart_suggest.engine"] = nil
  package.loaded["smart_suggest.context"] = nil
  package.loaded["smart_suggest.config"] = nil
  vim.notify("[smart-suggest] modules reloaded", vim.log.levels.INFO)
end, { desc = "Reload smart-suggest modules (for development)" })
