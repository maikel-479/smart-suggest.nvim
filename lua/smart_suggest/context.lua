-- Extracts "function around the cursor" context for the Decisions state.
-- Heuristic for C-style code:
--   * fn start  = the nearest line ABOVE the cursor that starts at column 0
--     with a non-space character (function signatures are at col 0; inside a
--     body, everything is indented). Comments/preprocessor lines are skipped.
--   * fn end    = the first line AT or BELOW the cursor starting with `}` at
--     col 0 (the function's closer). Falls back to a fixed window.
local M = {}

local MAX_UP = 200
local MAX_DOWN = 200

local function is_col0_code(line)
  -- non-empty, first char is not whitespace and not `#`/comment marker
  local first = line:sub(1, 1)
  return first ~= "" and first ~= " " and first ~= "\t" and first ~= "#" and first ~= "*"
end

function M.context(max_lines)
  max_lines = max_lines or 60
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cur = cursor[1]     -- 1-based
  local col = cursor[2]     -- 0-based
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local n = #lines

  -- walk up for the signature line (col-0 non-space, non-preprocessor/comment)
  local fn_start = math.max(cur - math.floor(max_lines / 2), 1)
  for i = cur - 1, math.max(cur - MAX_UP, 1), -1 do
    local l = lines[i]
    if l:match("^%s*$") then
      -- blank line: candidate boundary, record in case nothing better appears
      fn_start = math.min(fn_start, i + 1)
    elseif is_col0_code(l) then
      fn_start = i
      break
    end
  end

  -- walk down for the closing brace at col 0
  local fn_end = math.min(cur + max_lines, n)
  local saw_open = lines[cur]:find("{", 1, true) ~= nil or lines[cur]:match("%S")
  for i = cur, math.min(cur + MAX_DOWN, n), 1 do
    if lines[i]:match("^%s*}%s*$") or lines[i]:match("^%}") then
      fn_end = i
      break
    end
  end

  -- clamp the slice around the cursor so both sides stay inside max_lines
  local budget = max_lines - 1
  local up_used = math.min(cur - fn_start, budget)
  local down_used = math.min(fn_end - cur, budget - up_used)
  if up_used + down_used > budget then
    down_used = math.max(budget - up_used, 0)
  end

  local start = math.max(cur - up_used, 1)
  local stop = math.min(cur + down_used, n)
  local slice = {}
  for i = start, stop, 1 do
    local l = lines[i]
    if i == cur then
      l = l:sub(1, col) .. "◈" .. l:sub(col + 1)
    end
    slice[#slice + 1] = l
  end
  return table.concat(slice, "\n")
end

return M
