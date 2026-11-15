local Git = require("diff-magik.git")
local BufferOrigin = require("diff-magik.buffer-origin")
local DiffSplit = require("diff-magik.diff-split")
local FileDiff = require("diff-magik.file-diff")
local Layout = require("diff-magik.layout")
local Browser = require("diff-magik.browser")
local util = require("diff-magik.util")
local Config = require("diff-magik.config")

local M = {}

---@param opts? table
function M.setup(opts)
	local config = Config.new(opts)

	DiffSplit.setup(config)
	FileDiff.setup(config)
	Layout.setup(config)
	Browser.setup(config)

	vim.api.nvim_create_user_command("DiffMagikOpen", function()
		local origin, err = BufferOrigin.of(vim.api.nvim_get_current_buf())
		if err ~= nil then
			util.error(err)
			return
		end
		DiffSplit.open_against_head(Git.from_root(origin.root), origin.rel)
	end, {
		desc = "Diff the current buffer's file against git HEAD",
	})

	for _, key in ipairs(config.keys.stage) do
		vim.keymap.set("n", key, function()
			local origin, err = BufferOrigin.of(vim.api.nvim_get_current_buf())
			if err ~= nil then
				util.error(err)
				return
			end
			Browser.toggle_stage(Git.from_root(origin.root), origin.rel)
		end, { desc = "DiffMagik: stage or unstage the current file" })
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
end

return M
