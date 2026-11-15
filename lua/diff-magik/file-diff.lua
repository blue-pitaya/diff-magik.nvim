local config = require("diff-magik.config")
local util = require("diff-magik.util")
local BufferOrigin = require("diff-magik.buffer-origin")

local ns = vim.api.nvim_create_namespace("diff-magik.file-diff")

local COPIED_HL = {
	DiffMagikFileAdded = "DiffAdd",
	DiffMagikFileDeleted = "DiffDelete",
}

local function define_hl()
	for name, source in pairs(COPIED_HL) do
		local hl = vim.api.nvim_get_hl(0, { name = source, link = false }) --[[@as vim.api.keyset.highlight]]
		vim.api.nvim_set_hl(0, name, hl)
	end
end

local FOLD_OPTS = {
	foldmethod = "expr",
	foldexpr = "v:lua.require'diff-magik.file-diff'.foldexpr(v:lnum)",
	foldenable = true,
	foldlevel = 0,
}

local FOLD_OPT_NAMES = vim.tbl_keys(FOLD_OPTS)

---@class FileDiffState
---@field source integer
---@field base string
---@field base_lines string[]
---@field keep? table<integer, boolean>

---@class FileDiffModuleState
---@field active table<integer, FileDiffState>
---@field win_opts table<integer, table<string, any>>
local state = {
	active = {},
	win_opts = {},
}

local M = {}

---@param lnum integer
---@return string
function M.foldexpr(lnum)
	local diff = state.active[vim.api.nvim_get_current_buf()]
	local keep = diff and diff.keep
	if not keep or keep[lnum] then
		return "0"
	end
	return "1"
end

---@param lines string[]
local function as_text(lines)
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

---@param ranges integer[][]
---@param total integer
---@return table<integer, boolean>?
local function unfolded_lines(ranges, total)
	if #ranges == 0 then
		return nil
	end

	local context = config.options.fold_context
	local keep = {}

	for _, range in ipairs(ranges) do
		for lnum = math.max(range[1] - context, 1), math.min(range[2] + context, total) do
			keep[lnum] = true
		end
	end

	return keep
end

---@param bufnr integer
---@param force boolean
local function fold_windows(bufnr, force)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		if not state.win_opts[winid] then
			state.win_opts[winid] = util.save_wo(winid, FOLD_OPT_NAMES)
			util.set_wo(winid, FOLD_OPTS)
		elseif force then
			vim.api.nvim_win_call(winid, function()
				vim.cmd("normal! zX")
			end)
		end
	end
end

---@param bufnr integer
local function refold_windows(bufnr)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		if state.win_opts[winid] and vim.api.nvim_win_is_valid(winid) then
			if vim.wo[winid].foldmethod ~= FOLD_OPTS.foldmethod or vim.wo[winid].foldexpr ~= FOLD_OPTS.foldexpr then
				util.set_wo(winid, { foldmethod = FOLD_OPTS.foldmethod, foldexpr = FOLD_OPTS.foldexpr })
			end
		end
	end
end

---@param winid integer
local function restore_window(winid)
	local saved = state.win_opts[winid]
	if saved and vim.api.nvim_win_is_valid(winid) then
		util.set_wo(winid, saved)
	end
	state.win_opts[winid] = nil
end

---@param source integer
---@return integer[]
local function views_of(source)
	local views = {}
	for view, diff in pairs(state.active) do
		if diff.source == source then
			table.insert(views, view)
		end
	end
	return views
end

---@param view integer
local function render(view)
	local diff = state.active[view]
	if not diff or not vim.api.nvim_buf_is_valid(view) or not vim.api.nvim_buf_is_valid(diff.source) then
		return
	end

	if not vim.api.nvim_buf_is_loaded(diff.source) then
		vim.fn.bufload(diff.source)
	end

	local current = vim.api.nvim_buf_get_lines(diff.source, 0, -1, false)
	local hunks = vim.text.diff(diff.base, as_text(current), { result_type = "indices" }) --[[@as integer[][] ]]

	local hl = config.options.highlights
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
			table.insert(lines, diff.base_lines[start_a + i] or "")
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

	diff.keep = unfolded_lines(ranges, #lines)

	vim.bo[view].modifiable = true
	vim.api.nvim_buf_set_lines(view, 0, -1, false, lines)
	vim.bo[view].modifiable = false

	vim.api.nvim_buf_clear_namespace(view, ns, 0, -1)
	for lnum, group in pairs(groups) do
		vim.api.nvim_buf_set_extmark(view, ns, lnum - 1, 0, {
			line_hl_group = group,
		})
	end

	fold_windows(view, false)
end

---@param bufnr integer
---@return integer?
function M.source(bufnr)
	local diff = state.active[bufnr]
	return diff and diff.source
end

---@param bufnr integer
function M.detach(bufnr)
	state.active[bufnr] = nil

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		restore_window(winid)
	end
end

function M.clear()
	for bufnr in pairs(state.active) do
		M.detach(bufnr)
	end
	for winid in pairs(state.win_opts) do
		restore_window(winid)
	end
end

function M.setup()
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
			for _, view in ipairs(views_of(args.buf)) do
				render(view)
			end
		end,
		desc = "DiffMagik: keep the in-file diff in sync with the file",
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		callback = function(args)
			M.detach(args.buf)
		end,
		desc = "DiffMagik: drop the in-file diff of a closed buffer",
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			state.win_opts[tonumber(args.match)] = nil
		end,
		desc = "DiffMagik: forget the fold options of a closed window",
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function(args)
			local bufnr = args.buf
			vim.schedule(function()
				if state.active[bufnr] then
					refold_windows(bufnr)
				end
			end)
		end,
		desc = "DiffMagik: keep the hunk folds an attaching LSP would take over",
	})
end

---@param repo Git
---@param rel string
---@param bufnr integer
---@return integer?
function M.attach(repo, rel, bufnr)
	local base, err = repo:base_lines(rel)
	if err ~= nil then
		util.error(err)
		return nil
	end
	local base_lines = base.lines

	local view = views_of(bufnr)[1]
	if not view then
		view = util.scratch_buf(("diffmagik://%s@%s:inline"):format(rel, base.label))
		vim.bo[view].filetype = vim.bo[bufnr].filetype
		BufferOrigin.new(repo.root, rel):tag(view)
	end

	state.active[view] = {
		source = bufnr,
		base = as_text(base_lines),
		base_lines = base_lines,
	}

	vim.api.nvim_win_set_buf(0, view)

	render(view)
	fold_windows(view, true)

	return view
end

return M
