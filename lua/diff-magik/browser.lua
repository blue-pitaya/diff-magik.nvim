local Git = require("diff-magik.git")
local TreeNode = require("diff-magik.tree")
local render = require("diff-magik.render")
local util = require("diff-magik.util")

---@class Browser
---@field config Config
---@field layout Layout
---@field repo? Git
---@field tree? TreeNode
---@field flat? TreeFlatItem[]
---@field current_path? string
---@field diff_bufs integer[]
local Browser = {}
Browser.__index = Browser

---@param bufnr integer
---@param keys string[]
---@param desc string
---@param run fun()
local function map(bufnr, keys, desc, run)
	for _, key in ipairs(keys) do
		vim.keymap.set("n", key, run, { buffer = bufnr, nowait = true, silent = true, desc = desc })
	end
end

---@param bufnr integer
---@param keys string[]
local function unmap(bufnr, keys)
	for _, key in ipairs(keys) do
		pcall(vim.keymap.del, "n", key, { buffer = bufnr })
	end
end

---@param config Config
---@param layout Layout
---@return Browser
function Browser.new(config, layout)
	local self = setmetatable({ config = config, layout = layout, diff_bufs = {} }, Browser)

	local augroup = vim.api.nvim_create_augroup("diff-magik.browser", { clear = true })

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			local winid = tonumber(args.match)
			if winid and self.layout:in_split_view(winid) then
				vim.schedule(function()
					self:close_split_view()
				end)
			end
		end,
		desc = "DiffMagik: close the whole two-pane view once any of its windows is closed",
	})

	return self
end

function Browser:render_tree()
	local buf = self.layout:get_sidebar_buf()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local flat = {}
	self.tree:flatten(0, flat)
	self.flat = flat

	self.layout:fit_sidebar(render(buf, flat, self.config.highlights))
end

---@param path string?
---@return integer?
function Browser:index_of(path)
	if not self.flat or not path then
		return nil
	end

	for i, item in ipairs(self.flat) do
		if item.node.path == path then
			return i
		end
	end
end

---@return TreeFlatItem?
function Browser:selected_item()
	local line = self.layout:sidebar_cursor()
	return line and self.flat and self.flat[line]
end

---@return GitEntry?
function Browser:selected_entry()
	local item = self:selected_item()
	if not item or item.node.is_dir then
		return nil
	end
	return item.node.entry
end

function Browser:refresh()
	if not self.repo or not self.layout:has_sidebar() then
		return
	end

	local entries, err = self.repo:get_changed_files()
	if err ~= nil then
		return
	end

	local selected = self:selected_item()

	local collapsed = {}
	if self.tree then
		self.tree:collect_collapsed(collapsed)
	end

	self.tree = TreeNode.new(entries)
	self.tree:sort()
	self.tree:apply_collapsed(collapsed)

	self:render_tree()

	local target = selected and self:index_of(selected.node.path) or 1
	self.layout:set_sidebar_cursor(math.min(target, math.max(#self.flat, 1)))
end

---@param repo Git
---@param rel string
function Browser:toggle_stage(repo, rel)
	local _, err = repo:toggle_stage(rel)
	if err ~= nil then
		util.error(("failed to update the index for '%s': %s"):format(rel, err))
		return
	end

	self:refresh()
end

function Browser:clear_diff_keymaps()
	for _, buf in ipairs(self.diff_bufs) do
		if vim.api.nvim_buf_is_valid(buf) then
			unmap(buf, self.config.keys.next_file)
			unmap(buf, self.config.keys.prev_file)
		end
	end
	self.diff_bufs = {}
end

---@param bufs integer[]
function Browser:set_diff_keymaps(bufs)
	self:clear_diff_keymaps()

	local keys = self.config.keys
	for _, buf in ipairs(bufs) do
		map(buf, keys.next_file, "DiffMagik: next changed file", function()
			self:select_offset(1)
		end)
		map(buf, keys.prev_file, "DiffMagik: previous changed file", function()
			self:select_offset(-1)
		end)
	end

	self.diff_bufs = bufs
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

---@param offset integer
function Browser:select_offset(offset)
	local index = self:index_of(self.current_path)
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

function Browser:open_selected()
	local line = self.layout:sidebar_cursor()
	local item = line and self.flat and self.flat[line]
	if not line or not item then
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

function Browser:toggle_stage_selected()
	local entry = self:selected_entry()
	if self.repo and entry then
		self:toggle_stage(self.repo, entry.path)
	end
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

	local _, err = self.repo:reset(entry.path)
	if err ~= nil then
		util.error(("failed to reset '%s': %s"):format(entry.path, err))
		return
	end

	if self.current_path == entry.path then
		self.layout:reload_main()
	end

	self:refresh()
end

function Browser:toggle_diff_style()
	util.info(("browser diff style is %s"):format(self.layout:toggle_diff_style()))

	local index = self:index_of(self.current_path)
	if not index then
		return
	end

	local from = vim.api.nvim_get_current_win()
	self:open_entry(self.flat[index].node.entry)
	if vim.api.nvim_win_is_valid(from) then
		vim.api.nvim_set_current_win(from)
	end
end

function Browser:toggle_width_mode()
	util.info(("sidebar width is %s"):format(self.layout:toggle_width_mode()))
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

	local repo, err = Git.new(dir)
	if err ~= nil then
		util.error(err)
		return
	end

	local entries
	entries, err = repo:get_changed_files()
	if err ~= nil then
		util.error(("failed to run git status: %s"):format(err))
		return
	end
	if #entries == 0 then
		util.error("no changes in repository")
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

	local keys = self.config.keys
	map(bufnr, keys.open, "DiffMagik: open entry", function()
		self:open_selected()
	end)
	map(bufnr, keys.stage, "DiffMagik: stage or unstage entry", function()
		self:toggle_stage_selected()
	end)
	map(bufnr, keys.reset, "DiffMagik: discard the changes to entry", function()
		self:reset_selected()
	end)
	map(bufnr, keys.close, "DiffMagik: close browser", function()
		self:close()
	end)
	map(bufnr, keys.toggle_width, "DiffMagik: toggle the sidebar width mode", function()
		self:toggle_width_mode()
	end)
end

return Browser
