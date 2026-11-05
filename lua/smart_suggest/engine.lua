-- Local, deterministic candidate composer for C/C++ line endings.
-- The AI never generates text: it only ranks candidates produced here.
local M = {}

-- scan with escape-aware skipping
local function count_quotes(s, ch)
  local n = 0
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == ch then
      n = n + 1
      i = i + 1
    else
      i = i + 1
    end
  end
  return n
end

-- cut at a `//` comment if one is present (naive but fine for delimiter stats)
local function strip_comment(line)
  local pos = line:find("//", 1, true)
  if pos then
    return line:sub(1, pos - 1)
  end
  return line
end

-- replace string/char contents with `?` placeholders so brackets inside
-- strings don't skew delimiter depth.
-- Returns the sanitized string plus flags for unterminated quotes.
local function without_string_contents(s)
  local out = {}
  local i = 1
  local dq_open, sq_open = false, false
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == '"' or c == "'" then
      local q = c
      i = i + 1
      local inner = {}
      local closed = false
      while i <= #s do
        local d = s:sub(i, i)
        if d == "\\" then
          inner[#inner + 1] = "?"
          i = i + 2
        elseif d == q then
          i = i + 1
          closed = true
          break
        else
          inner[#inner + 1] = "?"
          i = i + 1
        end
      end
      if closed then
        out[#out + 1] = q .. table.concat(inner) .. q
      else
        out[#out + 1] = q .. table.concat(inner)
        dq_open = dq_open or q == '"'
        sq_open = sq_open or q == "'"
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out), dq_open, sq_open
end

local function balance(line)
  local s, dq_open, sq_open = without_string_contents(strip_comment(line))
  local paren, brace, bracket = 0, 0, 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "(" then
      paren = paren + 1
    elseif c == ")" then
      paren = paren - 1
    elseif c == "{" then
      brace = brace + 1
    elseif c == "}" then
      brace = brace - 1
    elseif c == "[" then
      bracket = bracket + 1
    elseif c == "]" then
      bracket = bracket - 1
    end
  end
  return {
    paren = paren,
    brace = brace,
    bracket = bracket,
    dquote_par = dq_open or count_quotes(s, '"') % 2 == 1,
    squote_par = sq_open or count_quotes(s, "'") % 2 == 1,
  }
end

--- Compose insertion candidates for the current line up to the cursor.
--- Each candidate is { text = <string to place at the cursor>, repl = <how
--- many characters before the cursor it replaces> }:
---   * repl = 0  → pure insertion (e.g. append `;` after a finished token)
---   * repl = n  → the candidate REPLACES the last n characters (e.g. a
---                 half-typed keyword `s` becomes `std::endl;`)
--- Returns a list, or nil.
function M.candidates(line)
  local keyword = line:match("[%w_]+$") or ""
  local kwlen = #keyword
  local b = balance(line)
  local seen = {}
  local list = {}
  local function add(text, repl)
    if text and text ~= "" and not seen[text .. "|" .. (repl or 0)] then
      seen[text .. "|" .. (repl or 0)] = true
      list[#list + 1] = { text = text, repl = repl or 0 }
    end
  end

  -- missing string/char closer (always insert directly)
  if b.dquote_par then
    add "\""
  end
  if b.squote_par then
    add "'"
  end

  -- unclosed delimiters
  if b.paren > 0 then
    add ")"
    if b.paren > 1 then
      add "))"
    end
  end
  if b.brace > 0 then
    add "}"
  end

  -- after `if (...)` / `for (...)` / `while (...)`: suggest opening brace
  if b.paren <= 0 and (line:match("%f[%a]for%s*%b()%s*$") or line:match("%f[%a]if%s*%b()%s*$") or line:match("%f[%a]while%s*%b()%s*$")) then
    add "{"
  end

  -- stream operand slots: cursor is a value position in a `<<` chain
  local in_stream_after_op = b.paren == 0
    and not b.dquote_par
    and not b.squote_par
    and line:sub(1, #line - kwlen):match("<<%s*$") ~= nil

  if in_stream_after_op then
    if kwlen == 0 then
      add "std::endl;"
      add "std::flush;"
      add "\"\\n\";"
      if line:match("std::cout%f[%s]*<<%s*$") or line:match("%f[%a]cout%s*<<%s*$") then
        add "\"\";"
      end
    else
      -- half-typed keyword in a value position: offer full replacements
      add("std::endl;", kwlen)
      add("std::flush;", kwlen)
      add(";", 0)                -- keep the typed token as-is and terminate
      add("\"\\n\";", kwlen)
    end
  end

  -- return statement endings
  if b.paren <= 0 and not b.dquote_par and not b.squote_par and line:sub(1, #line - kwlen):match("%f[%a]return%s*$") then
    if kwlen == 0 then
      add "0;"
      add "{};"
      add " nullptr;"
    else
      add("nullptr;", kwlen)
      add("0;", kwlen)
      add(";", 0)
    end
  end

  -- printf family with an open paren and a dangling string
  if b.paren > 0 and line:match("%f[%a]printf%s*$") then
    add "\"\\n\");"
  end

  -- generic statement terminator — the most common case
  local balanced = b.paren <= 0 and b.brace <= 0 and b.bracket <= 0
  local clean = not b.dquote_par and not b.squote_par
  local head = line:sub(1, #line - kwlen)
  if balanced and clean and #head > 0 and not head:match("[;}_(,]$") then
    if kwlen == 0 then
      add ";"
    else
      -- half-typed keywords: right after `<<` handled above; otherwise the
      -- only honest completion is finishing the identifier with `;`
      add(";", 0)
    end
  end

  -- closing a chained stream expression with a terminator
  if balanced and clean and (line:match("std::") or line:match("%f[%a]cout") or line:match("%f[%a]cerr")) and not head:match("[;}<>]%s*$") and not head:match("<<%s*$") then
    if kwlen == 0 then
      add " << std::endl;"
      add " << std::flush;"
    else
      add " << std::endl;"
    end
  end

  -- template / angle-bracket case is deliberately skipped (too ambiguous)

  -- cap candidates to keep the Decisions request small
  local out = {}
  for i = 1, math.min(#list, 8) do
    out[#out + 1] = list[i]
  end
  return #out > 0 and out or nil
end

return M
