local Git = require("diff-magik.git")
local TreeNode = require("diff-magik.tree")
local Layout = require("diff-magik.layout")
local render = require("diff-magik.render")
local config = require("diff-magik.config")

---@class BrowserState
---@field repo? Git
---@field tree? TreeNode
---@field flat? TreeFlatItem[]
---@field current_path? string
---@field diff_bufs integer[]
local state = { diff_bufs = {} }

local M = {}

---@type table<string, { desc: string, run: fun() }>
local ACTIONS = {
	open = { desc = "DiffMagik: open entry", run = function() M.open_selected() end },
	close = { desc = "DiffMagik: close browser", run = function() M.close() end },
	stage = { desc = "DiffMagik: stage or unstage entry", run = function() M.toggle_stage_selected() end },
	reset = { desc = "DiffMagik: discard the changes to entry", run = function() M.reset_selected() end },
	next_file = { desc = "DiffMagik: next changed file", run = function() M.select_offset(1) end },
	prev_file = { desc = "DiffMagik: previous changed file", run = function() M.select_offset(-1) end },
	toggle_width = { desc = "DiffMagik: toggle the sidebar width mode", run = function() M.toggle_width_mode() end },
}

local SIDEBAR_ACTIONS = { "open", "stage", "reset", "close", "toggle_width" }
local DIFF_ACTIONS = { "next_file", "prev_file" }

---@param bufnr integer
---@param names string[]
local function set_keymaps(bufnr, names)
	for _, name in ipairs(names) do
		local action = ACTIONS[name]
		for _, key in ipairs(config.options.keys[name]) do
			vim.keymap.set("n", key, action.run, {
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

local function render_tree()
	local buf = Layout.sidebar_buf()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local flat = {}
	state.tree:flatten(0, flat)
	state.flat = flat

	Layout.fit_sidebar(render(buf, flat))
end

function M.refresh()
	if not state.repo or not Layout.has_sidebar() then
		return
	end

	local entries = state.repo:get_changed_files()
	if not entries then
		return
	end

	local line = Layout.sidebar_cursor()
	local cursor_path = line and state.flat and state.flat[line] and state.flat[line].path

	local collapsed = {}
	if state.tree then
		state.tree:collect_collapsed(collapsed)
	end

	state.tree = TreeNode.new(entries)
	state.tree:sort()
	state.tree:apply_collapsed(collapsed)

	render_tree()

	local target = 1
	for i, item in ipairs(state.flat) do
		if item.path == cursor_path then
			target = i
			break
		end
	end
	Layout.set_sidebar_cursor(math.min(target, math.max(#state.flat, 1)))
end

local function clear_diff_keymaps()
	for _, buf in ipairs(state.diff_bufs) do
		if vim.api.nvim_buf_is_valid(buf) then
			del_keymaps(buf, DIFF_ACTIONS)
		end
	end
	state.diff_bufs = {}
end

---@param bufs integer[]
local function set_diff_keymaps(bufs)
	clear_diff_keymaps()

	for _, buf in ipairs(bufs) do
		set_keymaps(buf, DIFF_ACTIONS)
	end

	state.diff_bufs = bufs
end

---@return integer?
local function current_index()
	if not state.flat or not state.current_path then
		return nil
	end

	for i, item in ipairs(state.flat) do
		if not item.node.is_dir and item.node.entry.path == state.current_path then
			return i
		end
	end
end

---@param entry GitEntry
local function open_entry(entry)
	local bufs = Layout.open_file(state.repo, entry.path)
	if not bufs then
		return
	end

	state.current_path = entry.path
	set_diff_keymaps(bufs)
end

---@param offset integer
function M.select_offset(offset)
	local index = current_index()
	if not index then
		return
	end

	local i = index + offset
	while state.flat[i] do
		if not state.flat[i].node.is_dir then
			Layout.set_sidebar_cursor(i)
			open_entry(state.flat[i].node.entry)
			return
		end
		i = i + offset
	end
end

function M.open_selected()
	local line = Layout.sidebar_cursor()
	local item = line and state.flat[line]
	if not item then
		return
	end

	if item.node.is_dir then
		item.node.expanded = not item.node.expanded
		render_tree()
		Layout.set_sidebar_cursor(line)
	else
		open_entry(item.node.entry)
	end
end

---@return GitEntry?
local function selected_entry()
	local line = Layout.sidebar_cursor()
	local item = line and state.flat and state.flat[line]
	if not item or item.node.is_dir then
		return nil
	end
	return item.node.entry
end

function M.toggle_stage_selected()
	local entry = selected_entry()
	if not state.repo or not entry then
		return
	end

	if not state.repo:toggle_stage(entry.path) then
		vim.notify(("DiffMagik: failed to update the index for '%s'"):format(entry.path), vim.log.levels.ERROR)
		return
	end

	M.refresh()
end

function M.reset_selected()
	local entry = selected_entry()
	if not state.repo or not entry then
		return
	end

	local prompt = ("DiffMagik: discard all changes to '%s'?"):format(entry.path)
	if vim.fn.confirm(prompt, "&yes\n&no", 2, "Question") ~= 1 then
		return
	end

	if not state.repo:reset(entry.path) then
		vim.notify(("DiffMagik: failed to reset '%s'"):format(entry.path), vim.log.levels.ERROR)
		return
	end

	if state.current_path == entry.path then
		Layout.reload_main()
	end

	M.refresh()
end

function M.toggle_diff_style()
	local style = Layout.toggle_diff_style()
	vim.notify(("DiffMagik: browser diff style is %s"):format(style))

	local index = current_index()
	local item = index and state.flat[index]
	if not item then
		return
	end

	local from = vim.api.nvim_get_current_win()
	open_entry(item.node.entry)
	if vim.api.nvim_win_is_valid(from) then
		vim.api.nvim_set_current_win(from)
	end
end

function M.toggle_width_mode()
	local mode = Layout.toggle_width_mode()
	vim.notify(("DiffMagik: sidebar width is %s"):format(mode))
end

function M.close()
	clear_diff_keymaps()
	Layout.close()
end

local function close_split_view()
	clear_diff_keymaps()
	Layout.close_split_view()
end

function M.setup()
	local augroup = vim.api.nvim_create_augroup("diff-magik.browser", { clear = true })

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			if Layout.in_split_view(tonumber(args.match)) then
				vim.schedule(close_split_view)
			end
		end,
		desc = "DiffMagik: close the whole two-pane view once any of its windows is closed",
	})
end

function M.open()
	if Layout.focus_sidebar() then
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

	state.repo = repo
	state.tree = tree

	local bufnr = Layout.open_sidebar()
	render_tree()

	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = bufnr,
		callback = function()
			M.refresh()
		end,
		desc = "DiffMagik: refresh the changed-file list",
	})

	set_keymaps(bufnr, SIDEBAR_ACTIONS)
end

return M
