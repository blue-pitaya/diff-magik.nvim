local h = require("helpers")
local TreeNode = require("diff-magik.tree")
local Config = require("diff-magik.config")
local render = require("diff-magik.render")

local test = h.test

local ns = vim.api.nvim_create_namespace("diff-magik")

local function rendered()
	local tree = TreeNode.new({
		{ path = "dir/x.txt", status = "M", staged = true, unstaged = false },
		{ path = "y.txt", status = "A", staged = true, unstaged = true },
		{ path = "z.txt", status = "D", staged = false, unstaged = true },
	})
	tree:sort()

	local flat = {}
	tree:flatten(0, flat)

	local buf = vim.api.nvim_create_buf(false, true)
	local width = render(buf, flat, Config.new().highlights)
	return buf, width
end

test("render writes one row per tree item with the staging markers", function()
	local buf = rendered()

	h.eq({
		"▾ dir/",
		"  M x.txt (S)",
		"A y.txt (S*)",
		"D z.txt",
	}, h.lines(buf))
end)

test("render returns the widest row, counting room for the widest staging marker", function()
	local _, width = rendered()

	h.eq(14, width)
end)

test("render highlights directories, status letters and staging markers", function()
	local buf = rendered()

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
