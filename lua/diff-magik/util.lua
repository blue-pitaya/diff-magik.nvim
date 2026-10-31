local M = {}

---@param msg string
function M.info(msg)
	vim.notify("DiffMagik: " .. msg, vim.log.levels.INFO)
end

---@param msg string
function M.error(msg)
	vim.notify("DiffMagik: " .. msg, vim.log.levels.ERROR)
end

---@param winid integer?
---@return boolean
function M.win_valid(winid)
	return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
---@return boolean
function M.is_floating(winid)
	return vim.api.nvim_win_get_config(winid).relative ~= ""
end

---@param winid integer
---@param names string[]
---@return table<string, any>
function M.save_wo(winid, names)
	local saved = {}
	for _, name in ipairs(names) do
		saved[name] = vim.api.nvim_get_option_value(name, { scope = "local", win = winid })
	end
	return saved
end

---@param winid integer
---@param opts table<string, any>
function M.set_wo(winid, opts)
	for name, value in pairs(opts) do
		vim.api.nvim_set_option_value(name, value, { scope = "local", win = winid })
	end
end

---@param name string
---@return integer
function M.scratch_buf(name)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, name)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	return buf
end

---@param bufnr integer
---@param root string
---@param rel string
function M.tag_buffer(bufnr, root, rel)
	vim.b[bufnr].diffmagik_root = root
	vim.b[bufnr].diffmagik_path = rel
end

---@param bufnr integer
---@return string?
---@return string?
function M.buffer_target(bufnr)
	return vim.b[bufnr].diffmagik_root, vim.b[bufnr].diffmagik_path
end

return M
