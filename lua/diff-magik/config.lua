---@class DiffMagikKeys
---@field open string[] open the entry under the cursor, or toggle a directory
---@field close string[] close the sidebar
---@field next_file string[] open the next changed file, from either diff pane
---@field prev_file string[] open the previous changed file, from either diff pane

---@class DiffMagikHighlights
---@field added string status letter for files absent from HEAD
---@field changed string status letter for modified files
---@field removed string status letter for files deleted from the working tree
---@field directory string directory rows in the sidebar
---@field staged string the "(S)" marker
---@field staged_dirty string the "(S*)" marker
---@field head_win string 'winhighlight' for the HEAD pane
---@field main_win string 'winhighlight' for the working-copy pane

---@class DiffMagikConfig
---@field keys DiffMagikKeys
---@field highlights DiffMagikHighlights
---@field fillchar string 'fillchars' diff filler, drawn over missing lines

---@type DiffMagikConfig
local defaults = {
	keys = {
		open = { "<CR>", "o" },
		close = { "q" },
		next_file = { "<C-n>" },
		prev_file = { "<C-p>" },
	},
	highlights = {
		added = "Added",
		changed = "Changed",
		removed = "Removed",
		directory = "Directory",
		staged = "Added",
		staged_dirty = "DiagnosticWarn",
		head_win = "DiffAdd:DiffDelete,DiffDelete:DiffviewDiffDeleteDim",
		main_win = "DiffDelete:DiffviewDiffDeleteDim",
	},
	fillchar = "╱",
}

local M = {}

---@type DiffMagikConfig
M.options = vim.deepcopy(defaults)

---@param opts table|nil partial `DiffMagikConfig`
function M.setup(opts)
	opts = opts or {}

	local options = vim.deepcopy(defaults)
	options.keys = vim.tbl_extend("force", options.keys, opts.keys or {})
	options.highlights = vim.tbl_extend("force", options.highlights, opts.highlights or {})
	options.fillchar = opts.fillchar or options.fillchar

	M.options = options
end

return M
