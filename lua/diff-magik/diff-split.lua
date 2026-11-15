local config = require("diff-magik.config")
local util = require("diff-magik.util")
local BufferOrigin = require("diff-magik.buffer-origin")

local win_valid = util.win_valid

local MAIN_OPTS = { "fillchars", "winhighlight", "foldcolumn" }

---@class DiffSplitState
---@field head_win? integer
---@field main_win? integer
---@field main_buf? integer
---@field main_opts? table<string, any>
---@field opening? boolean
local state = {}

local M = {}

---@param winid integer
---@param char string
---@return string
local function diff_fillchars(winid, char)
	local parts = vim.tbl_filter(function(part)
		return not vim.startswith(part, "diff:")
	end, vim.split(vim.wo[winid].fillchars, ",", { trimempty = true }))

	table.insert(parts, "diff:" .. char)
	return table.concat(parts, ",")
end

---@param winid integer
---@param winhighlight string
local function diff_on(winid, winhighlight)
	if vim.wo[winid].diff and vim.wo[winid].foldmethod == "diff" then
		return
	end

	local wrap = vim.wo[winid].wrap

	util.set_wo(winid, {
		fillchars = diff_fillchars(winid, config.options.fillchar),
		winhighlight = winhighlight,
	})
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

local function restore_main_opts()
	if state.main_opts and win_valid(state.main_win) then
		util.set_wo(state.main_win, state.main_opts)
	end
end

---@return boolean
local function showing_main_buf()
	return win_valid(state.main_win)
		and state.main_buf ~= nil
		and vim.api.nvim_win_get_buf(state.main_win) == state.main_buf
end

---@return integer?
function M.close()
	local main_buf = state.main_buf

	diff_off(state.main_win)
	restore_main_opts()

	if win_valid(state.head_win) then
		pcall(vim.api.nvim_win_close, state.head_win, true)
	end

	state.head_win = nil
	state.main_win = nil
	state.main_buf = nil
	state.main_opts = nil

	return main_buf
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
		diff_on(state.head_win, config.options.highlights.head_win)
	else
		diff_off(state.main_win)
		restore_main_opts()
		diff_off(state.head_win)
	end
end

function M.setup()
	local augroup = vim.api.nvim_create_augroup("diff-magik.diff-split", { clear = true })

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

---@param winid integer
---@return boolean
function M.contains(winid)
	return not state.opening
		and win_valid(state.head_win)
		and win_valid(state.main_win)
		and (winid == state.head_win or winid == state.main_win)
end

---@param repo Git
---@param rel string
---@param lines string[]
---@param label string
---@return integer
local function split_head(repo, rel, lines, label)
	local main_win = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()

	if win_valid(state.head_win) then
		vim.api.nvim_win_close(state.head_win, true)
	end

	restore_main_opts()
	vim.cmd.diffoff({ bang = true })

	state.main_win = main_win
	state.main_buf = bufnr
	state.main_opts = util.save_wo(main_win, MAIN_OPTS)

	local origin = BufferOrigin.new(repo.root, rel)
	origin:tag(bufnr)

	vim.cmd.vsplit()
	state.head_win = vim.api.nvim_get_current_win()
	local head_buf = util.scratch_buf(("diffmagik://%s@%s"):format(rel, label))
	vim.api.nvim_buf_set_lines(head_buf, 0, -1, false, lines)
	vim.bo[head_buf].filetype = vim.bo[bufnr].filetype
	vim.bo[head_buf].modifiable = false
	origin:tag(head_buf)

	vim.api.nvim_win_set_buf(state.head_win, head_buf)
	vim.api.nvim_set_current_win(main_win)

	return head_buf
end

---@param repo Git
---@param rel string
---@return integer?
function M.open_against_head(repo, rel)
	local lines, label, err = repo:base_lines(rel)
	if not lines then
		util.error(err)
		return nil
	end

	state.opening = true
	local ok, head_buf = pcall(split_head, repo, rel, lines, label)
	state.opening = false

	if not ok then
		util.error(head_buf)
		return nil
	end

	sync()
	return head_buf
end

return M
