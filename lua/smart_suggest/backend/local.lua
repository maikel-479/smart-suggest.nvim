-- Deterministic offline backend: no network, no API key.
-- Candidates come out of the engine already ordered by heuristic priority,
-- so ranks are just a decaying probability curve over that order.
local M = {}

function M.rank(request, callback)
  local n = #request.candidates
  local ranked = {}
  for i, cand in ipairs(request.candidates) do
    ranked[#ranked + 1] = {
      cand = cand,
      p = math.max(0.9 - (i - 1) * (0.5 / math.max(n - 1, 1)), 0.35),
    }
  end
  callback { ok = true, ranked = ranked }
end

return M
