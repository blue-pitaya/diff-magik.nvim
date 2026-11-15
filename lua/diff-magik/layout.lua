local util = require("diff-magik.util")

local SIDEBAR_WIDTH = 40

local SIDEBAR_WIN_OPTS = {
	winfixwidth = true,
	number = false,
	relativenumber = false,
	signcolumn = "no",
	wrap = true,
	cursorline = true,
	cursorlineopt = "line",
}

local SIDEBAR_WIN_OPT_NAMES = vim.tbl_keys(SIDEBAR_WIN_OPTS)

---@class Layout
---@field diff_split DiffSplit
---@field file_diffs FileDiffManager
---@field sidebar_win? integer
---@field sidebar_buf? integer
---@field main_win? integer
---@field main_opts? table<string, any> main window options saved before the sidebar split it
---@field diff_style DiffMagikDiffStyle
local Layout = {}
Layout.__index = Layout

---@param config Config
---@param diff_split DiffSplit
---@param file_diffs FileDiffManager
---@return Layout
function Layout.new(config, diff_split, file_diffs)
	return setmetatable({
		diff_split = diff_split,
		file_diffs = file_diffs,
		diff_style = config.diff_style,
	}, Layout)
end

---@return integer?
local function reusable_win()
	local candidates = vim.api.nvim_tabpage_list_wins(0)
	table.insert(candidates, 1, vim.api.nvim_get_current_win())

	for _, winid in ipairs(candidates) do
		if
			vim.api.nvim_win_is_valid(winid)
			and not util.is_floating(winid)
			and vim.bo[vim.api.nvim_win_get_buf(winid)].buftype == ""
		then
			return winid
		end
	end
end

---@return integer?
function Layout:get_sidebar_buf()
	return self.sidebar_buf
end

---@return boolean
function Layout:has_sidebar()
	return self.sidebar_win ~= nil and vim.api.nvim_win_is_valid(self.sidebar_win)
end

function Layout:forget_sidebar()
	self.sidebar_win = nil
	self.sidebar_buf = nil
end

function Layout:apply_sidebar_width()
	if self:has_sidebar() then
		vim.api.nvim_win_set_width(self.sidebar_win, SIDEBAR_WIDTH)
	end
end

---@return DiffMagikDiffStyle
function Layout:toggle_diff_style()
	self.diff_style = self.diff_style == "split" and "inline" or "split"

	if self.diff_style == "inline" then
		self.diff_split:close()
	else
		self.file_diffs:clear()
	end

	return self.diff_style
end

---@return boolean
function Layout:focus_sidebar()
	if not self:has_sidebar() then
		return false
	end
	vim.api.nvim_set_current_win(self.sidebar_win)
	return true
end

---@return integer?
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

---@return integer
function Layout:ensure_main()
	if self.main_win ~= nil and vim.api.nvim_win_is_valid(self.main_win) then
		return self.main_win
	end

	local reused = reusable_win()
	if reused then
		self.main_win = reused
		return reused
	end

	local anchor = self:has_sidebar() and self.sidebar_win or vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(anchor)
	vim.cmd.vsplit({ mods = { split = "belowright" } })
	self.main_win = vim.api.nvim_get_current_win()

	util.set_wo(self.main_win, self.main_opts or {})

	if anchor == self.sidebar_win then
		self:apply_sidebar_width()
	end

	return self.main_win
end

---@return integer sidebar_buf
function Layout:open_sidebar()
	self.main_win = reusable_win() or vim.api.nvim_get_current_win()
	self.main_opts = util.save_wo(self.main_win, SIDEBAR_WIN_OPT_NAMES)
	vim.api.nvim_set_current_win(self.main_win)

	vim.cmd.vsplit({ mods = { split = "topleft" } })
	self.sidebar_win = vim.api.nvim_get_current_win()
	self:apply_sidebar_width()

	self.sidebar_buf = util.scratch_buf("diffmagik://changes")
	vim.api.nvim_win_set_buf(self.sidebar_win, self.sidebar_buf)
	vim.bo[self.sidebar_buf].filetype = "diffmagik"

	util.set_wo(self.sidebar_win, SIDEBAR_WIN_OPTS)

	return self.sidebar_buf
end

---@param repo Git
---@param rel string
---@return integer[]? bufs buffers of the opened diff
function Layout:open_file(repo, rel)
	local main_win = self:ensure_main()
	vim.api.nvim_set_current_win(main_win)

	local ok, err = pcall(vim.cmd.edit, { args = { vim.fs.joinpath(repo.root, rel) } })
	if not ok then
		util.error(err)
		return nil
	end

	local bufnr = vim.api.nvim_win_get_buf(main_win)

	if self.diff_style == "inline" then
		local view
		view, err = self.file_diffs:attach(repo, rel, bufnr)
		if err ~= nil then
			util.error(err)
			return { bufnr }
		end
		return { view }
	end

	self.file_diffs:detach(bufnr)
	local head_buf = self.diff_split:open_against_head(repo, rel)

	return { bufnr, head_buf }
end

function Layout:reload_main()
	if self.main_win == nil or not vim.api.nvim_win_is_valid(self.main_win) then
		return
	end

	local source = self.file_diffs:source_of(vim.api.nvim_win_get_buf(self.main_win))
	if source then
		vim.api.nvim_buf_call(source, function()
			pcall(vim.cmd.edit, { bang = true })
		end)
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
	self:forget_sidebar()
end

---@param winid integer
---@return boolean
function Layout:in_split_view(winid)
	return self.diff_style == "split"
		and self.sidebar_win ~= nil
		and vim.api.nvim_win_is_valid(self.sidebar_win)
		and self.diff_split:contains(self.main_win)
		and (winid == self.sidebar_win or self.diff_split:contains(winid))
end

function Layout:close_split_view()
	local main_buf = self.diff_split:close()

	if self.main_win ~= nil and vim.api.nvim_win_is_valid(self.main_win) then
		self:close()
		pcall(vim.api.nvim_win_close, self.main_win, true)
		return
	end

	if self:has_sidebar() and not pcall(vim.api.nvim_win_close, self.sidebar_win, true) then
		local buf = main_buf and vim.api.nvim_buf_is_valid(main_buf) and main_buf or vim.api.nvim_create_buf(true, false)
		vim.api.nvim_win_set_buf(self.sidebar_win, buf)
		util.set_wo(self.sidebar_win, self.main_opts or {})
		self.main_win = self.sidebar_win
	end

	self:forget_sidebar()
end

return Layout
