local Git = require("diff-magik.git")
local DiffSplit = require("diff-magik.diffsplit")
local Browser = require("diff-magik.browser")
local config = require("diff-magik.config")

local M = {}

---@return Git|nil, string|nil
local function current_file()
	if vim.b.diffmagik_root and vim.b.diffmagik_path then
		return Git.from_root(vim.b.diffmagik_root), vim.b.diffmagik_path
	end

	local filepath = vim.api.nvim_buf_get_name(0)
	if filepath == "" then
		vim.notify("DiffMagik: current buffer has no file", vim.log.levels.ERROR)
		return nil, nil
	end

	local repo = Git.new(vim.fs.dirname(filepath))
	if not repo then
		vim.notify("DiffMagik: not inside a git repository", vim.log.levels.ERROR)
		return nil, nil
	end

	local rel = vim.fs.relpath(repo.root, filepath)
	if not rel then
		vim.notify("DiffMagik: failed to resolve path relative to repo root", vim.log.levels.ERROR)
		return nil, nil
	end

	return repo, rel
end

---@param opts table|nil partial `DiffMagikConfig`
function M.setup(opts)
	config.setup(opts)

	local diffsplit = DiffSplit.new()
	local browser = Browser.new()

	vim.api.nvim_create_user_command("DiffMagikOpen", function()
		local repo, rel = current_file()
		if repo and rel then
			diffsplit:open_against_head(repo, rel)
		end
	end, {
		desc = "Diff the current buffer's file against git HEAD",
	})

	for _, key in ipairs(config.options.keys.stage) do
		vim.keymap.set("n", key, function()
			local repo, rel = current_file()
			if not repo or not rel then
				return
			end
			if not repo:toggle_stage(rel) then
				vim.notify(("DiffMagik: failed to update the index for '%s'"):format(rel), vim.log.levels.ERROR)
				return
			end

			browser:refresh()
		end, { desc = "DiffMagik: stage or unstage the current file" })
	end

	vim.api.nvim_create_user_command("DiffMagikBrowser", function()
		browser:open()
	end, {
		desc = "Open a sidebar browser of all changed files vs git HEAD",
	})

	vim.api.nvim_create_user_command("DiffMagikBrowserDiffToggle", function()
		browser:toggle_diff_style()
	end, {
		desc = "Switch the browser between the two-pane and single-pane diff styles",
	})

	vim.api.nvim_create_user_command("DiffMagikBrowserSizeToggle", function()
		browser:toggle_width_mode()
	end, {
		desc = "Switch the browser sidebar between the expanding and constant widths",
	})
end

return M
