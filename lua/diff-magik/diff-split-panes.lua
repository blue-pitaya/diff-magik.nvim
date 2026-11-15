local util = require("diff-magik.util")

---@class DiffSplitPanes
---@field main_win integer pane showing the working copy
---@field main_buf integer buffer the HEAD pane was opened for
---@field head_win integer pane showing the base version
---@field fillchars string main window 'fillchars' before diff mode
---@field winhighlight string main window 'winhighlight' before diff mode
---@field foldcolumn string main window 'foldcolumn' before diff mode
local DiffSplitPanes = {}
DiffSplitPanes.__index = DiffSplitPanes

---@param main_win integer
---@param main_buf integer
---@param head_win integer
---@return DiffSplitPanes
function DiffSplitPanes.new(main_win, main_buf, head_win)
	---@param name string
	local function local_value(name)
		return vim.api.nvim_get_option_value(name, { scope = "local", win = main_win })
	end

	return setmetatable({
		main_win = main_win,
		main_buf = main_buf,
		head_win = head_win,
		fillchars = local_value("fillchars"),
		winhighlight = local_value("winhighlight"),
		foldcolumn = local_value("foldcolumn"),
	}, DiffSplitPanes)
end

---@return boolean
function DiffSplitPanes:main_valid()
	return vim.api.nvim_win_is_valid(self.main_win)
end

---@return boolean
function DiffSplitPanes:head_valid()
	return vim.api.nvim_win_is_valid(self.head_win)
end

---@return boolean
function DiffSplitPanes:showing_main_buf()
	return self:main_valid() and vim.api.nvim_win_get_buf(self.main_win) == self.main_buf
end

---@param winid integer?
---@return boolean
function DiffSplitPanes:contains(winid)
	return self:head_valid() and self:main_valid() and (winid == self.head_win or winid == self.main_win)
end

function DiffSplitPanes:restore_main_opts()
	if self:main_valid() then
		util.set_wo(self.main_win, {
			fillchars = self.fillchars,
			winhighlight = self.winhighlight,
			foldcolumn = self.foldcolumn,
		})
	end
end

return DiffSplitPanes
