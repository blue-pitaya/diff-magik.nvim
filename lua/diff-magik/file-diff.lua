local ns = vim.api.nvim_create_namespace("diff-magik.file-diff")

---@class FileDiff
---@field view integer scratch buffer the diff is drawn in
---@field source integer buffer of the file being diffed
---@field base string base version as text, for vim.text.diff
---@field base_lines string[] base version as lines
---@field config Config
---@field folds integer[][] view line ranges folded away: everything outside the hunks and their context
local FileDiff = {}
FileDiff.__index = FileDiff

---@param lines string[]
---@return string
local function as_text(lines)
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

---@param hunks integer[][] view line ranges of the hunks
---@param total integer view line count
---@param context integer untouched lines kept around each hunk
---@return integer[][] folds line ranges outside every hunk and its context; empty when nothing changed
local function fold_ranges(hunks, total, context)
	if #hunks == 0 then
		return {}
	end

	local kept = {}
	for _, hunk in ipairs(hunks) do
		for lnum = math.max(hunk[1] - context, 1), math.min(hunk[2] + context, total) do
			kept[lnum] = true
		end
	end

	local folds = {}
	local start
	for lnum = 1, total do
		if not kept[lnum] then
			start = start or lnum
		elseif start then
			table.insert(folds, { start, lnum - 1 })
			start = nil
		end
	end
	if start then
		table.insert(folds, { start, total })
	end
	return folds
end

---@param view integer
---@param source integer
---@param base_lines string[]
---@param config Config
---@return FileDiff
function FileDiff.new(view, source, base_lines, config)
	return setmetatable({
		view = view,
		source = source,
		base = as_text(base_lines),
		base_lines = base_lines,
		config = config,
		folds = {},
	}, FileDiff)
end

---@return boolean rendered false when the view or the source buffer is gone
function FileDiff:render()
	if not vim.api.nvim_buf_is_valid(self.view) or not vim.api.nvim_buf_is_valid(self.source) then
		return false
	end

	if not vim.api.nvim_buf_is_loaded(self.source) then
		vim.fn.bufload(self.source)
	end

	local current = vim.api.nvim_buf_get_lines(self.source, 0, -1, false)
	local hunks = vim.text.diff(self.base, as_text(current), { result_type = "indices" }) --[[@as integer[][] ]]

	local hl = self.config.highlights
	local lines = {}
	local groups = {}
	local ranges = {}
	local next_b = 1

	for _, hunk in ipairs(hunks) do
		local start_a, count_a, start_b, count_b = hunk[1], hunk[2], hunk[3], hunk[4]
		local first_b = count_b > 0 and start_b or start_b + 1

		for lnum = next_b, first_b - 1 do
			table.insert(lines, current[lnum])
		end

		local first = #lines + 1
		for i = 0, count_a - 1 do
			table.insert(lines, self.base_lines[start_a + i] or "")
			groups[#lines] = hl.file_deleted
		end
		for i = 0, count_b - 1 do
			table.insert(lines, current[start_b + i])
			groups[#lines] = hl.file_added
		end
		table.insert(ranges, { first, #lines })

		next_b = first_b + count_b
	end

	for lnum = next_b, #current do
		table.insert(lines, current[lnum])
	end

	self.folds = fold_ranges(ranges, #lines, self.config.fold_context)

	vim.bo[self.view].modifiable = true
	vim.api.nvim_buf_set_lines(self.view, 0, -1, false, lines)
	vim.bo[self.view].modifiable = false

	vim.api.nvim_buf_clear_namespace(self.view, ns, 0, -1)
	for lnum, group in pairs(groups) do
		vim.api.nvim_buf_set_extmark(self.view, ns, lnum - 1, 0, {
			line_hl_group = group,
		})
	end

	return true
end

---@param winid integer
function FileDiff:apply_folds(winid)
	vim.api.nvim_win_call(winid, function()
		vim.cmd("normal! zE")
		for _, fold in ipairs(self.folds) do
			vim.cmd(("%d,%dfold"):format(fold[1], fold[2]))
		end
	end)
end

function FileDiff:clear_highlights()
	if vim.api.nvim_buf_is_valid(self.view) then
		vim.api.nvim_buf_clear_namespace(self.view, ns, 0, -1)
	end
end

return FileDiff
