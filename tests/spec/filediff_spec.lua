local h = require("helpers")
local Git = require("diff-magik.git")
local FileDiff = require("diff-magik.filediff")

local test = h.test

local ns = vim.api.nvim_create_namespace("diff-magik.filediff")
local FOLDEXPR = "v:lua.require'diff-magik.filediff'.foldexpr(v:lnum)"

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
local function attach(original, changed, before_attach)
	local root = h.repo({ ["a.txt"] = original })
	h.write(root .. "/a.txt", changed)

	require("diff-magik").setup()
	h.edit(root .. "/a.txt")
	if before_attach then
		before_attach()
	end
	local buf = vim.api.nvim_get_current_buf()
	FileDiff.attach(Git.from_root(root), "a.txt", buf)

	return buf
end

---@param before_attach? fun()
local function attach_changed_line_10(before_attach)
	local changed = numbered()
	changed[10] = "changed 10"
	return attach(numbered(), changed, before_attach)
end

---@param buf integer
local function marks(buf)
	return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

---@param buf integer
local function added_rows(buf)
	local rows = {}
	for _, mark in ipairs(marks(buf)) do
		if mark[4].line_hl_group then
			table.insert(rows, mark[2])
		end
	end
	return rows
end

---@param buf integer
local function deleted_texts(buf)
	local texts = {}
	for _, mark in ipairs(marks(buf)) do
		for _, chunks in ipairs(mark[4].virt_lines or {}) do
			table.insert(texts, chunks[1][1])
		end
	end
	return texts
end

---@param buf integer
local function deleted_lines(buf)
	local deleted = {}
	for _, mark in ipairs(marks(buf)) do
		for _, chunks in ipairs(mark[4].virt_lines or {}) do
			table.insert(deleted, { mark[2], vim.trim(chunks[1][1]) })
		end
	end
	return deleted
end

---@param buf integer
local function deleted_placement(buf)
	local placement = {}
	for _, mark in ipairs(marks(buf)) do
		if mark[4].virt_lines then
			table.insert(placement, { mark[2], mark[4].virt_lines_above == true })
		end
	end
	return placement
end

test("attach highlights the added lines", function()
	local buf = attach_changed_line_10()

	h.eq({ 9 }, added_rows(buf))
end)

test("attach draws the deleted lines as virtual lines at the hunk", function()
	local buf = attach_changed_line_10()

	h.eq({ { 9, "line 10" } }, deleted_lines(buf))
end)

test("attach draws a deleted first line above the new first line", function()
	local changed = numbered()
	table.remove(changed, 1)
	local buf = attach(numbered(), changed)

	h.eq({ { 0, "line 1" } }, deleted_lines(buf))
	h.eq({ { 0, true } }, deleted_placement(buf))
end)

test("attach draws a deleted middle line below the line before it", function()
	local changed = numbered()
	table.remove(changed, 10)
	local buf = attach(numbered(), changed)

	h.eq({ { 8, "line 10" } }, deleted_lines(buf))
	h.eq({ { 8, false } }, deleted_placement(buf))
end)

test("attach expands tabs in the deleted lines", function()
	local original = numbered()
	original[10] = "\tx"
	local changed = numbered()
	changed[10] = "changed 10"
	local buf = attach(original, changed)

	h.eq("        x", deleted_texts(buf)[1]:sub(1, 9))
end)

test("attach pads the deleted lines to the text width of the window", function()
	local buf = attach_changed_line_10()
	local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]

	h.eq(info.width - info.textoff, vim.fn.strdisplaywidth(deleted_texts(buf)[1]))
end)

test("attach folds everything but the hunk and its context", function()
	attach_changed_line_10()

	local folds = {}
	local expected = {}
	for lnum = 1, 20 do
		table.insert(folds, FileDiff.foldexpr(lnum))
		table.insert(expected, (lnum >= 7 and lnum <= 13) and "0" or "1")
	end

	h.eq("expr", vim.wo.foldmethod)
	h.eq(expected, folds)
end)

test("detach restores the fold options the window had before", function()
	local buf = attach_changed_line_10(function()
		vim.wo.foldmethod = "indent"
		vim.wo.foldlevel = 2
	end)

	FileDiff.detach(buf)

	h.eq("indent", vim.wo.foldmethod)
	h.eq(2, vim.wo.foldlevel)
end)

test("an attaching LSP gets the hunk folds put back", function()
	local buf = attach_changed_line_10()
	vim.wo.foldexpr = "v:lua.vim.lsp.foldexpr()"

	vim.api.nvim_exec_autocmds("LspAttach", { buffer = buf, data = { client_id = 0 } })
	h.flush()

	h.eq("expr", vim.wo.foldmethod)
	h.eq(FOLDEXPR, vim.wo.foldexpr)
end)

test("editing the buffer redraws the diff", function()
	local buf = attach_changed_line_10()

	vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "edited 2" })
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })

	h.eq({ 1, 9 }, added_rows(buf))
	h.eq({ { 1, "line 2" }, { 9, "line 10" } }, deleted_lines(buf))
end)
