local h = require("helpers")
local DiffSplit = require("diff-magik.diff-split")

local test = h.test

---@param before_open? fun()
local function open_modified(before_open)
	local root = h.repo({ ["a.lua"] = { "local a = 1", "return a" } })
	h.write(root .. "/a.lua", { "local a = 2", "return a" })

	require("diff-magik").setup()
	h.edit(root .. "/a.lua")
	if before_open then
		before_open()
	end
	vim.cmd.DiffMagikOpen()

	return root
end

local function diff_flags()
	return vim.tbl_map(function(win)
		return vim.wo[win].diff
	end, vim.api.nvim_tabpage_list_wins(0))
end

test("DiffMagikOpen splits the HEAD version next to the working copy", function()
	local root = open_modified()
	local head_buf = h.buf_named("diffmagik://a.lua@HEAD")

	h.eq({ root .. "/a.lua", "diffmagik://a.lua@HEAD" }, h.win_names())
	h.eq({ "local a = 1", "return a" }, h.lines(head_buf))
	h.eq(root .. "/a.lua", vim.api.nvim_buf_get_name(0))
end)

test("DiffMagikOpen turns on diff mode in both panes", function()
	open_modified()

	h.eq({ true, true }, diff_flags())
end)

test("returning to the file in the main window turns diff mode back on", function()
	open_modified()
	local main_buf = vim.api.nvim_get_current_buf()

	vim.cmd.enew()
	vim.api.nvim_set_current_buf(main_buf)

	h.eq({ true, true }, diff_flags())
end)

test("an attaching LSP gets the diff folds put back", function()
	open_modified()
	vim.wo.foldmethod = "expr"

	vim.api.nvim_exec_autocmds("LspAttach", { buffer = vim.api.nvim_get_current_buf(), data = { client_id = 0 } })
	h.flush()

	h.eq("diff", vim.wo.foldmethod)
end)

test("close removes the HEAD pane and restores the main window options", function()
	local root = open_modified(function()
		vim.wo.winhighlight = "Normal:Pmenu"
		vim.wo.foldcolumn = "1"
	end)

	DiffSplit.close()

	h.eq({ root .. "/a.lua" }, h.win_names())
	h.eq("Normal:Pmenu", vim.wo.winhighlight)
	h.eq("1", vim.wo.foldcolumn)
end)

test("DiffMagikOpen replaces the HEAD pane when run again", function()
	local root = open_modified()
	vim.cmd.DiffMagikOpen()

	h.eq({ root .. "/a.lua", "diffmagik://a.lua@HEAD" }, h.win_names())
end)

test("DiffMagikOpen shows the index version of a staged then reverted file", function()
	local root = h.repo({ ["a.txt"] = { "one" } })
	h.write(root .. "/a.txt", { "two" })
	h.git(root, { "add", "a.txt" })
	h.write(root .. "/a.txt", { "one" })

	require("diff-magik").setup()
	h.edit(root .. "/a.txt")
	vim.cmd.DiffMagikOpen()

	h.eq({ "two" }, h.lines(h.buf_named("diffmagik://a.txt@INDEX")))
end)
