local Git = require("diff-magik.git")
local TreeNode = require("diff-magik.tree")
local Layout = require("diff-magik.layout")
local config = require("diff-magik.config")

local ns = vim.api.nvim_create_namespace("diff-magik")

---@class Browser
---@field layout Layout
---@field repo Git|nil
---@field tree TreeNode|nil
---@field flat TreeFlatItem[]|nil
---@field current_path string|nil
---@field diff_bufs integer[]
local Browser = {}
Browser.__index = Browser

function Browser.new()
	return setmetatable({ layout = Layout.new(), diff_bufs = {} }, Browser)
end

local SIDEBAR_ACTIONS = { "open", "stage", "reset", "close" }
local DIFF_ACTIONS = { "next_file", "prev_file" }

local DESCRIPTIONS = {
	open = "DiffMagik: open entry",
	close = "DiffMagik: close browser",
	stage = "DiffMagik: stage or unstage entry",
	reset = "DiffMagik: discard the changes to entry",
	next_file = "DiffMagik: next changed file",
	prev_file = "DiffMagik: previous changed file",
}

---@param bufnr integer
---@param names string[]
function Browser:set_keymaps(bufnr, names)
	local handlers = {
		open = function()
			self:open_selected()
		end,
		close = function()
			self:close()
		end,
		stage = function()
			self:toggle_stage_selected()
		end,
		reset = function()
			self:reset_selected()
		end,
		next_file = function()
			self:select_offset(1)
		end,
		prev_file = function()
			self:select_offset(-1)
		end,
	}

	for _, name in ipairs(names) do
		for _, key in ipairs(config.options.keys[name]) do
			vim.keymap.set("n", key, handlers[name], {
				buffer = bufnr,
				nowait = true,
				silent = true,
				desc = DESCRIPTIONS[name],
			})
		end
	end
end

---@param bufnr integer
---@param names string[]
local function del_keymaps(bufnr, names)
	for _, name in ipairs(names) do
		for _, key in ipairs(config.options.keys[name]) do
			pcall(vim.keymap.del, "n", key, { buffer = bufnr })
		end
	end
end

---@param status string
local function status_hl(status)
	local hl = config.options.highlights
	if status == "A" then
		return hl.added
	elseif status == "D" then
		return hl.removed
	end
	return hl.changed
end

---@param entry GitEntry
local function stage_suffix(entry)
	if not entry.staged then
		return ""
	end
	return entry.unstaged and " (S*)" or " (S)"
end

---@param entry GitEntry
local function stage_hl(entry)
	local hl = config.options.highlights
	return entry.unstaged and hl.staged_dirty or hl.staged
end

function Browser:render_tree()
	local buf = self.layout.sidebar_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local flat = {}
	self.tree:flatten(0, flat)
	self.flat = flat

	local lines = {}
	for _, item in ipairs(flat) do
		local indent = ("  "):rep(item.depth)
		if item.node.is_dir then
			local marker = item.node.expanded and "▾" or "▸"
			table.insert(lines, ("%s%s %s/"):format(indent, marker, item.node.name))
		else
			table.insert(
				lines,
				("%s%s %s%s"):format(indent, item.node.entry.status, item.node.name, stage_suffix(item.node.entry))
			)
		end
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, item in ipairs(flat) do
		if item.node.is_dir then
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
				line_hl_group = config.options.highlights.directory,
			})
		else
			local col = #("  "):rep(item.depth)
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, {
				end_col = col + 1,
				hl_group = status_hl(item.node.entry.status),
			})

			local suffix = stage_suffix(item.node.entry)
			if suffix ~= "" then
				local end_col = #lines[i]
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, end_col - #suffix + 1, {
					end_col = end_col,
					hl_group = stage_hl(item.node.entry),
				})
			end
		end
	end
end

function Browser:refresh()
	if not self.repo or not self.layout:has_sidebar() then
		return
	end

	local entries = self.repo:get_changed_files()
	if not entries then
		return
	end

	local line = self.layout:sidebar_cursor()
	local cursor_path = line and self.flat and self.flat[line] and self.flat[line].path

	local collapsed = {}
	if self.tree then
		self.tree:collect_collapsed(collapsed)
	end

	self.tree = TreeNode.new(entries)
	self.tree:sort()
	self.tree:apply_collapsed(collapsed)

	self:render_tree()

	local target = 1
	for i, item in ipairs(self.flat) do
		if item.path == cursor_path then
			target = i
			break
		end
	end
	self.layout:set_sidebar_cursor(math.min(target, math.max(#self.flat, 1)))
end

function Browser:clear_diff_keymaps()
	for _, buf in ipairs(self.diff_bufs) do
		if vim.api.nvim_buf_is_valid(buf) then
			del_keymaps(buf, DIFF_ACTIONS)
		end
	end
	self.diff_bufs = {}
end

---@param bufs integer[]
function Browser:set_diff_keymaps(bufs)
	self:clear_diff_keymaps()

	for _, buf in ipairs(bufs) do
		self:set_keymaps(buf, DIFF_ACTIONS)
	end

	self.diff_bufs = bufs
end

---@return integer|nil
function Browser:current_index()
	if not self.flat or not self.current_path then
		return nil
	end

	for i, item in ipairs(self.flat) do
		if not item.node.is_dir and item.node.entry.path == self.current_path then
			return i
		end
	end
end

---@param offset integer
function Browser:select_offset(offset)
	local index = self:current_index()
	if not index then
		return
	end

	local i = index + offset
	while self.flat[i] do
		if not self.flat[i].node.is_dir then
			self.layout:set_sidebar_cursor(i)
			self:open_entry(self.flat[i].node.entry)
			return
		end
		i = i + offset
	end
end

---@param entry GitEntry
function Browser:open_entry(entry)
	local bufs = self.layout:open_file(self.repo, entry.path)
	if not bufs then
		return
	end

	self.current_path = entry.path
	self:set_diff_keymaps(bufs)
end

function Browser:open_selected()
	local line = self.layout:sidebar_cursor()
	local item = line and self.flat[line]
	if not item then
		return
	end

	if item.node.is_dir then
		item.node.expanded = not item.node.expanded
		self:render_tree()
		self.layout:set_sidebar_cursor(line)
	else
		self:open_entry(item.node.entry)
	end
end

---@return GitEntry|nil
function Browser:selected_entry()
	local line = self.layout:sidebar_cursor()
	local item = line and self.flat and self.flat[line]
	if not item or item.node.is_dir then
		return nil
	end
	return item.node.entry
end

function Browser:toggle_stage_selected()
	local entry = self:selected_entry()
	if not self.repo or not entry then
		return
	end

	if not self.repo:toggle_stage(entry.path) then
		vim.notify(("DiffMagik: failed to update the index for '%s'"):format(entry.path), vim.log.levels.ERROR)
		return
	end

	self:refresh()
end

function Browser:reset_selected()
	local entry = self:selected_entry()
	if not self.repo or not entry then
		return
	end

	local prompt = ("DiffMagik: discard all changes to '%s'?"):format(entry.path)
	if vim.fn.confirm(prompt, "&yes\n&no", 2, "Question") ~= 1 then
		return
	end

	if not self.repo:reset(entry.path) then
		vim.notify(("DiffMagik: failed to reset '%s'"):format(entry.path), vim.log.levels.ERROR)
		return
	end

	if self.current_path == entry.path then
		self.layout:reload_main()
	end

	self:refresh()
end

function Browser:close()
	self:clear_diff_keymaps()
	self.layout:close()
end

function Browser:open()
	if self.layout:focus_sidebar() then
		return
	end

	local bufname = vim.api.nvim_buf_get_name(0)
	local dir = bufname ~= "" and vim.fs.dirname(bufname) or vim.fn.getcwd()

	local repo = Git.new(dir)
	if not repo then
		vim.notify("DiffMagik: not inside a git repository", vim.log.levels.ERROR)
		return
	end

	local entries = repo:get_changed_files()
	if not entries then
		vim.notify("DiffMagik: failed to run git diff", vim.log.levels.ERROR)
		return
	end
	if #entries == 0 then
		vim.notify("DiffMagik: no changes in repository", vim.log.levels.ERROR)
		return
	end

	local tree = TreeNode.new(entries)
	tree:sort()

	self.repo = repo
	self.tree = tree

	local bufnr = self.layout:open_sidebar()
	self:render_tree()

	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = bufnr,
		callback = function()
			self:refresh()
		end,
		desc = "DiffMagik: refresh the changed-file list",
	})

	self:set_keymaps(bufnr, SIDEBAR_ACTIONS)
end

return Browser
