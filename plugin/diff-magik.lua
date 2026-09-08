if vim.g.loaded_diffmagik then
	return
end
vim.g.loaded_diffmagik = true

vim.api.nvim_create_user_command("DiffMagikOpen", function()
	require("diff-magik").open()
end, {
	desc = "Diff the current buffer's file against git HEAD",
})
