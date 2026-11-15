---@class DiffMagikKeys
---@field open string[] open the entry under the cursor, or toggle a directory
---@field close string[] close the sidebar
---@field next_file string[] open the next changed file, from either diff pane
---@field prev_file string[] open the previous changed file, from either diff pane
---@field stage string[] stage the entry under the cursor, or unstage it if fully staged
---@field reset string[] discard every change to the entry under the cursor

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

---@alias DiffMagikDiffStyle
---| "split" # the working copy and the base side by side, in two panes
---| "inline" # one pane, with the deleted lines drawn above the added ones

---Plugin options: the user's settings merged over the defaults.
---@class Config
---@field keys DiffMagikKeys
---@field highlights DiffMagikHighlights
---@field fillchar string 'fillchars' diff filler, drawn over missing lines
---@field diff_style DiffMagikDiffStyle the browser starts in this style
---@field fold_context integer untouched lines kept around each hunk before the browser folds the rest
---@field command_timeout integer milliseconds a git command may run before it is killed and fails
local Config = {}
Config.__index = Config

local DEFAULTS = {
	keys = {
		open = { "<CR>", "o" },
		close = { "q" },
		next_file = { "1" },
		prev_file = { "2" },
		stage = { "3" },
		reset = { "X" },
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
	diff_style = "split",
	fold_context = 3,
	command_timeout = 5000,
}

---@param opts table?
---@return Config
function Config.new(opts)
	opts = opts or {}
	local defaults = vim.deepcopy(DEFAULTS)

	return setmetatable({
		keys = vim.tbl_extend("force", defaults.keys, opts.keys or {}),
		highlights = vim.tbl_extend("force", defaults.highlights, opts.highlights or {}),
		fillchar = opts.fillchar or defaults.fillchar,
		diff_style = opts.diff_style or defaults.diff_style,
		fold_context = opts.fold_context or defaults.fold_context,
		command_timeout = opts.command_timeout or defaults.command_timeout,
	}, Config)
end

return Config
