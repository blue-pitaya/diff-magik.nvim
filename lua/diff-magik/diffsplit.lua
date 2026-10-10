local config = require("diff-magik.config")
local util = require("diff-magik.util")

local win_valid = util.win_valid

---@class DiffSplitState
---@field head_win? integer
---@field main_win? integer
---@field main_buf? integer
---@field main_state? { fillchars: string, winhighlight: string, foldcolumn: string }
---@field opening? boolean
local state = {}

local M = {}

---@param winid integer
---@param char string
local function set_diff_fillchar(winid, char)
	local parts = vim.tbl_filter(function(part)
		return not vim.startswith(part, "diff:")
	end, vim.split(vim.wo[winid].fillchars, ",", { trimempty = true }))

	table.insert(parts, "diff:" .. char)
	vim.wo[winid].fillchars = table.concat(parts, ",")
end

---@param winid integer
---@param winhighlight string
local function diff_on(winid, winhighlight)
	if vim.wo[winid].diff and vim.wo[winid].foldmethod == "diff" then
		return
	end

	local wrap = vim.wo[winid].wrap

	set_diff_fillchar(winid, config.options.fillchar)
	vim.wo[winid].winhighlight = winhighlight
	vim.api.nvim_win_call(winid, function()
		vim.cmd.diffthis()
	end)
	vim.wo[winid].wrap = wrap

	if vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winid)) <= 1 then
		vim.wo[winid].scrollbind = false
		vim.wo[winid].cursorbind = false
	end
end

---@param winid integer?
local function diff_off(winid)
	if not win_valid(winid) or not vim.wo[winid].diff then
		return
	end

	vim.api.nvim_win_call(winid, function()
		vim.cmd.diffoff()
	end)
end

---@param winid integer
local function save_main_state(winid)
	state.main_state = {
		fillchars = vim.api.nvim_get_option_value("fillchars", { scope = "local", win = winid }),
		winhighlight = vim.wo[winid].winhighlight,
		foldcolumn = vim.wo[winid].foldcolumn,
	}
end

local function restore_main_state()
	local saved = state.main_state

	if not saved or not win_valid(state.main_win) then
		return
	end

	vim.api.nvim_set_option_value("fillchars", saved.fillchars, { scope = "local", win = state.main_win })
	vim.wo[state.main_win].winhighlight = saved.winhighlight
	vim.wo[state.main_win].foldcolumn = saved.foldcolumn
end

---@return boolean
local function showing_main_buf()
	return win_valid(state.main_win)
		and state.main_buf ~= nil
		and vim.api.nvim_win_get_buf(state.main_win) == state.main_buf
end

function M.close()
	diff_off(state.main_win)
	restore_main_state()

	if win_valid(state.head_win) then
		pcall(vim.api.nvim_win_close, state.head_win, true)
	end

	state.head_win = nil
	state.main_win = nil
	state.main_buf = nil
	state.main_state = nil
end

local function sync()
	if state.opening then
		return
	end

	if not win_valid(state.main_win) or not state.main_buf then
		return
	end

	if not win_valid(state.head_win) then
		M.close()
		return
	end

	if showing_main_buf() then
		diff_on(state.main_win, config.options.highlights.main_win)
		if win_valid(state.head_win) then
			diff_on(state.head_win, config.options.highlights.head_win)
		end
	else
		diff_off(state.main_win)
		restore_main_state()
		diff_off(state.head_win)
	end
end

function M.setup()
	local augroup = vim.api.nvim_create_augroup("diff-magik.diffsplit", { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = augroup,
		callback = function()
			sync()
		end,
		desc = "DiffMagik: keep diff mode bound to the file the HEAD pane was opened for",
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function()
			vim.schedule(sync)
		end,
		desc = "DiffMagik: restore the diff folds an attaching LSP would take over",
	})
end

---@return integer?
function M.head_win()
	return state.head_win
end

---@return integer?
function M.main_buf()
	return state.main_buf
end

---@return boolean
function M.is_opening()
	return state.opening == true
end

---@param repo Git
---@param rel string
function M.open_against_head(repo, rel)
	local main_win = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()

	local base_content, base_label, err = repo:base_lines(rel)
	if not base_content then
		vim.notify("DiffMagik: " .. err, vim.log.levels.ERROR)
		return
	end

	state.opening = true

	if win_valid(state.head_win) then
		vim.api.nvim_win_close(state.head_win, true)
	end

	restore_main_state()
	vim.cmd.diffoff({ bang = true })

	state.main_win = main_win
	state.main_buf = bufnr
	save_main_state(main_win)

	util.tag_buffer(bufnr, repo.root, rel)

	vim.cmd.vsplit()
	state.head_win = vim.api.nvim_get_current_win()
	local head_buf = util.scratch_buf(("diffmagik://%s@%s"):format(rel, base_label))
	vim.api.nvim_buf_set_lines(head_buf, 0, -1, false, base_content)
	vim.bo[head_buf].filetype = vim.bo[bufnr].filetype
	vim.bo[head_buf].modifiable = false
	util.tag_buffer(head_buf, repo.root, rel)

	vim.api.nvim_win_set_buf(state.head_win, head_buf)

	vim.api.nvim_set_current_win(main_win)
	state.opening = false
	sync()
end

return M
