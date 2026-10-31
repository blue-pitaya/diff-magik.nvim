local M = {}

---@type { name: string, fn: fun() }[]
M.cases = {}

---@param name string
---@param fn fun()
function M.test(name, fn)
	table.insert(M.cases, { name = name, fn = fn })
end

---@param expected any
---@param actual any
function M.eq(expected, actual)
	if not vim.deep_equal(expected, actual) then
		error(("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

---@param dir string
---@param args string[]
---@return string
function M.git(dir, args)
	local cmd = { "git", "-C", dir }
	vim.list_extend(cmd, args)
	local result = vim.system(cmd, { text = true }):wait()
	if result.code ~= 0 then
		error(("git %s failed: %s"):format(table.concat(args, " "), result.stderr), 2)
	end
	return result.stdout
end

---@param path string
---@param lines string[]
function M.write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end

---@param path string
---@return string[]
function M.read(path)
	return vim.fn.readfile(path)
end

---@param committed? table<string, string[]>
---@return string
function M.repo(committed)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	dir = assert(vim.uv.fs_realpath(dir))

	M.git(dir, { "init", "--quiet" })

	if committed then
		for rel, lines in pairs(committed) do
			M.write(vim.fs.joinpath(dir, rel), lines)
		end
		M.git(dir, { "add", "--all" })
		M.git(dir, { "commit", "--quiet", "--message", "initial" })
	end

	return dir
end

---@param path string
function M.edit(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
end

---@param keys string
function M.press(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

---@param ms? integer
function M.flush(ms)
	vim.wait(ms or 50)
end

---@param name string
---@return integer
function M.buf_named(name)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(buf) == name then
			return buf
		end
	end
	error(("no buffer named '%s'"):format(name), 2)
end

---@param buf integer
---@return integer
function M.win_of(buf)
	return vim.fn.win_findbuf(buf)[1]
end

---@return string[]
function M.win_names()
	local names = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		table.insert(names, vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))
	end
	table.sort(names)
	return names
end

---@param buf integer
---@return string[]
function M.lines(buf)
	return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

return M
