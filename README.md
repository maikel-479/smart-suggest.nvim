# smart-suggest.nvim

A [blink.cmp](https://github.com/SagHen/blink.cmp) completion source that
ranks "how does this line end?" suggestions inside your normal completion
menu. It happens to be written and tested around C and C++ code, simply
because that is what I worked in when trying the idea out. The design is
language-agnostic.

## The problem it tries to solve

Most completion only helps with the *next word*. When what you need is the
end of the current statement — a semicolon, an unterminated string closer, a
closing quote, `std::endl;` after a broken `<<` chain — you still have to
type it all yourself, every time, even though the answer is usually obvious
from the file you are already in.

This plugin suggests line endings instead of individual symbols. You type
`std::cout << ` and the menu offers `std::endl;`, `std::flush;`, `"\n";` —
ranked by an AI that has read the function you are working in, marked
best-first so you can just take the top one.

## How it works

The AI never writes code. That is the important part, and it is what keeps
this safe and cheap.

Everything happens in two layers:

1. **The composer** (`lua/smart_suggest/engine.lua`) is plain Lua. It reads the
   partial line up to the cursor, tracks quotes, parentheses and braces, and
   produces a short list of *syntactically valid* endings. When you have
   half-typed a keyword, it also offers full replacements — e.g. after
   `<< s` you get `std::endl;` as a "replace `s`" candidate, next to `;` as a
   "keep `s`, terminate" candidate. Both are always valid inputs; which one
   you meant is the AI's problem, not yours.
2. **The backend** takes the candidates, and the enclosing function of your
   cursor as context, and ranks them. One candidate, one decision, one small
   HTTP call. Candidates below the probability floor are dropped; if nothing
   is plausible (your code was genuinely broken), you still get the top
   guesses, hedge included.

The shipped backend uses [Inception Labs'
Decisions](https://docs.inceptionlabs.ai/capabilities/decisions) endpoint,
which costs a fraction of a cent per request at the time of writing. Write
your own backend for any other classifier endpoint — see the section near
the bottom.

## Installation

Works with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "saghen/blink.cmp",
  opts = function()
    -- merge onto your existing config however you usually do it
    local opts = require("nvchad.blink.config") -- nvchad users
    opts.sources.default = { "smart-suggest", "lsp", "snippets", "buffer", "path" }
    opts.sources.providers = opts.sources.providers or {}
    opts.sources.providers["smart-suggest"] = {
      module = "smart_suggest",
      name = "Smart",
      async = true,   -- the menu never waits on the network
      score_offset = 12,
      timeout_ms = 600,
    }
    return opts
  end,
},
-- put this before or after, lazy resolves it
{
  "maikel-479/smart-suggest.nvim",
  event = { "InsertEnter", "CmdLineEnter" },
},
```

Export your API key before starting nvim:

```bash
export INCEPTION_API_KEY="..."
```

No key? The plugin still works in a degraded mode: the composer's own
ordering is used, no network is touched.

## Options

All of these can go in `vim.g.smart_suggest_config` in your config, or in the
blink provider's `opts` table (blink wins):

```lua
vim.g.smart_suggest_config = {
  backend = "decisions",       -- "decisions" | "local" | your own module name
  enabled_ft = { "c", "cpp" }, -- filetypes the source fires for
  max_context_lines = 60,      -- how much of the function to send around cursor
  min_probability = 0.05,      -- noise floor for ranked candidates
  show_probability = true,     -- append "  ✦0.72" to menu labels
  local_only_fallback = true,  -- engine ordering when no API key is set
  disabled = false,            -- hard off switch
}
```

`:SmartSuggestToggle` flips the hard switch at runtime.
`:SmartSuggestReload` drops and re-requires the modules (useful while editing
them).

## Writing your own backend

A backend is a Lua module under `smart_suggest.backend.<name>`. It exposes one
function that receives the request and must call a callback exactly once:

```lua
function M.rank(request, callback)
  -- request.partial: the line so far
  -- request.keyword: trailing identifier, or ""
  -- request.candidates: { { text = "...", repl = 0 or n } } from the composer
  -- request.context: the enclosing function, cursor marked with a diamond
  -- request.cursor_line: 1-based
  -- request.filetype: "cpp", etc.

  -- Rank the candidates however you like; return them best first.
  callback {
    ok = true,
    ranked = {
      { cand = request.candidates[1], p = 0.9 },
    },
  }
  return function() end -- optional cancel
end
```

Then set `vim.g.smart_suggest_config = { backend = "<name>" }`.

## Known limits

The composer understands quotes, parens, braces, `<<`/`>>`/`printf` chains
and return statements, and it stays conservative: anything subtler
(templates, complex nested brackets) produces no candidates rather than bad
ones. Filetypes other than C and C++ will follow the same pattern; the
engine is where the language knowledge lives, and it is meant to grow.

## License

MIT
