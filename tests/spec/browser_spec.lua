local h = require("helpers")

local test = h.test

local SIDEBAR = "diffmagik://changes"

---@param opts? table
local function open_browser(opts)
	local root = h.repo({ ["a.txt"] = { "a" }, ["dir/b.txt"] = { "b" } })
	h.write(root .. "/a.txt", { "a2" })
	h.write(root .. "/dir/b.txt", { "b2" })
	h.write(root .. "/new.txt", { "new" })

	vim.fn.chdir(root)
	require("diff-magik").setup(opts)
	vim.cmd.DiffMagikBrowser()

	return root
end

local function reenter_sidebar()
	vim.cmd.wincmd("l")
	vim.api.nvim_set_current_win(h.win_of(h.buf_named(SIDEBAR)))
end

---@param line integer
local function select_line(line)
	vim.api.nvim_set_current_win(h.win_of(h.buf_named(SIDEBAR)))
	vim.api.nvim_win_set_cursor(0, { line, 0 })
end

local function sidebar_lines()
	return h.lines(h.buf_named(SIDEBAR))
end

test("DiffMagikBrowser lists the changed files in a sidebar", function()
	open_browser()

	h.eq(SIDEBAR, vim.api.nvim_buf_get_name(0))
	h.eq({
		"▾ dir/",
		"  M b.txt",
		"M a.txt",
		"A new.txt",
	}, sidebar_lines())
end)

test("opening an entry shows the file against HEAD next to the sidebar", function()
	local root = open_browser()

	select_line(3)
	h.press("<CR>")

	h.eq({ root .. "/a.txt", "diffmagik://a.txt@HEAD", SIDEBAR }, h.win_names())
	h.eq(root .. "/a.txt", vim.api.nvim_buf_get_name(0))
end)

test("opening a directory collapses it", function()
	open_browser()

	select_line(1)
	h.press("<CR>")

	h.eq({
		"▸ dir/",
		"M a.txt",
		"A new.txt",
	}, sidebar_lines())
end)

test("next_file opens the following changed file from the diff pane", function()
	local root = open_browser()

	select_line(3)
	h.press("<CR>")
	h.press("1")

	h.eq({ root .. "/new.txt", SIDEBAR, "diffmagik://new.txt@HEAD" }, h.win_names())
	h.eq(4, vim.api.nvim_win_get_cursor(h.win_of(h.buf_named(SIDEBAR)))[1])
end)

test("prev_file opens the preceding changed file from the diff pane", function()
	local root = open_browser()

	select_line(3)
	h.press("<CR>")
	h.press("2")

	h.eq({ root .. "/dir/b.txt", SIDEBAR, "diffmagik://dir/b.txt@HEAD" }, h.win_names())
end)

test("stage marks the entry as staged", function()
	open_browser()

	select_line(3)
	h.press("3")

	h.eq({
		"▾ dir/",
		"  M b.txt",
		"M a.txt (S)",
		"A new.txt",
	}, sidebar_lines())
end)

test("reset discards the changes to the entry once confirmed", function()
	local root = open_browser()
	vim.fn.confirm = function()
		return 1
	end

	select_line(3)
	h.press("X")

	h.eq({ "a" }, h.read(root .. "/a.txt"))
	h.eq({
		"▾ dir/",
		"  M b.txt",
		"A new.txt",
	}, sidebar_lines())
end)

test("the inline diff style shows the deleted and added lines in one pane", function()
	open_browser()
	vim.cmd.DiffMagikBrowserDiffToggle()

	select_line(3)
	h.press("<CR>")

	local view = h.buf_named("diffmagik://a.txt@HEAD:inline")
	local ns = vim.api.nvim_create_namespace("diff-magik.file-diff")
	local highlighted = {}
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(view, ns, 0, -1, { details = true })) do
		table.insert(highlighted, { mark[2], mark[4].line_hl_group })
	end

	h.eq({ "diffmagik://a.txt@HEAD:inline", SIDEBAR }, h.win_names())
	h.eq({ "a", "a2" }, h.lines(view))
	h.eq({ { 0, "DiffMagikFileDeleted" }, { 1, "DiffMagikFileAdded" } }, highlighted)
end)

test("reset redraws the inline diff from the reverted file", function()
	local root = open_browser()
	vim.cmd.DiffMagikBrowserDiffToggle()
	vim.fn.confirm = function()
		return 1
	end

	select_line(3)
	h.press("<CR>")
	select_line(3)
	h.press("X")

	h.eq({ "a" }, h.lines(h.buf_named("diffmagik://a.txt@HEAD:inline")))
	h.eq({ "a" }, h.read(root .. "/a.txt"))
end)

test("closing the HEAD pane closes the whole split view", function()
	local root = open_browser()

	select_line(3)
	h.press("<CR>")
	vim.api.nvim_win_close(h.win_of(h.buf_named("diffmagik://a.txt@HEAD")), true)
	h.flush()

	h.eq({ root .. "/a.txt" }, h.win_names())
end)

test("entering the sidebar lists files changed in the meantime", function()
	local root = open_browser()
	h.write(root .. "/later.txt", { "later" })

	reenter_sidebar()

	h.eq({
		"▾ dir/",
		"  M b.txt",
		"M a.txt",
		"A later.txt",
		"A new.txt",
	}, sidebar_lines())
end)

test("refreshing keeps collapsed directories and the entry under the cursor", function()
	local root = open_browser()
	select_line(1)
	h.press("<CR>")
	vim.api.nvim_win_set_cursor(0, { 3, 0 })
	h.write(root .. "/later.txt", { "later" })

	reenter_sidebar()

	h.eq({
		"▸ dir/",
		"M a.txt",
		"A later.txt",
		"A new.txt",
	}, sidebar_lines())
	h.eq(4, vim.api.nvim_win_get_cursor(0)[1])
end)

test("switching the diff style reopens the current file in the new style", function()
	local root = open_browser()
	select_line(3)
	h.press("<CR>")

	vim.cmd.DiffMagikBrowserDiffToggle()

	h.eq({ "diffmagik://a.txt@HEAD:inline", SIDEBAR }, h.win_names())
	h.eq("diffmagik://a.txt@HEAD:inline", vim.api.nvim_buf_get_name(0))
end)

test("closing the sidebar closes the whole split view", function()
	local root = open_browser()
	select_line(3)
	h.press("<CR>")

	select_line(3)
	h.press("q")
	h.flush()

	h.eq({ root .. "/a.txt" }, h.win_names())
end)

test("DiffMagikBrowser focuses the sidebar when it is already open", function()
	local root = open_browser()
	select_line(3)
	h.press("<CR>")

	vim.cmd.DiffMagikBrowser()

	h.eq(SIDEBAR, vim.api.nvim_buf_get_name(0))
	h.eq({ root .. "/a.txt", "diffmagik://a.txt@HEAD", SIDEBAR }, h.win_names())
end)

test("staging from the diff pane updates the sidebar", function()
	open_browser()
	select_line(3)
	h.press("<CR>")

	h.press("3")

	h.eq({
		"▾ dir/",
		"  M b.txt",
		"M a.txt (S)",
		"A new.txt",
	}, sidebar_lines())
end)

test("the sidebar uses the keys from the config", function()
	local root = open_browser({ keys = { open = { "l" } } })

	select_line(3)
	h.press("l")

	h.eq({ root .. "/a.txt", "diffmagik://a.txt@HEAD", SIDEBAR }, h.win_names())
end)

test("DiffMagikBrowserSizeToggle switches between the fitted and the constant width", function()
	local name = ("x"):rep(56) .. ".txt"
	local root = h.repo({ ["a.txt"] = { "a" } })
	h.write(vim.fs.joinpath(root, name), { "new" })

	vim.fn.chdir(root)
	require("diff-magik").setup()
	vim.cmd.DiffMagikBrowser()
	local win = h.win_of(h.buf_named(SIDEBAR))

	h.eq(50, vim.api.nvim_win_get_width(win))

	vim.cmd.DiffMagikBrowserSizeToggle()
	h.eq(40, vim.api.nvim_win_get_width(win))
end)
