local DiffSplit = require("diff-magik.diffsplit")

local SIDEBAR_WIDTH = 40

local SIDEBAR_WIN_OPTS = {
	winfixwidth = true,
	number = false,
	relativenumber = false,
	signcolumn = "no",
	wrap = false,
	cursorline = true,
	cursorlineopt = "line",
}

---@class Layout
---@field sidebar_win integer|nil
---@field sidebar_buf integer|nil
---@field main_win integer|nil the window holding the working copy
---@field main_opts table<string, any>|nil `SIDEBAR_WIN_OPTS` as they were before the sidebar existed
---@field diffsplit DiffSplit owns the HEAD pane
local Layout = {}
Layout.__index = Layout

function Layout.new()
	return setmetatable({ diffsplit = DiffSplit.new() }, Layout)
end

---@param winid integer|nil
local function win_valid(winid)
	return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
local function is_floating(winid)
	return vim.api.nvim_win_get_config(winid).relative ~= ""
end

---@param winid integer
---@return table<string, any>
local function capture_win_opts(winid)
	local opts = {}
	for name in pairs(SIDEBAR_WIN_OPTS) do
		opts[name] = vim.wo[winid][name]
	end
	return opts
end

---@param winid integer
---@param opts table<string, any>
local function apply_win_opts(winid, opts)
	for name, value in pairs(opts) do
		vim.wo[winid][name] = value
	end
end

function Layout:has_sidebar()
	return win_valid(self.sidebar_win)
end

---@return boolean ok
function Layout:focus_sidebar()
	if not self:has_sidebar() then
		return false
	end
	vim.api.nvim_set_current_win(self.sidebar_win)
	return true
end

---@return integer|nil
function Layout:sidebar_cursor()
	if not self:has_sidebar() then
		return nil
	end
	return vim.api.nvim_win_get_cursor(self.sidebar_win)[1]
end

---@param line integer
function Layout:set_sidebar_cursor(line)
	if self:has_sidebar() then
		vim.api.nvim_win_set_cursor(self.sidebar_win, { line, 0 })
	end
end

---@return integer|nil winid a window that may host the working copy
function Layout:reusable_win()
	local candidates = vim.api.nvim_tabpage_list_wins(0)
	table.insert(candidates, 1, vim.api.nvim_get_current_win())

	for _, winid in ipairs(candidates) do
		if
			win_valid(winid)
			and winid ~= self.sidebar_win
			and winid ~= self.diffsplit.head_win
			and not is_floating(winid)
			and vim.bo[vim.api.nvim_win_get_buf(winid)].buftype == ""
		then
			return winid
		end
	end
end

---@return integer winid recreated whenever the previous main window was closed
function Layout:ensure_main()
	if win_valid(self.main_win) then
		return self.main_win
	end

	local reused = self:reusable_win()
	if reused then
		self.main_win = reused
		return reused
	end

	local anchor = self:has_sidebar() and self.sidebar_win or vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(anchor)
	vim.cmd.vsplit({ mods = { split = "belowright" } })
	self.main_win = vim.api.nvim_get_current_win()

	apply_win_opts(self.main_win, self.main_opts or {})

	if anchor == self.sidebar_win then
		vim.api.nvim_win_set_width(self.sidebar_win, SIDEBAR_WIDTH)
	end

	return self.main_win
end

---@return integer bufnr of the sidebar
function Layout:open_sidebar()
	self.main_win = self:reusable_win() or vim.api.nvim_get_current_win()
	self.main_opts = capture_win_opts(self.main_win)
	vim.api.nvim_set_current_win(self.main_win)

	vim.cmd.vsplit({ mods = { split = "topleft" } })
	self.sidebar_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_width(self.sidebar_win, SIDEBAR_WIDTH)

	self.sidebar_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(self.sidebar_win, self.sidebar_buf)

	vim.api.nvim_buf_set_name(self.sidebar_buf, "diffmagik://changes")
	vim.bo[self.sidebar_buf].buftype = "nofile"
	vim.bo[self.sidebar_buf].bufhidden = "wipe"
	vim.bo[self.sidebar_buf].swapfile = false
	vim.bo[self.sidebar_buf].filetype = "diffmagik"

	apply_win_opts(self.sidebar_win, SIDEBAR_WIN_OPTS)

	return self.sidebar_buf
end

---@param repo Git
---@param rel string path to the file, relative to `repo.root`
---@return integer[]|nil bufs the buffers making up the diff
function Layout:open_file(repo, rel)
	local main_win = self:ensure_main()
	vim.api.nvim_set_current_win(main_win)

	local ok, err = pcall(vim.cmd.edit, { args = { vim.fs.joinpath(repo.root, rel) } })
	if not ok then
		vim.notify(("DiffMagik: %s"):format(err), vim.log.levels.ERROR)
		return nil
	end

	self.diffsplit:open_against_head(repo, rel)

	local bufs = { vim.api.nvim_win_get_buf(main_win) }
	if win_valid(self.diffsplit.head_win) then
		table.insert(bufs, vim.api.nvim_win_get_buf(self.diffsplit.head_win))
	end
	return bufs
end

--- Drops whatever the working-copy pane holds in favour of what is on disk now.
function Layout:reload_main()
	if not win_valid(self.main_win) then
		return
	end

	vim.api.nvim_win_call(self.main_win, function()
		pcall(vim.cmd.edit, { bang = true })
	end)
end

function Layout:close()
	if self:has_sidebar() then
		vim.api.nvim_win_close(self.sidebar_win, true)
	end
	self.sidebar_win = nil
	self.sidebar_buf = nil
end

return Layout
