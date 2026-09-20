# nvim-diff-magik

Git diff for changed files against git `HEAD` inside neovim. Inspired by [diffview.nvim](https://github.com/sindrets/diffview.nvim).

## Installation

lazy.nvim

```lua
{
  "yourname/nvim-diff-magik",
  cmd = { "DiffMagikOpen", "DiffMagikBrowser", "DiffMagikBrowserDiffToggle" },
  config = function()
    require("diff-magik").setup()
  end,
}
```

## Commands

- `:DiffMagikOpen` 
- `:DiffMagikBrowser`
- `:DiffMagikBrowserDiffToggle`

## Default config

```lua
require("diff-magik").setup({
  keys = {
    open = { "<CR>", "o" },
    close = { "q" },
    next_file = { "1" },
    prev_file = { "2" },
    stage = { "3" },
    reset = { "X" },
    toggle_width = { "N" },
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
    file_added = "DiffMagikFileAdded",
    file_deleted = "DiffMagikFileDeleted",
  },
  fillchar = "╱",
  width_mode = "expand",
  diff_style = "split",
  fold_context = 3,
})
```

`:DiffMagikBrowserDiffToggle` flips the browser's `diff_style` between `"split"`, the two
panes, and `"inline"`, a single pane: the lines you added are highlighted in place, the
lines you deleted are drawn above them as virtual lines, and there is no second buffer to
scrollbind against. Switching to `"inline"` closes the base pane on the spot and redraws
the file that is open, and every file opened from the sidebar afterwards follows the same
style until you switch back. `diff_style` sets the style the browser starts in, and the
cursor stays wherever the command was run from.

`file_added` and `file_deleted` are the highlight groups the inline style draws with. They
default to `DiffMagikFileAdded` and `DiffMagikFileDeleted`, which are defined as copies of
`DiffAdd` and `DiffDelete` — copies, because the split panes remap `DiffDelete` to the dim
filler color through `winhighlight`, and a virtual line drawn in such a window would inherit
that remap and come out grey instead of red. The copies are refreshed on every `ColorScheme`,
so point `file_added` / `file_deleted` at groups of your own to recolor.

The inline style folds every run of untouched lines away, keeping `fold_context` lines on
each side of a hunk, so what is left on screen is the changes and their surroundings; `zR`
opens it all back up. In the `"split"` style the folding is Vim's own, the one `:diffthis`
sets up — if you run with `set nofoldenable`, that is why you see no folds there. Switching
the style back hands the window's fold settings over exactly as they were.

`width_mode` controls how wide the browser sidebar is: `"expand"` grows it to fit the
widest row (never past half the screen), `"constant"` pins it to 40 columns. Press `N`
inside the sidebar to switch between the two.
