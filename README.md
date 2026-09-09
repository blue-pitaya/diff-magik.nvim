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
