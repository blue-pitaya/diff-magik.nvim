local Git = require("diff-magik.git")
local TreeNode = require("diff-magik.tree")
local DiffSplit = require("diff-magik.diffsplit")
local config = require("diff-magik.config")

local ns = vim.api.nvim_create_namespace("diff-magik")

---@class Browser
---@field sidebar_win integer|nil
---@field sidebar_buf integer|nil
---@field main_win integer|nil
---@field diffsplit DiffSplit
---@field repo Git|nil
---@field tree TreeNode|nil
---@field flat TreeFlatItem[]|nil
---@field current_path string|nil
---@field diff_bufs integer[]
local Browser = {}
Browser.__index = Browser

function Browser.new()
	return setmetatable({ diffsplit = DiffSplit.new(), diff_bufs = {} }, Browser)
end

---@param bufnr integer
---@param keys string[]
---@param fn fun()
---@param desc string
local function map(bufnr, keys, fn, desc)
	for _, key in ipairs(keys) do
		vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
	end
end

---@param bufnr integer
---@param keys string[]
local function unmap(bufnr, keys)
	for _, key in ipairs(keys) do
		pcall(vim.keymap.del, "n", key, { buffer = bufnr })
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

	vim.bo[self.sidebar_buf].modifiable = true
	vim.api.nvim_buf_set_lines(self.sidebar_buf, 0, -1, false, lines)
	vim.bo[self.sidebar_buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(self.sidebar_buf, ns, 0, -1)
	for i, item in ipairs(flat) do
		if item.node.is_dir then
			vim.api.nvim_buf_set_extmark(self.sidebar_buf, ns, i - 1, 0, {
				line_hl_group = config.options.highlights.directory,
			})
		else
			local col = #("  "):rep(item.depth)
			vim.api.nvim_buf_set_extmark(self.sidebar_buf, ns, i - 1, col, {
				end_col = col + 1,
				hl_group = status_hl(item.node.entry.status),
			})

			local suffix = stage_suffix(item.node.entry)
			if suffix ~= "" then
				local end_col = #lines[i]
				vim.api.nvim_buf_set_extmark(self.sidebar_buf, ns, i - 1, end_col - #suffix + 1, {
					end_col = end_col,
					hl_group = stage_hl(item.node.entry),
				})
			end
		end
	end
end

function Browser:clear_diff_keymaps()
	local keys = config.options.keys

	for _, buf in ipairs(self.diff_bufs) do
		if vim.api.nvim_buf_is_valid(buf) then
			unmap(buf, keys.next_file)
			unmap(buf, keys.prev_file)
		end
	end
	self.diff_bufs = {}
end

---@param bufs integer[]
function Browser:set_diff_keymaps(bufs)
	self:clear_diff_keymaps()

	local keys = config.options.keys
	for _, buf in ipairs(bufs) do
		map(buf, keys.next_file, function()
			self:select_offset(1)
		end, "DiffMagik: next changed file")
		map(buf, keys.prev_file, function()
			self:select_offset(-1)
		end, "DiffMagik: previous changed file")
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
			if self.sidebar_win and vim.api.nvim_win_is_valid(self.sidebar_win) then
				vim.api.nvim_win_set_cursor(self.sidebar_win, { i, 0 })
			end
			self:open_entry(self.flat[i].node.entry)
			return
		end
		i = i + offset
	end
end

---@param entry GitEntry
function Browser:open_entry(entry)
	if not vim.api.nvim_win_is_valid(self.main_win) then
		vim.notify("DiffMagik: target window is no longer open", vim.log.levels.ERROR)
		return
	end

	vim.api.nvim_set_current_win(self.main_win)
	vim.cmd.edit({ args = { vim.fs.joinpath(self.repo.root, entry.path) } })
	self.diffsplit:open_against_head(self.repo, entry.path)
	self.current_path = entry.path

	local bufs = { vim.api.nvim_win_get_buf(self.main_win) }
	local head_win = self.diffsplit.head_win
	if head_win and vim.api.nvim_win_is_valid(head_win) then
		table.insert(bufs, vim.api.nvim_win_get_buf(head_win))
	end
	self:set_diff_keymaps(bufs)
end

function Browser:open_selected()
	local line = vim.api.nvim_win_get_cursor(self.sidebar_win)[1]
	local item = self.flat[line]
	if not item then
		return
	end

	if item.node.is_dir then
		item.node.expanded = not item.node.expanded
		self:render_tree()
		vim.api.nvim_win_set_cursor(self.sidebar_win, { line, 0 })
	else
		self:open_entry(item.node.entry)
	end
end

function Browser:close()
	self:clear_diff_keymaps()

	if self.sidebar_win and vim.api.nvim_win_is_valid(self.sidebar_win) then
		vim.api.nvim_win_close(self.sidebar_win, true)
	end
end

function Browser:open()
	if self.sidebar_win and vim.api.nvim_win_is_valid(self.sidebar_win) then
		vim.api.nvim_set_current_win(self.sidebar_win)
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
	self.main_win = vim.api.nvim_get_current_win()

	vim.cmd.vsplit({ mods = { split = "topleft" } })
	self.sidebar_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_width(self.sidebar_win, 40)
	self.sidebar_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(self.sidebar_win, self.sidebar_buf)

	vim.api.nvim_buf_set_name(self.sidebar_buf, "diffmagik://changes")
	vim.bo[self.sidebar_buf].buftype = "nofile"
	vim.bo[self.sidebar_buf].bufhidden = "wipe"
	vim.bo[self.sidebar_buf].swapfile = false
	vim.bo[self.sidebar_buf].filetype = "diffmagik"

	vim.wo[self.sidebar_win].winfixwidth = true
	vim.wo[self.sidebar_win].number = false
	vim.wo[self.sidebar_win].relativenumber = false
	vim.wo[self.sidebar_win].signcolumn = "no"
	vim.wo[self.sidebar_win].wrap = false
	vim.wo[self.sidebar_win].cursorline = true
	vim.wo[self.sidebar_win].cursorlineopt = "line"

	self:render_tree()

	local keys = config.options.keys
	map(self.sidebar_buf, keys.open, function()
		self:open_selected()
	end, "DiffMagik: open entry")
	map(self.sidebar_buf, keys.close, function()
		self:close()
	end, "DiffMagik: close browser")
end

return Browser
