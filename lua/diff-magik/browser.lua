local Git = require("diff-magik.git")
local TreeNode = require("diff-magik.tree")
local Layout = require("diff-magik.layout")
local render = require("diff-magik.render")
local config = require("diff-magik.config")

---@class Browser
---@field layout Layout
---@field repo Git|nil
---@field tree TreeNode|nil
---@field flat TreeFlatItem[]|nil
---@field current_path string|nil
---@field diff_bufs integer[]
local Browser = {}
Browser.__index = Browser

local group_id = 0

function Browser.new()
	group_id = group_id + 1

	local self = setmetatable({ layout = Layout.new(), diff_bufs = {} }, Browser)
	local augroup = vim.api.nvim_create_augroup(("diff-magik.browser.%d"):format(group_id), { clear = true })

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			if self.layout:in_split_view(tonumber(args.match)) then
				vim.schedule(function()
					self:close_split_view()
				end)
			end
		end,
		desc = "DiffMagik: close the whole two-pane view once any of its windows is closed",
	})

	return self
end

---@class BrowserAction
---@field desc string
---@field run fun(browser: Browser)

---@type table<string, BrowserAction>
local ACTIONS = {
	open = { desc = "DiffMagik: open entry", run = function(b) b:open_selected() end },
	close = { desc = "DiffMagik: close browser", run = function(b) b:close() end },
	stage = { desc = "DiffMagik: stage or unstage entry", run = function(b) b:toggle_stage_selected() end },
	reset = { desc = "DiffMagik: discard the changes to entry", run = function(b) b:reset_selected() end },
	next_file = { desc = "DiffMagik: next changed file", run = function(b) b:select_offset(1) end },
	prev_file = { desc = "DiffMagik: previous changed file", run = function(b) b:select_offset(-1) end },
	toggle_width = { desc = "DiffMagik: toggle the sidebar width mode", run = function(b) b:toggle_width_mode() end },
}

local SIDEBAR_ACTIONS = { "open", "stage", "reset", "close", "toggle_width" }
local DIFF_ACTIONS = { "next_file", "prev_file" }

---@param bufnr integer
---@param names string[]
function Browser:set_keymaps(bufnr, names)
	for _, name in ipairs(names) do
		local action = ACTIONS[name]
		for _, key in ipairs(config.options.keys[name]) do
			vim.keymap.set("n", key, function()
				action.run(self)
			end, {
				buffer = bufnr,
				nowait = true,
				silent = true,
				desc = action.desc,
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

function Browser:render_tree()
	local buf = self.layout.sidebar_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local flat = {}
	self.tree:flatten(0, flat)
	self.flat = flat

	self.layout:fit_sidebar(render(buf, flat))
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

function Browser:toggle_diff_style()
	local style = self.layout:toggle_diff_style()
	vim.notify(("DiffMagik: browser diff style is %s"):format(style))

	local index = self:current_index()
	local item = index and self.flat[index]
	if not item then
		return
	end

	local from = vim.api.nvim_get_current_win()
	self:open_entry(item.node.entry)
	if vim.api.nvim_win_is_valid(from) then
		vim.api.nvim_set_current_win(from)
	end
end

function Browser:toggle_width_mode()
	local mode = self.layout:toggle_width_mode()
	vim.notify(("DiffMagik: sidebar width is %s"):format(mode))
end

function Browser:close()
	self:clear_diff_keymaps()
	self.layout:close()
end

function Browser:close_split_view()
	self:clear_diff_keymaps()
	self.layout:close_split_view()
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
