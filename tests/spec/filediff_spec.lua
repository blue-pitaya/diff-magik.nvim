local h = require("helpers")
local Git = require("diff-magik.git")
local FileDiff = require("diff-magik.filediff")

local test = h.test

local ns = vim.api.nvim_create_namespace("diff-magik.filediff")
local FOLDEXPR = "v:lua.require'diff-magik.filediff'.foldexpr(v:lnum)"
local ADDED = "DiffMagikFileAdded"
local DELETED = "DiffMagikFileDeleted"

local function numbered()
	local lines = {}
	for i = 1, 20 do
		table.insert(lines, "line " .. i)
	end
	return lines
end

---@param original string[]
---@param changed string[]
---@param before_attach? fun()
---@return integer
---@return integer
local function attach(original, changed, before_attach)
	local root = h.repo({ ["a.txt"] = original })
	h.write(root .. "/a.txt", changed)

	require("diff-magik").setup()
	h.edit(root .. "/a.txt")
	if before_attach then
		before_attach()
	end
	local source = vim.api.nvim_get_current_buf()
	local view = FileDiff.attach(Git.from_root(root), "a.txt", source)

	return assert(view), source
end

---@param before_attach? fun()
local function attach_changed_line_10(before_attach)
	local changed = numbered()
	changed[10] = "changed 10"
	return attach(numbered(), changed, before_attach)
end

---@param buf integer
local function highlighted(buf)
	local rows = {}
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
		table.insert(rows, { mark[2], mark[4].line_hl_group })
	end
	return rows
end

---@param lines string[]
---@param at integer
---@param inserted string[]
local function with_lines(lines, at, inserted)
	for i, line in ipairs(inserted) do
		table.insert(lines, at + i - 1, line)
	end
	return lines
end

test("attach shows the diff in the window of the file", function()
	local view = attach_changed_line_10()

	h.eq(view, vim.api.nvim_get_current_buf())
	h.eq("diffmagik://a.txt@HEAD:inline", vim.api.nvim_buf_get_name(view))
end)

test("attach puts the deleted lines as real lines above the added ones", function()
	local view = attach_changed_line_10()

	h.eq(with_lines(numbered(), 11, { "changed 10" }), h.lines(view))
	h.eq({ { 9, DELETED }, { 10, ADDED } }, highlighted(view))
end)

test("attach puts a deleted first line above the new first line", function()
	local changed = numbered()
	table.remove(changed, 1)
	local view = attach(numbered(), changed)

	h.eq(numbered(), h.lines(view))
	h.eq({ { 0, DELETED } }, highlighted(view))
end)

test("attach puts a deleted middle line below the line before it", function()
	local changed = numbered()
	table.remove(changed, 10)
	local view = attach(numbered(), changed)

	h.eq(numbered(), h.lines(view))
	h.eq({ { 9, DELETED } }, highlighted(view))
end)

test("the cursor moves onto the deleted lines", function()
	attach_changed_line_10()
	vim.api.nvim_win_set_cursor(0, { 9, 0 })

	h.press("j")

	h.eq("line 10", vim.api.nvim_get_current_line())
end)

test("attach folds everything but the hunk and its context", function()
	attach_changed_line_10()

	local folds = {}
	local expected = {}
	for lnum = 1, 21 do
		table.insert(folds, FileDiff.foldexpr(lnum))
		table.insert(expected, (lnum >= 7 and lnum <= 14) and "0" or "1")
	end

	h.eq("expr", vim.wo.foldmethod)
	h.eq(expected, folds)
end)

test("detach restores the fold options the window had before", function()
	local view = attach_changed_line_10(function()
		vim.wo.foldmethod = "indent"
		vim.wo.foldlevel = 2
	end)

	FileDiff.detach(view)

	h.eq("indent", vim.wo.foldmethod)
	h.eq(2, vim.wo.foldlevel)
end)

test("an attaching LSP gets the hunk folds put back", function()
	local view = attach_changed_line_10()
	vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"

	vim.api.nvim_exec_autocmds("LspAttach", { buffer = view, data = { client_id = 0 } })
	h.flush()

	h.eq("expr", vim.wo.foldmethod)
	h.eq(FOLDEXPR, vim.wo.foldexpr)
end)

test("editing the file redraws the diff", function()
	local view, source = attach_changed_line_10()

	vim.api.nvim_buf_set_lines(source, 1, 2, false, { "edited 2" })
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = source })

	h.eq(with_lines(with_lines(numbered(), 3, { "edited 2" }), 12, { "changed 10" }), h.lines(view))
	h.eq({ { 1, DELETED }, { 2, ADDED }, { 10, DELETED }, { 11, ADDED } }, highlighted(view))
end)
