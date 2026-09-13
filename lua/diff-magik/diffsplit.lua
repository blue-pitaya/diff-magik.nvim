local config = require("diff-magik.config")

local group_id = 0

---@class DiffSplit
---@field head_win integer|nil the window id of the currently open HEAD-side split
---@field main_win integer|nil the window holding the working copy
---@field main_buf integer|nil the buffer the HEAD-side split was built for
---@field main_state { fillchars: string, winhighlight: string }|nil
---@field augroup integer
local DiffSplit = {}
DiffSplit.__index = DiffSplit

---@param winid integer|nil
local function win_valid(winid)
	return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

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

	set_diff_fillchar(winid, config.options.fillchar)
	vim.wo[winid].winhighlight = winhighlight
	vim.api.nvim_win_call(winid, function()
		vim.cmd.diffthis()
	end)

	-- A pane with nothing to scroll through would drag its partner back to the top on every entry.
	if vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winid)) <= 1 then
		vim.wo[winid].scrollbind = false
		vim.wo[winid].cursorbind = false
	end
end

---@param winid integer|nil
local function diff_off(winid)
	if not win_valid(winid) or not vim.wo[winid].diff then
		return
	end

	vim.api.nvim_win_call(winid, function()
		vim.cmd.diffoff()
	end)
end

function DiffSplit.new()
	group_id = group_id + 1

	local self = setmetatable({
		augroup = vim.api.nvim_create_augroup(("diff-magik.diffsplit.%d"):format(group_id), { clear = true }),
	}, DiffSplit)

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = self.augroup,
		callback = function()
			self:sync()
		end,
		desc = "DiffMagik: keep diff mode bound to the file the HEAD pane was opened for",
	})

	return self
end

---@param winid integer
function DiffSplit:save_main_state(winid)
	self.main_state = {
		fillchars = vim.api.nvim_get_option_value("fillchars", { scope = "local", win = winid }),
		winhighlight = vim.wo[winid].winhighlight,
	}
end

function DiffSplit:restore_main_state()
	local state = self.main_state

	if not state or not win_valid(self.main_win) then
		return
	end

	vim.api.nvim_set_option_value("fillchars", state.fillchars, { scope = "local", win = self.main_win })
	vim.wo[self.main_win].winhighlight = state.winhighlight
end

---@return boolean
function DiffSplit:showing_main_buf()
	return win_valid(self.main_win)
		and self.main_buf ~= nil
		and vim.api.nvim_win_get_buf(self.main_win) == self.main_buf
end

--- Suspends the diff while the main window is showing some other buffer, and rebuilds it on return.
function DiffSplit:sync()
	if not win_valid(self.main_win) or not self.main_buf then
		return
	end

	if self:showing_main_buf() then
		diff_on(self.main_win, config.options.highlights.main_win)
		if win_valid(self.head_win) then
			diff_on(self.head_win, config.options.highlights.head_win)
		end
	else
		diff_off(self.main_win)
		self:restore_main_state()
		diff_off(self.head_win)
	end
end

---@param repo Git
---@param rel string path to the file, relative to `repo.root`
function DiffSplit:open_against_head(repo, rel)
	local main_win = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()

	---@type string[]
	local head_content = {}

	if repo:exists_in_head(rel) then
		local changed = repo:diff_name_only(rel)
		if not changed then
			vim.notify("DiffMagik: failed to run git diff", vim.log.levels.ERROR)
			return
		end
		if #changed == 0 then
			vim.notify(("DiffMagik: no changes in '%s'"):format(rel), vim.log.levels.ERROR)
			return
		end

		local lines = repo:head_lines(rel)
		if not lines then
			vim.notify("DiffMagik: failed to read HEAD version of file", vim.log.levels.ERROR)
			return
		end

		head_content = lines
	end

	if win_valid(self.head_win) then
		vim.api.nvim_win_close(self.head_win, true)
	end

	self:restore_main_state()
	vim.cmd.diffoff({ bang = true })

	self.main_win = main_win
	self.main_buf = bufnr
	self:save_main_state(main_win)

	vim.cmd.vsplit()
	self.head_win = vim.api.nvim_get_current_win()
	local head_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(head_buf, 0, -1, false, head_content)
	vim.api.nvim_buf_set_name(head_buf, ("diffmagik://%s@HEAD"):format(rel))
	vim.bo[head_buf].buftype = "nofile"
	vim.bo[head_buf].bufhidden = "wipe"
	vim.bo[head_buf].swapfile = false
	vim.bo[head_buf].filetype = vim.bo[bufnr].filetype
	vim.bo[head_buf].modifiable = false
	vim.b[head_buf].diffmagik_root = repo.root
	vim.b[head_buf].diffmagik_path = rel

	vim.api.nvim_win_set_buf(self.head_win, head_buf)

	vim.api.nvim_set_current_win(main_win)
	self:sync()
end

return DiffSplit
