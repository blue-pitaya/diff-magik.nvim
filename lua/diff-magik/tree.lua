---@class TreeNode
---@field name string
---@field is_dir boolean
---@field expanded boolean|nil only set on directory nodes
---@field children TreeNode[]|nil only set on directory nodes
---@field dirs_by_name table<string, TreeNode>|nil only set on directory nodes
---@field entry GitEntry|nil only set on file nodes
local TreeNode = {}
TreeNode.__index = TreeNode

---@class TreeFlatItem
---@field node TreeNode
---@field depth integer

---@param entries GitEntry[]
function TreeNode.new(entries)
	local root = setmetatable({ name = "", is_dir = true, expanded = true, children = {}, dirs_by_name = {} }, TreeNode)

	for _, entry in ipairs(entries) do
		local node = root
		local start = 1
		while true do
			local slash = entry.path:find("/", start, true)
			if not slash then
				local name = entry.path:sub(start)
				table.insert(node.children, setmetatable({ name = name, is_dir = false, entry = entry }, TreeNode))
				break
			end

			local name = entry.path:sub(start, slash - 1)
			local dir = node.dirs_by_name[name]
			if not dir then
				dir = setmetatable(
					{ name = name, is_dir = true, expanded = true, children = {}, dirs_by_name = {} },
					TreeNode
				)
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

return TreeNode
