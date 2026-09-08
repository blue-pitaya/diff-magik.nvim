-- lazy.nvim spec for nvim-diff-magik.
-- Copy this file into your ~/.config/nvim/lua/plugins/ directory.

return {
  "nvim-diff-magik",
  dir = "~/projects/nvim-diff-magik", -- local path to this plugin while developing; update to your actual path
  name = "nvim-diff-magik",
  cmd = { "DiffMagikOpen", "DiffMagikBrowser" },
  config = function()
    require("diff-magik").setup()
  end,
}
