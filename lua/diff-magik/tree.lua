---@class TreeNode
---@field name string
---@field path string
---@field is_dir boolean
---@field expanded? boolean
---@field children? TreeNode[]
---@field dirs_by_name? table<string, TreeNode>
---@field entry? GitEntry
local TreeNode = {}
TreeNode.__index = TreeNode

---@class TreeFlatItem
---@field node TreeNode
---@field depth integer

---@param name string
---@param path string
---@return TreeNode
local function new_dir(name, path)
	return setmetatable(
		{ name = name, path = path, is_dir = true, expanded = true, children = {}, dirs_by_name = {} },
		TreeNode
	)
end

---@param entries GitEntry[]
---@return TreeNode
function TreeNode.new(entries)
	local root = new_dir("", "")

	for _, entry in ipairs(entries) do
		local node = root
		local start = 1
		while true do
			local slash = entry.path:find("/", start, true)
			if not slash then
				local file = { name = entry.path:sub(start), path = entry.path, is_dir = false, entry = entry }
				table.insert(node.children, setmetatable(file, TreeNode))
				break
			end

			local name = entry.path:sub(start, slash - 1)
			local dir = node.dirs_by_name[name]
			if not dir then
				dir = new_dir(name, entry.path:sub(1, slash))
				node.dirs_by_name[name] = dir
				table.insert(node.children, dir)
			end
			node = dir
			start = slash + 1
		end
	end

	return root
end

function TreeNode:sort()
	table.sort(self.children, function(a, b)
		if a.is_dir ~= b.is_dir then
			return a.is_dir
		end
		return a.name < b.name
	end)
	for _, child in ipairs(self.children) do
		if child.is_dir then
			child:sort()
		end
	end
end

---@param depth integer
---@param out TreeFlatItem[]
function TreeNode:flatten(depth, out)
	for _, child in ipairs(self.children) do
		table.insert(out, { node = child, depth = depth })
		if child.is_dir and child.expanded then
			child:flatten(depth + 1, out)
		end
	end
end

---@param out table<string, boolean>
function TreeNode:collect_collapsed(out)
	for _, child in ipairs(self.children) do
		if child.is_dir then
			if not child.expanded then
				out[child.path] = true
			end
			child:collect_collapsed(out)
		end
	end
end

---@param collapsed table<string, boolean>
function TreeNode:apply_collapsed(collapsed)
	for _, child in ipairs(self.children) do
		if child.is_dir then
			if collapsed[child.path] then
				child.expanded = false
			end
			child:apply_collapsed(collapsed)
		end
	end
end

return TreeNode
