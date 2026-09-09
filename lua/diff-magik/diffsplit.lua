---@class DiffSplit
---@field head_win integer|nil the window id of the currently open HEAD-side split
local DiffSplit = {}
DiffSplit.__index = DiffSplit

function DiffSplit.new()
	return setmetatable({}, DiffSplit)
end

---@param repo Git
---@param rel string path to the file, relative to `repo.root`
function DiffSplit:open_against_head(repo, rel)
	local bufnr = vim.api.nvim_get_current_buf()

	if not repo:is_tracked(rel) then
		vim.notify(("DiffMagik: '%s' is not tracked in git"):format(rel), vim.log.levels.ERROR)
		return
	end

	local changed = repo:diff_name_only(rel)
	if not changed then
		vim.notify("DiffMagik: failed to run git diff", vim.log.levels.ERROR)
		return
	end
	if #changed == 0 then
		vim.notify(("DiffMagik: no changes in '%s'"):format(rel), vim.log.levels.ERROR)
		return
	end

	local head_content = repo:head_lines(rel)
	if not head_content then
		vim.notify("DiffMagik: failed to read HEAD version of file", vim.log.levels.ERROR)
		return
	end

	if self.head_win and vim.api.nvim_win_is_valid(self.head_win) then
		vim.api.nvim_win_close(self.head_win, true)
	end

	vim.cmd.vsplit()
	self.head_win = vim.api.nvim_get_current_win()
	local head_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(head_buf, 0, -1, false, head_content)
	vim.api.nvim_buf_set_name(head_buf, ("diffmagik://%s@HEAD"):format(rel))
	vim.bo[head_buf].buftype = "nofile"
	vim.bo[head_buf].bufhidden = "wipe"
	vim.bo[head_buf].swapfile = false
	vim.bo[head_buf].filetype = vim.bo[bufnr].filetype

	vim.api.nvim_win_set_buf(self.head_win, head_buf)
	vim.cmd.diffthis()

	vim.cmd.wincmd("p")
	vim.cmd.diffthis()
end

return DiffSplit
