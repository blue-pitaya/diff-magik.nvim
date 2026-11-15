local h = require("helpers")
local ChangeList = require("diff-magik.change-list")
local Config = require("diff-magik.config")

local test = h.test

local ns = vim.api.nvim_create_namespace("diff-magik.change-list")

---@return ChangeList
local function new_list()
	return ChangeList.new({
		{ path = "dir/x.txt", status = "M", staged = true, unstaged = false },
		{ path = "y.txt", status = "A", staged = true, unstaged = true },
		{ path = "z.txt", status = "D", staged = false, unstaged = true },
	}, Config.new().highlights)
end

---@param list ChangeList
---@return integer
local function drawn(list)
	local buf = vim.api.nvim_create_buf(false, true)
	list:draw(buf)
	return buf
end

test("draw writes one row per tree item with the staging markers", function()
	h.eq({
		"▾ dir/",
		"  M x.txt (S)",
		"A y.txt (S*)",
		"D z.txt",
	}, h.lines(drawn(new_list())))
end)

test("draw highlights directories, status letters and staging markers", function()
	local buf = drawn(new_list())

	local marks = vim.tbl_map(function(mark)
		local details = mark[4]
		return { mark[2], mark[3], details.hl_group or details.line_hl_group }
	end, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }))

	h.eq({
		{ 0, 0, "Directory" },
		{ 1, 2, "Changed" },
		{ 1, 10, "Added" },
		{ 2, 0, "Added" },
		{ 2, 8, "DiagnosticWarn" },
		{ 3, 0, "Removed" },
	}, marks)
end)

test("row, entry and line_of map sidebar lines to the tree", function()
	local list = new_list()

	h.eq("dir/", list:row(1).node.path)
	h.eq(nil, list:entry(1))
	h.eq("dir/x.txt", list:entry(2).path)
	h.eq(3, list:line_of("y.txt"))
	h.eq(nil, list:row(nil))
end)

test("toggle collapses a directory and only toggles directory rows", function()
	local list = new_list()

	h.eq(true, list:toggle(1))
	h.eq({ "▸ dir/", "A y.txt (S*)", "D z.txt" }, h.lines(drawn(list)))
	h.eq(false, list:toggle(2))
end)

test("next_file skips directory rows and stops at either end", function()
	local list = new_list()

	h.eq(3, list:next_file(2, 1))
	h.eq(nil, list:next_file(4, 1))
	h.eq(nil, list:next_file(2, -1))
end)

test("update keeps collapsed directories collapsed", function()
	local list = new_list()
	list:toggle(1)

	list:update({
		{ path = "dir/x.txt", status = "M", staged = false, unstaged = true },
		{ path = "w.txt", status = "A", staged = false, unstaged = true },
	})

	h.eq({ "▸ dir/", "A w.txt" }, h.lines(drawn(list)))
end)
