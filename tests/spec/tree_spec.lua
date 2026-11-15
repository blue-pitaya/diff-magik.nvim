local h = require("helpers")
local TreeNode = require("diff-magik.tree")

local test = h.test

---@param path string
---@return GitEntry
local function entry(path)
	return { path = path, status = "M", staged = false, unstaged = true }
end

local function build()
	local tree = TreeNode.new({
		entry("b.txt"),
		entry("a/z.txt"),
		entry("a/c/d.txt"),
		entry("a.txt"),
	})
	tree:sort()
	return tree
end

---@param tree TreeNode
local function rows(tree)
	local flat = {}
	tree:flatten(0, flat)
	return vim.tbl_map(function(item)
		return { item.depth, item.node.path }
	end, flat)
end

---@param tree TreeNode
---@param names string[]
local function find(tree, names)
	local node = tree
	for _, name in ipairs(names) do
		node = node.dirs_by_name[name]
	end
	return node
end

test("flatten lists directories before files, each level sorted by name", function()
	h.eq({
		{ 0, "a/" },
		{ 1, "a/c/" },
		{ 2, "a/c/d.txt" },
		{ 1, "a/z.txt" },
		{ 0, "a.txt" },
		{ 0, "b.txt" },
	}, rows(build()))
end)

test("flatten skips the contents of a collapsed directory", function()
	local tree = build()
	find(tree, { "a", "c" }).expanded = false

	h.eq({
		{ 0, "a/" },
		{ 1, "a/c/" },
		{ 1, "a/z.txt" },
		{ 0, "a.txt" },
		{ 0, "b.txt" },
	}, rows(tree))
end)

test("collect_collapsed and apply_collapsed carry collapsed directories over to a new tree", function()
	local old = build()
	find(old, { "a", "c" }).expanded = false

	local collapsed = {}
	old:collect_collapsed(collapsed)
	h.eq({ ["a/c/"] = true }, collapsed)

	local new = build()
	new:apply_collapsed(collapsed)
	h.eq(rows(old), rows(new))
end)
