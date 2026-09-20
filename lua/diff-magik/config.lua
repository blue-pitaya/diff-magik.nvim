---@class DiffMagikKeys
---@field open string[] open the entry under the cursor, or toggle a directory
---@field close string[] close the sidebar
---@field next_file string[] open the next changed file, from either diff pane
---@field prev_file string[] open the previous changed file, from either diff pane
---@field stage string[] stage the entry under the cursor, or unstage it if fully staged
---@field reset string[] discard every change to the entry under the cursor
---@field toggle_width string[] switch the sidebar between the expanding and constant widths

---@class DiffMagikHighlights
---@field added string status letter for files absent from HEAD
---@field changed string status letter for modified files
---@field removed string status letter for files deleted from the working tree
---@field directory string directory rows in the sidebar
---@field staged string the "(S)" marker
---@field staged_dirty string the "(S*)" marker
---@field head_win string 'winhighlight' for the HEAD pane
---@field main_win string 'winhighlight' for the working-copy pane
---@field file_added string added lines in the in-file diff, `DiffAdd`'s colors by default
---@field file_deleted string deleted lines in the in-file diff, `DiffDelete`'s colors by default

---@alias DiffMagikWidthMode
---| "expand" # grow the sidebar to fit the widest row
---| "constant" # keep the sidebar at its minimum width

---@alias DiffMagikDiffStyle
---| "split" # the working copy and the base side by side, in two panes
---| "inline" # one pane, with the deleted lines drawn above the added ones

---@class DiffMagikConfig
---@field keys DiffMagikKeys
---@field highlights DiffMagikHighlights
---@field fillchar string 'fillchars' diff filler, drawn over missing lines
---@field width_mode DiffMagikWidthMode the sidebar starts in this mode
---@field diff_style DiffMagikDiffStyle the browser starts in this style
---@field fold_context integer untouched lines kept around each hunk before the browser folds the rest

---@type DiffMagikConfig
local defaults = {
	keys = {
		open = { "<CR>", "o" },
		close = { "q" },
		next_file = { "1" },
		prev_file = { "2" },
		stage = { "3" },
		reset = { "X" },
		toggle_width = { "N" },
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
		file_added = "DiffMagikFileAdded",
		file_deleted = "DiffMagikFileDeleted",
	},
	fillchar = "╱",
	width_mode = "expand",
	diff_style = "split",
	fold_context = 3,
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
	options.width_mode = opts.width_mode or options.width_mode
	options.diff_style = opts.diff_style or options.diff_style
	options.fold_context = opts.fold_context or options.fold_context

	M.options = options
end

return M
