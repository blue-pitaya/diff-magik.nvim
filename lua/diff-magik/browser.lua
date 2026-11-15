local Git = require("diff-magik.git")
local TreeNode = require("diff-magik.tree")
local Layout = require("diff-magik.layout")
local render = require("diff-magik.render")
local util = require("diff-magik.util")

---The changed-files sidebar and the diff it opens for the selected file.
---@class Browser
---@field config Config
---@field repo? Git repository shown, set by open
---@field tree? TreeNode
---@field flat? TreeFlatItem[] sidebar rows, in display order
---@field current_path? string file the diff is open for
---@field diff_bufs integer[] buffers of the open diff that carry the file keymaps
local Browser = {}
Browser.__index = Browser

---@type table<string, { desc: string, run: fun(self: Browser) }>
local ACTIONS = {
	open = {
		desc = "DiffMagik: open entry",
		run = function(self)
			self:open_selected()
		end,
	},
	close = {
		desc = "DiffMagik: close browser",
		run = function(self)
			self:close()
		end,
	},
	stage = {
		desc = "DiffMagik: stage or unstage entry",
		run = function(self)
			self:toggle_stage_selected()
		end,
	},
	reset = {
		desc = "DiffMagik: discard the changes to entry",
		run = function(self)
			self:reset_selected()
		end,
	},
	next_file = {
		desc = "DiffMagik: next changed file",
		run = function(self)
			self:select_offset(1)
		end,
	},
	prev_file = {
		desc = "DiffMagik: previous changed file",
		run = function(self)
			self:select_offset(-1)
		end,
	},
	toggle_width = {
		desc = "DiffMagik: toggle the sidebar width mode",
		run = function(self)
			self:toggle_width_mode()
		end,
	},
}

local SIDEBAR_ACTIONS = { "open", "stage", "reset", "close", "toggle_width" }
local DIFF_ACTIONS = { "next_file", "prev_file" }

---Creates the browser and its autocmds; the sidebar opens on `open`.
---@param config Config
---@return Browser
function Browser.new(config)
	local self = setmetatable({ config = config, diff_bufs = {} }, Browser)

	local augroup = vim.api.nvim_create_augroup("diff-magik.browser", { clear = true })

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			local winid = tonumber(args.match)
			if winid and Layout.in_split_view(winid) then
				vim.schedule(function()
					self:close_split_view()
				end)
			end
		end,
		desc = "DiffMagik: close the whole two-pane view once any of its windows is closed",
	})

	return self
end

---@param bufnr integer
---@param names string[]
function Browser:set_keymaps(bufnr, names)
	for _, name in ipairs(names) do
		local action = ACTIONS[name]
		for _, key in ipairs(self.config.keys[name]) do
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
function Browser:del_keymaps(bufnr, names)
	for _, name in ipairs(names) do
		for _, key in ipairs(self.config.keys[name]) do
			pcall(vim.keymap.del, "n", key, { buffer = bufnr })
		end
	end
end

function Browser:render_tree()
	local buf = Layout.sidebar_buf()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local flat = {}
	self.tree:flatten(0, flat)
	self.flat = flat

	Layout.fit_sidebar(render(buf, flat, self.config.highlights))
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
	local line = Layout.sidebar_cursor()
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
	if not self.repo or not Layout.has_sidebar() then
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
	Layout.set_sidebar_cursor(math.min(target, math.max(#self.flat, 1)))
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
			self:del_keymaps(buf, DIFF_ACTIONS)
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

---@param entry GitEntry
function Browser:open_entry(entry)
	local bufs = Layout.open_file(self.repo, entry.path)
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
			Layout.set_sidebar_cursor(i)
			self:open_entry(self.flat[i].node.entry)
			return
		end
		i = i + offset
	end
end

function Browser:open_selected()
	local line = Layout.sidebar_cursor()
	local item = line and self.flat and self.flat[line]
	if not line or not item then
		return
	end

	if item.node.is_dir then
		item.node.expanded = not item.node.expanded
		self:render_tree()
		Layout.set_sidebar_cursor(line)
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
		Layout.reload_main()
	end

	self:refresh()
end

function Browser:toggle_diff_style()
	util.info(("browser diff style is %s"):format(Layout.toggle_diff_style()))

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
	util.info(("sidebar width is %s"):format(Layout.toggle_width_mode()))
end

function Browser:close()
	self:clear_diff_keymaps()
	Layout.close()
end

function Browser:close_split_view()
	self:clear_diff_keymaps()
	Layout.close_split_view()
end

---Opens the sidebar for the repository of the current buffer, or focuses it when already open.
function Browser:open()
	if Layout.focus_sidebar() then
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

	local bufnr = Layout.open_sidebar()
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
