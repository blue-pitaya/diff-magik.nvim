local M = {}

local ns = vim.api.nvim_create_namespace("diff-magik")

--- Persistent browser state (there is only ever one browser instance).
local state = {
	sidebar_win = nil,
	sidebar_buf = nil,
	main_win = nil,
	head_win = nil,
	root = nil,
	entries = nil,
}

--- Run a git command and return its stdout lines, or nil on failure.
---@param args string[] arguments passed after `git`
---@return string[]|nil
local function git(args)
	local cmd = { "git" }
	vim.list_extend(cmd, args)
	local out = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return out
end

--- Find the top-level directory of the git repo containing `dir`.
---@param dir string
---@return string|nil
local function git_root(dir)
	local out = git({ "-C", dir, "rev-parse", "--show-toplevel" })
	return out and out[1] or nil
end

--- Opens a diff of a file (relative to `root`) against the current git HEAD,
--- splitting off the current window. Prints an error if the file is not
--- tracked in git or has no changes against HEAD.
---@param root string absolute path to the git repo's top level
---@param rel string path to the file, relative to `root`
---@return integer|nil head_win the window id of the created HEAD-side split
local function diff_against_head(root, rel)
	local bufnr = vim.api.nvim_get_current_buf()

	local tracked = git({ "-C", root, "ls-files", "--error-unmatch", "--", rel })
	if not tracked then
		vim.notify(("DiffMagik: '%s' is not tracked in git"):format(rel), vim.log.levels.ERROR)
		return
	end

	local changed = git({ "-C", root, "diff", "--name-only", "HEAD", "--", rel })
	if not changed then
		vim.notify("DiffMagik: failed to run git diff", vim.log.levels.ERROR)
		return
	end
	if #changed == 0 then
		vim.notify(("DiffMagik: no changes in '%s'"):format(rel), vim.log.levels.ERROR)
		return
	end

	local head_content = git({ "-C", root, "show", ("HEAD:%s"):format(rel) })
	if not head_content then
		vim.notify("DiffMagik: failed to read HEAD version of file", vim.log.levels.ERROR)
		return
	end

	vim.cmd("vsplit")
	local head_win = vim.api.nvim_get_current_win()
	local head_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(head_buf, 0, -1, false, head_content)
	vim.api.nvim_buf_set_name(head_buf, ("diffmagik://%s@HEAD"):format(rel))
	vim.bo[head_buf].buftype = "nofile"
	vim.bo[head_buf].bufhidden = "wipe"
	vim.bo[head_buf].swapfile = false
	vim.bo[head_buf].filetype = vim.bo[bufnr].filetype

	vim.api.nvim_win_set_buf(head_win, head_buf)
	vim.cmd("diffthis")

	vim.cmd("wincmd p")
	vim.cmd("diffthis")

	return head_win
end

--- Opens a diff of the current buffer's file against the current git HEAD.
--- Prints an error if the buffer has no file, the file is not tracked in a
--- git repository, or the file has no changes against HEAD.
function M.open()
	local filepath = vim.api.nvim_buf_get_name(0)

	if filepath == "" then
		vim.notify("DiffMagik: current buffer has no file", vim.log.levels.ERROR)
		return
	end

	local dir = vim.fn.fnamemodify(filepath, ":h")
	local root = git_root(dir)
	if not root then
		vim.notify("DiffMagik: not inside a git repository", vim.log.levels.ERROR)
		return
	end

	local rel = filepath:sub(#root + 2)
	diff_against_head(root, rel)
end

--- Parses one line of `git diff --name-status` output into a status/path pair.
---@param line string
---@return { status: string, path: string }
local function parse_name_status(line)
	local status, rest = line:match("^(%S+)\t(.*)$")
	status = status and status:sub(1, 1) or "?"

	if status == "R" or status == "C" then
		-- rename/copy lines are "STATUS\told\tnew"
		local _, new_path = rest:match("^(.*)\t(.*)$")
		return { status = status, path = new_path or rest }
	end

	return { status = status, path = rest }
end

--- Highlight group for a given status letter, matching the groups most
--- colorschemes already define for diff output.
---@param status string
---@return string
local function status_hl(status)
	if status == "A" or status == "?" then
		return "diffAdded"
	elseif status == "D" then
		return "diffRemoved"
	end
	return "diffChanged"
end

--- Builds the list of changed files (tracked changes vs HEAD, plus
--- untracked files) as { status: string, path: string } entries.
---@param root string
---@return { status: string, path: string }[]|nil
local function collect_changes(root)
	local tracked = git({ "-C", root, "diff", "--ignore-submodules", "--name-status", "HEAD" })
	if not tracked then
		return nil
	end

	local untracked = git({ "-C", root, "ls-files", "--others", "--exclude-standard" }) or {}

	local entries = {}
	for _, line in ipairs(tracked) do
		table.insert(entries, parse_name_status(line))
	end
	for _, path in ipairs(untracked) do
		table.insert(entries, { status = "?", path = path })
	end
	return entries
end

--- Renders `entries` into the sidebar buffer: one "<status> <path>" line
--- each, with the status letter colored per `status_hl`.
---@param entries { status: string, path: string }[]
local function render_entries(entries)
	local lines = {}
	for _, entry in ipairs(entries) do
		table.insert(lines, ("%s %s"):format(entry.status, entry.path))
	end

	vim.bo[state.sidebar_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.sidebar_buf, 0, -1, false, lines)
	vim.bo[state.sidebar_buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(state.sidebar_buf, ns, 0, -1)
	for i, entry in ipairs(entries) do
		vim.api.nvim_buf_add_highlight(state.sidebar_buf, ns, status_hl(entry.status), i - 1, 0, 1)
	end

	state.entries = entries
end

--- Opens the diff for the entry under the cursor in the sidebar, reusing
--- the window layout: the file is edited in the window the browser was
--- opened from, with its HEAD version split beside it.
local function open_selected()
	local line = vim.api.nvim_win_get_cursor(state.sidebar_win)[1]
	local entry = state.entries[line]
	if not entry then
		return
	end

	if not vim.api.nvim_win_is_valid(state.main_win) then
		vim.notify("DiffMagik: target window is no longer open", vim.log.levels.ERROR)
		return
	end

	if state.head_win and vim.api.nvim_win_is_valid(state.head_win) then
		vim.api.nvim_win_close(state.head_win, true)
	end

	vim.api.nvim_set_current_win(state.main_win)
	vim.cmd("edit " .. vim.fn.fnameescape(state.root .. "/" .. entry.path))
	state.head_win = diff_against_head(state.root, entry.path)
end

--- Closes the browser sidebar, leaving any open diff split untouched.
local function close_browser()
	if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
		vim.api.nvim_win_close(state.sidebar_win, true)
	end
end

--- Opens (or focuses, if already open) a sidebar "changes browser" listing
--- every changed file in the current git repo (working tree vs HEAD,
--- including untracked files), similar in feel to a neo-tree file browser:
--- a pinned sidebar with cursorline-based selection. Pressing <CR> or "o"
--- on an entry opens a base (HEAD) vs current split diff for that file in
--- the window the browser was opened from; "q" closes the sidebar.
--- Prints an error if not inside a git repository or if there are no
--- changes.
function M.browser()
	if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
		vim.api.nvim_set_current_win(state.sidebar_win)
		return
	end

	local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
	if dir == "" then
		dir = vim.fn.getcwd()
	end

	local root = git_root(dir)
	if not root then
		vim.notify("DiffMagik: not inside a git repository", vim.log.levels.ERROR)
		return
	end

	local entries = collect_changes(root)
	if not entries then
		vim.notify("DiffMagik: failed to run git diff", vim.log.levels.ERROR)
		return
	end
	if #entries == 0 then
		vim.notify("DiffMagik: no changes in repository", vim.log.levels.ERROR)
		return
	end

	state.root = root
	state.main_win = vim.api.nvim_get_current_win()
	state.head_win = nil

	vim.cmd("topleft 40vsplit")
	state.sidebar_win = vim.api.nvim_get_current_win()
	state.sidebar_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(state.sidebar_win, state.sidebar_buf)

	vim.api.nvim_buf_set_name(state.sidebar_buf, "diffmagik://changes")
	vim.bo[state.sidebar_buf].buftype = "nofile"
	vim.bo[state.sidebar_buf].bufhidden = "wipe"
	vim.bo[state.sidebar_buf].swapfile = false
	vim.bo[state.sidebar_buf].filetype = "diffmagik"

	vim.wo[state.sidebar_win].winfixwidth = true
	vim.wo[state.sidebar_win].number = false
	vim.wo[state.sidebar_win].relativenumber = false
	vim.wo[state.sidebar_win].signcolumn = "no"
	vim.wo[state.sidebar_win].wrap = false
	vim.wo[state.sidebar_win].cursorline = true
	vim.wo[state.sidebar_win].cursorlineopt = "line"
	vim.wo[state.sidebar_win].winhighlight = "CursorLine:DiffMagikCursorLine"

	render_entries(entries)

	vim.keymap.set("n", "<CR>", open_selected, { buffer = state.sidebar_buf, nowait = true, silent = true })
	vim.keymap.set("n", "o", open_selected, { buffer = state.sidebar_buf, nowait = true, silent = true })
	vim.keymap.set("n", "q", close_browser, { buffer = state.sidebar_buf, nowait = true, silent = true })
end

--- Sets up the plugin: registers the :DiffMagikOpen and :DiffMagikBrowser
--- user commands. Call this from your plugin manager's config/init hook.
---@param opts table|nil reserved for future configuration
function M.setup(opts)
	opts = opts or {}

	-- Falls back to the ordinary CursorLine look unless the colorscheme
	-- (or the user) defines DiffMagikCursorLine explicitly.
	vim.api.nvim_set_hl(0, "DiffMagikCursorLine", { link = "CursorLine", default = true })

	vim.api.nvim_create_user_command("DiffMagikOpen", function()
		M.open()
	end, {
		desc = "Diff the current buffer's file against git HEAD",
	})

	vim.api.nvim_create_user_command("DiffMagikBrowser", function()
		M.browser()
	end, {
		desc = "Open a sidebar browser of all changed files vs git HEAD",
	})
end

return M
