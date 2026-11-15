---@class BufferOrigin
---@field root string repo top level
---@field rel string file path relative to root
local BufferOrigin = {}
BufferOrigin.__index = BufferOrigin

---@param root string
---@param rel string
---@return BufferOrigin
function BufferOrigin.new(root, rel)
	return setmetatable({ root = root, rel = rel }, BufferOrigin)
end

---@param bufnr integer
---@return BufferOrigin?
function BufferOrigin.of(bufnr)
	local root, rel = vim.b[bufnr].diffmagik_root, vim.b[bufnr].diffmagik_path
	if root and rel then
		return BufferOrigin.new(root, rel)
	end
	return nil
end

---@param bufnr integer
function BufferOrigin:tag(bufnr)
	vim.b[bufnr].diffmagik_root = self.root
	vim.b[bufnr].diffmagik_path = self.rel
end

return BufferOrigin
