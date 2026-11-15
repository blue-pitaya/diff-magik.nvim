local util = require("diff-magik.util")
local BufferOrigin = require("diff-magik.buffer-origin")

local ns = vim.api.nvim_create_namespace("diff-magik.file-diff")

local COPIED_HL = {
	DiffMagikFileAdded = "DiffAdd",
	DiffMagikFileDeleted = "DiffDelete",
}

local FOLD_OPTS = {
	foldmethod = "expr",
	foldexpr = "v:lua.require'diff-magik.file-diff'.foldexpr(v:lnum)",
	foldenable = true,
	foldlevel = 0,
}

local FOLD_OPT_NAMES = vim.tbl_keys(FOLD_OPTS)

---An inline diff: a read-only view buffer showing the source buffer's lines
---interleaved with the base lines they replaced.
---@class FileDiff
---@field view integer scratch buffer the diff is drawn in
---@field source integer buffer of the file being diffed
---@field base string base version as text, for vim.text.diff
---@field base_lines string[] base version as lines
---@field keep? table<integer, boolean> view lines left unfolded; nil when nothing changed
---@field config Config
local FileDiff = {}
FileDiff.__index = FileDiff

---Set by setup; handed to every diff attach creates.
---@type Config
local config

---Diffs by view buffer.
---@type table<integer, FileDiff>
local active = {}

---Window options saved before the diff's fold options replaced them, by window.
---@type table<integer, table<string, any>>
local win_opts = {}

local function define_hl()
	for name, source in pairs(COPIED_HL) do
		local hl = vim.api.nvim_get_hl(0, { name = source, link = false }) --[[@as vim.api.keyset.highlight]]
		vim.api.nvim_set_hl(0, name, hl)
	end
end

---@param lines string[]
---@return string
local function as_text(lines)
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

---@param ranges integer[][]
---@param total integer
---@param context integer untouched lines kept around each range
---@return table<integer, boolean>?
local function unfolded_lines(ranges, total, context)
	if #ranges == 0 then
		return nil
	end

	local keep = {}

	for _, range in ipairs(ranges) do
		for lnum = math.max(range[1] - context, 1), math.min(range[2] + context, total) do
			keep[lnum] = true
		end
	end

	return keep
end

---@param winid integer
local function restore_window(winid)
	local saved = win_opts[winid]
	if saved and vim.api.nvim_win_is_valid(winid) then
		util.set_wo(winid, saved)
	end
	win_opts[winid] = nil
end

---@param source integer
---@return FileDiff[]
local function diffs_of(source)
	local diffs = {}
	for _, diff in pairs(active) do
		if diff.source == source then
			table.insert(diffs, diff)
		end
	end
	return diffs
end

---@param view integer
---@param source integer
---@param base_lines string[]
---@param diff_config Config
---@return FileDiff
function FileDiff.new(view, source, base_lines, diff_config)
	return setmetatable({
		view = view,
		source = source,
		base = as_text(base_lines),
		base_lines = base_lines,
		config = diff_config,
	}, FileDiff)
end

---@param lnum integer
---@return string
function FileDiff:fold_level(lnum)
	if not self.keep or self.keep[lnum] then
		return "0"
	end
	return "1"
end

---Applies the fold options to every window showing the view.
---@param force boolean also recompute folds in windows that already have them
function FileDiff:fold_windows(force)
	for _, winid in ipairs(vim.fn.win_findbuf(self.view)) do
		if not win_opts[winid] then
			win_opts[winid] = util.save_wo(winid, FOLD_OPT_NAMES)
			util.set_wo(winid, FOLD_OPTS)
		elseif force then
			vim.api.nvim_win_call(winid, function()
				vim.cmd("normal! zX")
			end)
		end
	end
end

---Puts the fold method back in windows where something (e.g. an LSP) replaced it.
function FileDiff:refold_windows()
	for _, winid in ipairs(vim.fn.win_findbuf(self.view)) do
		if win_opts[winid] and vim.api.nvim_win_is_valid(winid) then
			if vim.wo[winid].foldmethod ~= FOLD_OPTS.foldmethod or vim.wo[winid].foldexpr ~= FOLD_OPTS.foldexpr then
				util.set_wo(winid, { foldmethod = FOLD_OPTS.foldmethod, foldexpr = FOLD_OPTS.foldexpr })
			end
		end
	end
end

---Redraws the view from the source buffer's current lines.
function FileDiff:render()
	if not vim.api.nvim_buf_is_valid(self.view) or not vim.api.nvim_buf_is_valid(self.source) then
		return
	end

	if not vim.api.nvim_buf_is_loaded(self.source) then
		vim.fn.bufload(self.source)
	end

	local current = vim.api.nvim_buf_get_lines(self.source, 0, -1, false)
	local hunks = vim.text.diff(self.base, as_text(current), { result_type = "indices" }) --[[@as integer[][] ]]

	local hl = self.config.highlights
	local lines = {}
	local groups = {}
	local ranges = {}
	local next_b = 1

	for _, hunk in ipairs(hunks) do
		local start_a, count_a, start_b, count_b = hunk[1], hunk[2], hunk[3], hunk[4]
		local first_b = count_b > 0 and start_b or start_b + 1

		for lnum = next_b, first_b - 1 do
			table.insert(lines, current[lnum])
		end

		local first = #lines + 1
		for i = 0, count_a - 1 do
			table.insert(lines, self.base_lines[start_a + i] or "")
			groups[#lines] = hl.file_deleted
		end
		for i = 0, count_b - 1 do
			table.insert(lines, current[start_b + i])
			groups[#lines] = hl.file_added
		end
		table.insert(ranges, { first, #lines })

		next_b = first_b + count_b
	end

	for lnum = next_b, #current do
		table.insert(lines, current[lnum])
	end

	self.keep = unfolded_lines(ranges, #lines, self.config.fold_context)

	vim.bo[self.view].modifiable = true
	vim.api.nvim_buf_set_lines(self.view, 0, -1, false, lines)
	vim.bo[self.view].modifiable = false

	vim.api.nvim_buf_clear_namespace(self.view, ns, 0, -1)
	for lnum, group in pairs(groups) do
		vim.api.nvim_buf_set_extmark(self.view, ns, lnum - 1, 0, {
			line_hl_group = group,
		})
	end

	self:fold_windows(false)
end

---'foldexpr' of the view windows; evaluated by Neovim for the current buffer.
---@param lnum integer
---@return string
function FileDiff.foldexpr(lnum)
	local diff = active[vim.api.nvim_get_current_buf()]
	return diff and diff:fold_level(lnum) or "0"
end

---@param bufnr integer
---@return integer? source the buffer `bufnr` shows a diff of, when it is a view
function FileDiff.source_of(bufnr)
	local diff = active[bufnr]
	return diff and diff.source
end

---@param bufnr integer
function FileDiff.detach(bufnr)
	active[bufnr] = nil

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		restore_window(winid)
	end
end

function FileDiff.clear()
	for bufnr in pairs(active) do
		FileDiff.detach(bufnr)
	end
	for winid in pairs(win_opts) do
		restore_window(winid)
	end
end

---@param plugin_config Config
function FileDiff.setup(plugin_config)
	config = plugin_config

	local augroup = vim.api.nvim_create_augroup("diff-magik.file-diff", { clear = true })

	define_hl()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = define_hl,
		desc = "DiffMagik: re-copy the diff colors the in-file diff draws with",
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufReadPost" }, {
		group = augroup,
		callback = function(args)
			for _, diff in ipairs(diffs_of(args.buf)) do
				diff:render()
			end
		end,
		desc = "DiffMagik: keep the in-file diff in sync with the file",
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		callback = function(args)
			FileDiff.detach(args.buf)
		end,
		desc = "DiffMagik: drop the in-file diff of a closed buffer",
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			win_opts[tonumber(args.match)] = nil
		end,
		desc = "DiffMagik: forget the fold options of a closed window",
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function(args)
			local bufnr = args.buf
			vim.schedule(function()
				local diff = active[bufnr]
				if diff then
					diff:refold_windows()
				end
			end)
		end,
		desc = "DiffMagik: keep the hunk folds an attaching LSP would take over",
	})
end

---Shows an inline diff of `bufnr` against its base version in the current window.
---@param repo Git
---@param rel string
---@param bufnr integer
---@return integer view
---@return string? err
function FileDiff.attach(repo, rel, bufnr)
	local base, err = repo:base_lines(rel)
	if err ~= nil then
		return util.fail(err)
	end

	local existing = diffs_of(bufnr)[1]
	local view = existing and existing.view
	if not view then
		view = util.scratch_buf(("diffmagik://%s@%s:inline"):format(rel, base.label))
		vim.bo[view].filetype = vim.bo[bufnr].filetype
		BufferOrigin.new(repo.root, rel):tag(view)
	end

	local diff = FileDiff.new(view, bufnr, base.lines, config)
	active[view] = diff

	vim.api.nvim_win_set_buf(0, view)

	diff:render()
	diff:fold_windows(true)

	return view, nil
end

return FileDiff
