local ns = vim.api.nvim_create_namespace("diff-magik")

---@param status string
---@param hl DiffMagikHighlights
local function status_hl(status, hl)
	if status == "A" then
		return hl.added
	elseif status == "D" then
		return hl.removed
	end
	return hl.changed
end

local STAGE_MARKER = {
	staged = " (S)",
	partial = " (S*)",
}

local STAGE_MARKER_WIDTH = 0
for _, marker in pairs(STAGE_MARKER) do
	STAGE_MARKER_WIDTH = math.max(STAGE_MARKER_WIDTH, vim.fn.strdisplaywidth(marker))
end

---@param entry GitEntry
local function stage_suffix(entry)
	if not entry.staged then
		return ""
	end
	return entry.unstaged and STAGE_MARKER.partial or STAGE_MARKER.staged
end

---@param entry GitEntry
---@param hl DiffMagikHighlights
local function stage_hl(entry, hl)
	return entry.unstaged and hl.staged_dirty or hl.staged
end

---@param flat TreeFlatItem[]
---@return string[]
---@return integer
local function build_lines(flat)
	local lines = {}
	local widest = 0
	for _, item in ipairs(flat) do
		local indent = ("  "):rep(item.depth)
		if item.node.is_dir then
			local marker = item.node.expanded and "▾" or "▸"
			local line = ("%s%s %s/"):format(indent, marker, item.node.name)
			table.insert(lines, line)
			widest = math.max(widest, vim.fn.strdisplaywidth(line))
		else
			local suffix = stage_suffix(item.node.entry)
			local line = ("%s%s %s%s"):format(indent, item.node.entry.status, item.node.name, suffix)
			table.insert(lines, line)
			local width = vim.fn.strdisplaywidth(line) - vim.fn.strdisplaywidth(suffix) + STAGE_MARKER_WIDTH
			widest = math.max(widest, width)
		end
	end
	return lines, widest
end

---@param buf integer
---@param flat TreeFlatItem[]
---@param lines string[]
---@param hl DiffMagikHighlights
local function apply_highlights(buf, flat, lines, hl)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, item in ipairs(flat) do
		if item.node.is_dir then
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
				line_hl_group = hl.directory,
			})
		else
			local col = #("  "):rep(item.depth)
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, {
				end_col = col + 1,
				hl_group = status_hl(item.node.entry.status, hl),
			})

			local suffix = stage_suffix(item.node.entry)
			if suffix ~= "" then
				local end_col = #lines[i]
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, end_col - #suffix + 1, {
					end_col = end_col,
					hl_group = stage_hl(item.node.entry, hl),
				})
			end
		end
	end
end

---@param buf integer
---@param flat TreeFlatItem[]
---@param hl DiffMagikHighlights
---@return integer
local function render(buf, flat, hl)
	local lines, widest = build_lines(flat)

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	apply_highlights(buf, flat, lines, hl)

	return widest
end

return render
