# nvim-diff-magik

Git diff for changed files against git `HEAD` inside neovim. Inspired by [diffview.nvim](https://github.com/sindrets/diffview.nvim).

## Installation

lazy.nvim

```lua
{
  "yourname/nvim-diff-magik",
  cmd = { "DiffMagikOpen", "DiffMagikBrowser" },
  config = function()
    require("diff-magik").setup()
  end,
}
```

## Commands

- `:DiffMagikOpen` 
- `:DiffMagikBrowser`

## Default config

```lua
require("diff-magik").setup({
  keys = {
    open = { "<CR>", "o" },
    close = { "q" },
    next_file = { "1" },
    prev_file = { "2" },
    stage = { "3" },
  },
  highlights = {
    added = "Added",
    changed = "Changed",
    removed = "Removed",
    directory = "Directory",
    staged = "Added",
    staged_dirty = "DiagnosticWarn",
    head_win = "DiffAdd:DiffDelete,DiffDelete:DiffviewDiffDeleteDim",
    main_win = "DiffDelete:DiffviewDiffDeleteDim",
  },
  fillchar = "╱",
})
```
