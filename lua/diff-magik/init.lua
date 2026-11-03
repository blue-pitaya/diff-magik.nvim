local Git = require("diff-magik.git")
local DiffSplit = require("diff-magik.diffsplit")
local FileDiff = require("diff-magik.filediff")
local Layout = require("diff-magik.layout")
local Browser = require("diff-magik.browser")
local Commit = require("diff-magik.commit")
local util = require("diff-magik.util")
local config = require("diff-magik.config")

local M = {}

---@return Git?
---@return string?
local function current_file()
	local repo, rel, err = Git.for_buffer(vim.api.nvim_get_current_buf())
	if not repo then
		util.error(err)
	end
	return repo, rel
end

---@param opts? table
function M.setup(opts)
	config.setup(opts)

	DiffSplit.setup()
	FileDiff.setup()
	Layout.setup()
	Browser.setup()

	vim.api.nvim_create_user_command("DiffMagikOpen", function()
		local repo, rel = current_file()
		if repo and rel then
			DiffSplit.open_against_head(repo, rel)
		end
	end, {
		desc = "Diff the current buffer's file against git HEAD",
	})

	for _, key in ipairs(config.options.keys.stage) do
		vim.keymap.set("n", key, function()
			local repo, rel = current_file()
			if repo and rel then
				Browser.toggle_stage(repo, rel)
			end
		end, { desc = "DiffMagik: stage or unstage the current file" })
	end

	for _, key in ipairs(config.options.keys.commit) do
		vim.keymap.set("n", key, function()
			local repo = Git.for_buffer(vim.api.nvim_get_current_buf()) or Git.new(vim.fn.getcwd())
			if not repo then
				util.error("not inside a git repository")
				return
			end
			Commit.open(repo)
		end, { desc = "DiffMagik: commit the staged changes" })
	end

	vim.api.nvim_create_user_command("DiffMagikBrowser", function()
		Browser.open()
	end, {
		desc = "Open a sidebar browser of all changed files vs git HEAD",
	})

	vim.api.nvim_create_user_command("DiffMagikBrowserDiffToggle", function()
		Browser.toggle_diff_style()
	end, {
		desc = "Switch the browser between the two-pane and single-pane diff styles",
	})

	vim.api.nvim_create_user_command("DiffMagikBrowserSizeToggle", function()
		Browser.toggle_width_mode()
	end, {
		desc = "Switch the browser sidebar between the expanding and constant widths",
	})
end

return M
