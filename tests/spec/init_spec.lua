local h = require("helpers")
local Git = require("diff-magik.git")

local test = h.test

local function modified_repo()
	local root = h.repo({ ["a.txt"] = { "one" } })
	h.write(root .. "/a.txt", { "two" })
	require("diff-magik").setup()
	return root
end

test("the stage key stages the file of the current buffer", function()
	local root = modified_repo()
	h.edit(root .. "/a.txt")

	h.press("3")

	h.eq(
		{ { path = "a.txt", status = "M", staged = true, unstaged = false } },
		Git.from_root(root):get_changed_files()
	)
end)

test("the stage key stages the file shown in the HEAD pane", function()
	local root = modified_repo()
	h.edit(root .. "/a.txt")
	vim.cmd.DiffMagikOpen()
	vim.api.nvim_set_current_win(h.win_of(h.buf_named("diffmagik://a.txt@HEAD")))

	h.press("3")

	h.eq(
		{ { path = "a.txt", status = "M", staged = true, unstaged = false } },
		Git.from_root(root):get_changed_files()
	)
end)
