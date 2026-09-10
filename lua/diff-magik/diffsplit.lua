local config = require("diff-magik.config")

---@class DiffSplit
---@field head_win integer|nil the window id of the currently open HEAD-side split
---@field main_state { win: integer, fillchars: string, winhighlight: string }|nil
local DiffSplit = {}
DiffSplit.__index = DiffSplit

function DiffSplit.new()
	return setmetatable({}, DiffSplit)
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
function DiffSplit:save_main_state(winid)
	self.main_state = {
		win = winid,
		fillchars = vim.api.nvim_get_option_value("fillchars", { scope = "local", win = winid }),
		winhighlight = vim.wo[winid].winhighlight,
	}
end

function DiffSplit:restore_main_state()
	local state = self.main_state
	self.main_state = nil

	if not state or not vim.api.nvim_win_is_valid(state.win) then
		return
	end

	vim.api.nvim_set_option_value("fillchars", state.fillchars, { scope = "local", win = state.win })
	vim.wo[state.win].winhighlight = state.winhighlight
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

	if self.head_win and vim.api.nvim_win_is_valid(self.head_win) then
		vim.api.nvim_win_close(self.head_win, true)
	end

	self:restore_main_state()
	vim.cmd.diffoff({ bang = true })
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
	set_diff_fillchar(self.head_win, config.options.fillchar)
	vim.wo[self.head_win].winhighlight = config.options.highlights.head_win
	vim.cmd.diffthis()

	vim.api.nvim_set_current_win(main_win)
	set_diff_fillchar(main_win, config.options.fillchar)
	vim.wo[main_win].winhighlight = config.options.highlights.main_win
	vim.cmd.diffthis()
end

return DiffSplit
