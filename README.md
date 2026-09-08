# nvim-diff-magik

Adds `:DiffMagikOpen`, which diffs the current buffer's file against the
current git `HEAD`, and `:DiffMagikBrowser`, a neo-tree-style sidebar
browser of every changed file in the repo.

### `:DiffMagikOpen`

- If the buffer has no associated file, or the file is not inside a git
  repository, or the file is not tracked by git: prints an error.
- If the file is tracked but has no changes against `HEAD`: prints an error.
- Otherwise: opens a vertical split showing the `HEAD` version of the file
  next to the current buffer with diff mode enabled.

### `:DiffMagikBrowser`

- If not inside a git repository, or there are no changes (tracked or
  untracked) against `HEAD`: prints an error.
- Otherwise: opens a pinned sidebar (or focuses it, if already open)
  listing every changed file as `<status> <path>`, with the status letter
  (`M`, `A`, `D`, `R`, `?`, ...) colored via the standard
  `diffAdded`/`diffChanged`/`diffRemoved` highlight groups, so it always
  matches the active colorscheme. The current line is highlighted via a
  `DiffMagikCursorLine` group (defaults to linking `CursorLine`).
  Press `<CR>` or `o` on an entry to open a base (`HEAD`) vs current diff
  for that file in the window the browser was opened from — reusing that
  split on each subsequent selection instead of stacking new ones. Press
  `q` to close the sidebar; any open diff split is left as-is.

## Installation

The plugin exposes a `setup()` function that must be called to register
`:DiffMagikOpen`.

lazy.nvim:

```lua
{
  "yourname/nvim-diff-magik",
  cmd = "DiffMagikOpen",
  config = function()
    require("diff-magik").setup()
  end,
}
```

packer.nvim:

```lua
use({
  "yourname/nvim-diff-magik",
  config = function()
    require("diff-magik").setup()
  end,
})
```

## Usage

Run `:DiffMagikOpen` from a buffer whose file is tracked in a git repo and
has uncommitted changes.
