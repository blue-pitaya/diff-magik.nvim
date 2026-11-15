local TreeNode = require("diff-magik.tree")

local ns = vim.api.nvim_create_namespace("diff-magik.change-list")

local STAGE_MARKER = {
	staged = " (S)",
	partial = " (S*)",
}

---@class ChangeListHighlight
---@field col integer byte the range starts at
---@field end_col? integer byte the range ends before; nil highlights the whole line
---@field group string

---@class ChangeList
---@field tree TreeNode
---@field rows TreeFlatItem[] visible rows, in sidebar line order
---@field highlights DiffMagikHighlights
local ChangeList = {}
ChangeList.__index = ChangeList

---@param entries GitEntry[]
---@return TreeNode
local function build_tree(entries)
	local tree = TreeNode.new(entries)
	tree:sort()
	return tree
end

---@param status string
---@param hl DiffMagikHighlights
---@return string
local function status_group(status, hl)
	if status == "A" then
		return hl.added
	elseif status == "D" then
		return hl.removed
	end
	return hl.changed
end

---@param row TreeFlatItem
---@param hl DiffMagikHighlights
---@return string text
---@return ChangeListHighlight[] highlights
local function format_row(row, hl)
	local indent = ("  "):rep(row.depth)
	local node = row.node

	if node.is_dir then
		local marker = node.expanded and "▾" or "▸"
		return ("%s%s %s/"):format(indent, marker, node.name), { { col = 0, group = hl.directory } }
	end

	local entry = node.entry --[[@as GitEntry]]
	local text = ("%s%s %s"):format(indent, entry.status, node.name)
	local highlights = { { col = #indent, end_col = #indent + 1, group = status_group(entry.status, hl) } }

	if entry.staged then
		local marker = entry.unstaged and STAGE_MARKER.partial or STAGE_MARKER.staged
		local group = entry.unstaged and hl.staged_dirty or hl.staged
		-- the marker's leading space stays unhighlighted
		table.insert(highlights, { col = #text + 1, end_col = #text + #marker, group = group })
		text = text .. marker
	end

	return text, highlights
end

---@param entries GitEntry[]
---@param highlights DiffMagikHighlights
---@return ChangeList
function ChangeList.new(entries, highlights)
	local self = setmetatable({ tree = build_tree(entries), rows = {}, highlights = highlights }, ChangeList)
	self:flatten()
	return self
end

function ChangeList:flatten()
	local rows = {}
	self.tree:flatten(0, rows)
	self.rows = rows
end

---@param entries GitEntry[]
function ChangeList:update(entries)
	local collapsed = {}
	self.tree:collect_collapsed(collapsed)

	self.tree = build_tree(entries)
	self.tree:apply_collapsed(collapsed)
	self:flatten()
end

---@param buf integer
function ChangeList:draw(buf)
	local lines = {}
	local highlights = {}
	for i, row in ipairs(self.rows) do
		lines[i], highlights[i] = format_row(row, self.highlights)
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, row_highlights in ipairs(highlights) do
		for _, highlight in ipairs(row_highlights) do
			if highlight.end_col then
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, highlight.col, {
					end_col = highlight.end_col,
					hl_group = highlight.group,
				})
			else
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, highlight.col, {
					line_hl_group = highlight.group,
				})
			end
		end
	end
end

---@param line integer?
---@return TreeFlatItem?
function ChangeList:row(line)
	return line and self.rows[line]
end

---@param line integer?
---@return GitEntry? entry the file on `line`; nil for a directory row
function ChangeList:entry(line)
	local row = self:row(line)
	return row and not row.node.is_dir and row.node.entry or nil
end

---@param path string
---@return integer?
function ChangeList:line_of(path)
	for i, row in ipairs(self.rows) do
		if row.node.path == path then
			return i
		end
	end
end

---@param line integer
---@return boolean toggled false when `line` is not a directory row
function ChangeList:toggle(line)
	local row = self.rows[line]
	if not row or not row.node.is_dir then
		return false
	end

	row.node.expanded = not row.node.expanded
	self:flatten()
	return true
end

---@param line integer
---@param offset 1|-1 direction to search in
---@return integer? line of the nearest file row past `line`
function ChangeList:next_file(line, offset)
	local i = line + offset
	while self.rows[i] do
		if not self.rows[i].node.is_dir then
			return i
		end
		i = i + offset
	end
end

return ChangeList
