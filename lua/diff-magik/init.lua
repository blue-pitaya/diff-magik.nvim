local Git = require("diff-magik.git")
local DiffSplit = require("diff-magik.diffsplit")
local Browser = require("diff-magik.browser")

local M = {}

---@param opts table|nil reserved for future configuration
function M.setup(opts)
	opts = opts or {}

	local browser = Browser.new()
	local diffsplit = DiffSplit.new()

	browser:setup_highlights()

	vim.api.nvim_create_user_command("DiffMagikOpen", function()
		local filepath = vim.api.nvim_buf_get_name(0)

		if filepath == "" then
			vim.notify("DiffMagik: current buffer has no file", vim.log.levels.ERROR)
			return
		end

		local dir = vim.fs.dirname(filepath)
		local repo = Git.new(dir)
		if not repo then
			vim.notify("DiffMagik: not inside a git repository", vim.log.levels.ERROR)
			return
		end

		local rel = vim.fs.relpath(repo.root, filepath)
		if not rel then
			vim.notify("DiffMagik: failed to resolve path relative to repo root", vim.log.levels.ERROR)
			return
		end

		diffsplit:open_against_head(repo, rel)
	end, {
		desc = "Diff the current buffer's file against git HEAD",
	})

	vim.api.nvim_create_user_command("DiffMagikBrowser", function()
		browser:open()
	end, {
		desc = "Open a sidebar browser of all changed files vs git HEAD",
	})
end

return M
