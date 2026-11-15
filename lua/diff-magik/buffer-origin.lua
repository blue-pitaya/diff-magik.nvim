local Git = require("diff-magik.git")
local util = require("diff-magik.util")

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
local function from_tag(bufnr)
	local root, rel = vim.b[bufnr].diffmagik_root, vim.b[bufnr].diffmagik_path
	if root and rel then
		return BufferOrigin.new(root, rel)
	end
	return nil
end

---The buffer's tag when it has one, otherwise the repo and path of the file it shows.
---@param bufnr integer
---@return BufferOrigin origin
---@return string? err
function BufferOrigin.of(bufnr)
	local tagged = from_tag(bufnr)
	if tagged then
		return tagged, nil
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return util.fail("current buffer has no file")
	end

	local repo, err = Git.new(vim.fs.dirname(path))
	if err ~= nil then
		return util.fail(err)
	end

	local rel = vim.fs.relpath(repo.root, path)
	if not rel then
		return util.fail("failed to resolve path relative to repo root")
	end

	return BufferOrigin.new(repo.root, rel), nil
end

---@param bufnr integer
function BufferOrigin:tag(bufnr)
	vim.b[bufnr].diffmagik_root = self.root
	vim.b[bufnr].diffmagik_path = self.rel
end

return BufferOrigin
