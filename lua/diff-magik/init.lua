local Git = require("diff-magik.git")
local BufferOrigin = require("diff-magik.buffer-origin")
local DiffSplit = require("diff-magik.diff-split")
local FileDiff = require("diff-magik.file-diff")
local Layout = require("diff-magik.layout")
local Browser = require("diff-magik.browser")
local Commit = require("diff-magik.commit")
local util = require("diff-magik.util")
local config = require("diff-magik.config")

local M = {}

---@return BufferOrigin?
local function current_file()
	local origin, err = BufferOrigin.of(vim.api.nvim_get_current_buf())
	if err ~= nil then
		util.error(err)
	end
	return origin
end

---@param opts? table
function M.setup(opts)
	config.setup(opts)

	DiffSplit.setup()
	FileDiff.setup()
	Layout.setup()
	Browser.setup()

	vim.api.nvim_create_user_command("DiffMagikOpen", function()
		local origin = current_file()
		if origin then
			DiffSplit.open_against_head(Git.from_root(origin.root), origin.rel)
		end
	end, {
		desc = "Diff the current buffer's file against git HEAD",
	})

	for _, key in ipairs(config.options.keys.stage) do
		vim.keymap.set("n", key, function()
			local origin = current_file()
			if origin then
				Browser.toggle_stage(Git.from_root(origin.root), origin.rel)
			end
		end, { desc = "DiffMagik: stage or unstage the current file" })
	end

	for _, key in ipairs(config.options.keys.commit) do
		vim.keymap.set("n", key, function()
			local origin = BufferOrigin.of(vim.api.nvim_get_current_buf())
			local repo, err
			if origin then
				repo = Git.from_root(origin.root)
			else
				repo, err = Git.new(vim.fn.getcwd())
			end
			if err ~= nil then
				util.error(err)
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
