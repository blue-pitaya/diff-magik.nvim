local DiffSplit = require("diff-magik.diffsplit")
local FileDiff = require("diff-magik.filediff")
local util = require("diff-magik.util")
local config = require("diff-magik.config")

local win_valid = util.win_valid
local is_floating = util.is_floating

local SIDEBAR_MIN_WIDTH = 40
local SIDEBAR_MAX_WIDTH = 50
local SIDEBAR_MAX_RATIO = 0.5

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

---@class LayoutState
---@field sidebar_win? integer
---@field sidebar_buf? integer
---@field main_win? integer
---@field main_opts? table<string, any>
---@field sidebar_width integer
---@field content_width integer
---@field width_mode DiffMagikWidthMode
---@field diff_style DiffMagikDiffStyle
local state = {
	sidebar_width = SIDEBAR_MIN_WIDTH,
	content_width = SIDEBAR_MIN_WIDTH,
}

local M = {}

function M.setup()
	state.width_mode = config.options.width_mode
	state.diff_style = config.options.diff_style
end

---@return integer?
function M.sidebar_buf()
	return state.sidebar_buf
end

function M.has_sidebar()
	return win_valid(state.sidebar_win)
end

local function forget_sidebar()
	state.sidebar_win = nil
	state.sidebar_buf = nil
end

local function apply_sidebar_width()
	local max = math.min(SIDEBAR_MAX_WIDTH, math.max(SIDEBAR_MIN_WIDTH, math.floor(vim.o.columns * SIDEBAR_MAX_RATIO)))
	local wanted = state.width_mode == "constant" and SIDEBAR_MIN_WIDTH or state.content_width
	state.sidebar_width = math.min(math.max(wanted, SIDEBAR_MIN_WIDTH), max)

	if M.has_sidebar() then
		vim.api.nvim_win_set_width(state.sidebar_win, state.sidebar_width)
	end
end

---@param width integer
function M.fit_sidebar(width)
	state.content_width = width
	apply_sidebar_width()
end

---@return DiffMagikWidthMode
function M.toggle_width_mode()
	state.width_mode = state.width_mode == "expand" and "constant" or "expand"
	apply_sidebar_width()
	return state.width_mode
end

---@return DiffMagikDiffStyle
function M.toggle_diff_style()
	state.diff_style = state.diff_style == "split" and "inline" or "split"

	if state.diff_style == "inline" then
		DiffSplit.close()
	else
		FileDiff.clear()
	end

	return state.diff_style
end

---@return boolean
function M.focus_sidebar()
	if not M.has_sidebar() then
		return false
	end
	vim.api.nvim_set_current_win(state.sidebar_win)
	return true
end

---@return integer?
function M.sidebar_cursor()
	if not M.has_sidebar() then
		return nil
	end
	return vim.api.nvim_win_get_cursor(state.sidebar_win)[1]
end

---@param line integer
function M.set_sidebar_cursor(line)
	if M.has_sidebar() then
		vim.api.nvim_win_set_cursor(state.sidebar_win, { line, 0 })
	end
end

---@return integer?
local function reusable_win()
	local candidates = vim.api.nvim_tabpage_list_wins(0)
	table.insert(candidates, 1, vim.api.nvim_get_current_win())

	for _, winid in ipairs(candidates) do
		if
			win_valid(winid)
			and not is_floating(winid)
			and vim.bo[vim.api.nvim_win_get_buf(winid)].buftype == ""
		then
			return winid
		end
	end
end

---@return integer
local function ensure_main()
	if win_valid(state.main_win) then
		return state.main_win
	end

	local reused = reusable_win()
	if reused then
		state.main_win = reused
		return reused
	end

	local anchor = M.has_sidebar() and state.sidebar_win or vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(anchor)
	vim.cmd.vsplit({ mods = { split = "belowright" } })
	state.main_win = vim.api.nvim_get_current_win()

	util.set_wo(state.main_win, state.main_opts or {})

	if anchor == state.sidebar_win then
		apply_sidebar_width()
	end

	return state.main_win
end

---@return integer
function M.open_sidebar()
	state.main_win = reusable_win() or vim.api.nvim_get_current_win()
	state.main_opts = util.save_wo(state.main_win, SIDEBAR_WIN_OPT_NAMES)
	vim.api.nvim_set_current_win(state.main_win)

	vim.cmd.vsplit({ mods = { split = "topleft" } })
	state.sidebar_win = vim.api.nvim_get_current_win()
	apply_sidebar_width()

	state.sidebar_buf = util.scratch_buf("diffmagik://changes")
	vim.api.nvim_win_set_buf(state.sidebar_win, state.sidebar_buf)
	vim.bo[state.sidebar_buf].filetype = "diffmagik"

	util.set_wo(state.sidebar_win, SIDEBAR_WIN_OPTS)

	return state.sidebar_buf
end

---@param repo Git
---@param rel string
---@return integer[]?
function M.open_file(repo, rel)
	local main_win = ensure_main()
	vim.api.nvim_set_current_win(main_win)

	local ok, err = pcall(vim.cmd.edit, { args = { vim.fs.joinpath(repo.root, rel) } })
	if not ok then
		util.error(err)
		return nil
	end

	local bufnr = vim.api.nvim_win_get_buf(main_win)

	if state.diff_style == "inline" then
		return { FileDiff.attach(repo, rel, bufnr) or bufnr }
	end

	FileDiff.detach(bufnr)
	local head_buf = DiffSplit.open_against_head(repo, rel)

	return { bufnr, head_buf }
end

function M.reload_main()
	if not win_valid(state.main_win) then
		return
	end

	local source = FileDiff.source(vim.api.nvim_win_get_buf(state.main_win))
	if source then
		vim.api.nvim_buf_call(source, function()
			pcall(vim.cmd.edit, { bang = true })
		end)
		return
	end

	vim.api.nvim_win_call(state.main_win, function()
		pcall(vim.cmd.edit, { bang = true })
	end)
end

function M.close()
	if M.has_sidebar() then
		vim.api.nvim_win_close(state.sidebar_win, true)
	end
	forget_sidebar()
end

---@param winid integer
---@return boolean
function M.in_split_view(winid)
	return state.diff_style == "split"
		and win_valid(state.sidebar_win)
		and DiffSplit.contains(state.main_win)
		and (winid == state.sidebar_win or DiffSplit.contains(winid))
end

function M.close_split_view()
	local main_buf = DiffSplit.close()

	if win_valid(state.main_win) then
		M.close()
		pcall(vim.api.nvim_win_close, state.main_win, true)
		return
	end

	if M.has_sidebar() and not pcall(vim.api.nvim_win_close, state.sidebar_win, true) then
		local buf = main_buf and vim.api.nvim_buf_is_valid(main_buf) and main_buf or vim.api.nvim_create_buf(true, false)
		vim.api.nvim_win_set_buf(state.sidebar_win, buf)
		util.set_wo(state.sidebar_win, state.main_opts or {})
		state.main_win = state.sidebar_win
	end

	forget_sidebar()
end

return M
