local M = {}

---@param msg string
function M.info(msg)
	vim.notify("DiffMagik: " .. msg, vim.log.levels.INFO)
end

---@param msg string|integer
function M.error(msg)
	vim.notify("DiffMagik: " .. msg, vim.log.levels.ERROR)
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

---@param path string
---@return string? nil when no part of the path exists
function M.nearest_existing_parent_dir(path)
	while not vim.uv.fs_stat(path) do
		local parent = vim.fs.dirname(path)
		if not parent or parent == path then
			return nil
		end
		path = parent
	end
	return path
end

---@param err string
---@return any value always nil
---@return string err
function M.fail(err)
	return nil, err
end

return M
