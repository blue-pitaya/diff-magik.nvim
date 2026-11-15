local util = require("diff-magik.util")
local BufferOrigin = require("diff-magik.buffer-origin")
local DiffSplitPanes = require("diff-magik.diff-split-panes")

---@class DiffSplit
---@field config Config
---@field panes? DiffSplitPanes the open split; nil while none is open
---@field opening boolean true while open_against_head builds the panes
local DiffSplit = {}
DiffSplit.__index = DiffSplit

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
---@param fillchar string
local function diff_on(winid, winhighlight, fillchar)
	if vim.wo[winid].diff and vim.wo[winid].foldmethod == "diff" then
		return
	end

	local wrap = vim.wo[winid].wrap

	util.set_wo(winid, {
		fillchars = diff_fillchars(winid, fillchar),
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
	if winid == nil or not vim.api.nvim_win_is_valid(winid) or not vim.wo[winid].diff then
		return
	end

	vim.api.nvim_win_call(winid, function()
		vim.cmd.diffoff()
	end)
end

---@param config Config
---@return DiffSplit
function DiffSplit.new(config)
	local self = setmetatable({ config = config, opening = false }, DiffSplit)

	local augroup = vim.api.nvim_create_augroup("diff-magik.diff-split", { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = augroup,
		callback = function()
			self:sync()
		end,
		desc = "DiffMagik: keep diff mode bound to the file the HEAD pane was opened for",
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function()
			vim.schedule(function()
				self:sync()
			end)
		end,
		desc = "DiffMagik: restore the diff folds an attaching LSP would take over",
	})

	return self
end

---@return integer? main_buf buffer the HEAD pane was opened for
function DiffSplit:close()
	local panes = self.panes
	if not panes then
		return nil
	end
	self.panes = nil

	diff_off(panes.main_win)
	panes:restore_main_opts()

	if panes:head_valid() then
		pcall(vim.api.nvim_win_close, panes.head_win, true)
	end

	return panes.main_buf
end

function DiffSplit:sync()
	local panes = self.panes
	if self.opening or not panes or not panes:main_valid() then
		return
	end

	if not panes:head_valid() then
		self:close()
		return
	end

	if panes:showing_main_buf() then
		diff_on(panes.main_win, self.config.highlights.main_win, self.config.fillchar)
		diff_on(panes.head_win, self.config.highlights.head_win, self.config.fillchar)
	else
		diff_off(panes.main_win)
		panes:restore_main_opts()
		diff_off(panes.head_win)
	end
end

---@param winid integer?
---@return boolean
function DiffSplit:contains(winid)
	return not self.opening and self.panes ~= nil and self.panes:contains(winid)
end

---@param repo Git
---@param rel string
---@param lines string[]
---@param label string
---@return integer
function DiffSplit:split_head(repo, rel, lines, label)
	local main_win = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()

	local previous = self.panes
	if previous then
		if previous:head_valid() then
			vim.api.nvim_win_close(previous.head_win, true)
		end
		previous:restore_main_opts()
		self.panes = nil
	end
	vim.cmd.diffoff({ bang = true })

	local origin = BufferOrigin.new(repo.root, rel)
	origin:tag(bufnr)

	vim.cmd.vsplit()
	local head_win = vim.api.nvim_get_current_win()
	self.panes = DiffSplitPanes.new(main_win, bufnr, head_win)

	local head_buf = util.scratch_buf(("diffmagik://%s@%s"):format(rel, label))
	vim.api.nvim_buf_set_lines(head_buf, 0, -1, false, lines)
	vim.bo[head_buf].filetype = vim.bo[bufnr].filetype
	vim.bo[head_buf].modifiable = false
	origin:tag(head_buf)

	vim.api.nvim_win_set_buf(head_win, head_buf)
	vim.api.nvim_set_current_win(main_win)

	return head_buf
end

---@param repo Git
---@param rel string
---@return integer? head_buf
function DiffSplit:open_against_head(repo, rel)
	local base, err = repo:base_lines(rel)
	if err ~= nil then
		util.error(err)
		return nil
	end

	self.opening = true
	local ok, head_buf = pcall(self.split_head, self, repo, rel, base.lines, base.label)
	self.opening = false

	if not ok then
		util.error(head_buf)
		return nil
	end

	self:sync()
	return head_buf
end

return DiffSplit
