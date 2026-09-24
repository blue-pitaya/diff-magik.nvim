local M = {}

---@param winid integer|nil
---@return boolean
function M.win_valid(winid)
	return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
---@return boolean
function M.is_floating(winid)
	return vim.api.nvim_win_get_config(winid).relative ~= ""
end

---@param name string
---@return integer bufnr an unlisted scratch buffer, wiped once hidden
function M.scratch_buf(name)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, name)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	return buf
end

---@param bufnr integer
---@param root string absolute path to the repo's top level
---@param rel string path to the file, relative to `root`
function M.tag_buffer(bufnr, root, rel)
	vim.b[bufnr].diffmagik_root = root
	vim.b[bufnr].diffmagik_path = rel
end

---@param bufnr integer
---@return string|nil root
---@return string|nil rel
function M.buffer_target(bufnr)
	return vim.b[bufnr].diffmagik_root, vim.b[bufnr].diffmagik_path
end

return M
