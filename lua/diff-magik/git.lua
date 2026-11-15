local CommandRunner = require("diff-magik.command-runner")
local util = require("diff-magik.util")

---@class Git
---@field root string
---@field has_head? boolean
---@field empty_tree? string
local Git = {}
Git.__index = Git

local EMPTY_TREE_SHA1 = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

---@param path string
---@return Git repo
---@return string? err
function Git.new(path)
	local repo_root_path = util.nearest_existing_parent_dir(path)
	if repo_root_path == nil then
		return util.fail(("no existing directory in '%s'"):format(path))
	end

	local lines, err = CommandRunner.run({ "git", "-C", repo_root_path, "rev-parse", "--show-toplevel" })
	if err ~= nil then
		return util.fail(err)
	end
	return Git.from_root(lines[1]), nil
end

---@param root string
---@return Git
function Git.from_root(root)
	return setmetatable({ root = root }, Git)
end

---@return string
function Git:base()
	if self.has_head == nil then
		self.has_head = CommandRunner.run({ "git", "-C", self.root, "rev-parse", "--verify", "--quiet", "HEAD" }) ~= nil
	end
	if self.has_head then
		return "HEAD"
	end

	if not self.empty_tree then
		local lines, err = CommandRunner.run(
			{ "git", "-C", self.root, "hash-object", "-t", "tree", "--stdin" },
			{ stdin = "" }
		)
		self.empty_tree = err == nil and lines[1] or EMPTY_TREE_SHA1
	end
	return self.empty_tree
end

---@param rel string
---@return GitEntry? entry nil when the file has no changes
---@return string? err
function Git:entry(rel)
	local entries, err = self:get_changed_files({ rel })
	if err ~= nil then
		return util.fail(err)
	end
	return entries[1], nil
end

---@param rel string
---@return boolean matches true when the working tree file equals the base version
---@return string? err
function Git:matches_base(rel)
	local lines, err = CommandRunner.run({ "git", "-C", self.root, "diff", "--name-only", self:base(), "--", rel })
	if err ~= nil then
		return util.fail(err)
	end
	return #lines == 0, nil
end

---@param rel string
---@return boolean ok
---@return string? err
function Git:stage(rel)
	local _, err = CommandRunner.run({ "git", "-C", self.root, "add", "--", rel })
	if err ~= nil then
		return util.fail(err)
	end
	return true, nil
end

---@param rel string
---@return boolean ok
---@return string? err
function Git:unstage(rel)
	local _, err
	if self:base() ~= "HEAD" then
		_, err = CommandRunner.run({ "git", "-C", self.root, "rm", "--cached", "--quiet", "--force", "--", rel })
	else
		_, err = CommandRunner.run({ "git", "-C", self.root, "restore", "--staged", "--", rel })
	end
	if err ~= nil then
		return util.fail(err)
	end
	return true, nil
end

---@param rel string
---@return boolean ok
---@return string? err
function Git:toggle_stage(rel)
	local entry, err = self:entry(rel)
	if err ~= nil then
		return util.fail(err)
	end
	if entry and entry.staged and not entry.unstaged then
		return self:unstage(rel)
	end
	return self:stage(rel)
end

---@param rel string
---@return boolean ok
---@return string? err
function Git:reset(rel)
	local entry, err = self:entry(rel)
	if err ~= nil then
		return util.fail(err)
	end
	if not entry then
		return util.fail(("no changes in '%s'"):format(rel))
	end

	local _
	if entry.status ~= "A" then
		_, err = CommandRunner.run({ "git", "-C", self.root, "checkout", self:base(), "--", rel })
		if err ~= nil then
			return util.fail(err)
		end
		return true, nil
	end

	if entry.staged then
		_, err = self:unstage(rel)
		if err ~= nil then
			return util.fail(err)
		end
	end

	local path = vim.fs.joinpath(self.root, rel)
	if not vim.uv.fs_stat(path) then
		return true, nil
	end
	_, err = vim.uv.fs_unlink(path)
	if err ~= nil then
		return util.fail(err)
	end
	return true, nil
end

---@param rel string
---@return string[] lines
---@return string? err
function Git:head_lines(rel)
	return CommandRunner.run({ "git", "-C", self.root, "show", ("%s:%s"):format(self:base(), rel) })
end

---@param rel string
---@return string[] lines
---@return string? err
function Git:index_lines(rel)
	return CommandRunner.run({ "git", "-C", self.root, "show", (":%s"):format(rel) })
end

---@class GitBase
---@field lines string[] contents of the version the file is diffed against
---@field label "HEAD"|"INDEX" which version the lines come from

---@param rel string
---@return GitBase base
---@return string? err
function Git:base_lines(rel)
	local entry, err = self:entry(rel)
	if err ~= nil then
		return util.fail(err)
	end
	if not entry then
		return util.fail(("no changes in '%s'"):format(rel))
	end

	local lines
	if entry.staged and entry.unstaged then
		local matches
		matches, err = self:matches_base(rel)
		if err ~= nil then
			return util.fail(err)
		end
		if matches then
			lines, err = self:index_lines(rel)
			if err ~= nil then
				return util.fail(err)
			end
			return { lines = lines, label = "INDEX" }, nil
		end
	end

	if entry.status == "A" then
		return { lines = {}, label = "HEAD" }, nil
	end

	lines, err = self:head_lines(rel)
	if err ~= nil then
		return util.fail(err)
	end
	return { lines = lines, label = "HEAD" }, nil
end

---@class GitEntry
---@field status string
---@field path string
---@field staged boolean
---@field unstaged boolean

---@param x string
---@param y string
---@return string
local function entry_status(x, y)
	if x == "?" then
		return "A"
	end
	if x ~= " " then
		return x
	end
	return y
end

---@param pathspec? string[]
---@return GitEntry[] entries
---@return string? err
function Git:get_changed_files(pathspec)
	local args = {
		"git",
		"-C",
		self.root,
		"status",
		"--porcelain",
		"-z",
		"--untracked-files=all",
		"--no-renames",
		"--ignore-submodules",
	}
	if pathspec then
		table.insert(args, "--")
		vim.list_extend(args, pathspec)
	end

	local records, err = CommandRunner.run(args, { sep = "\0" })
	if err ~= nil then
		return util.fail(err)
	end

	---@type GitEntry[]
	local entries = {}
	for _, record in ipairs(records) do
		local x, y, path = record:sub(1, 1), record:sub(2, 2), record:sub(4)
		if path ~= "" then
			table.insert(entries, {
				status = entry_status(x, y),
				path = path,
				staged = x ~= " " and x ~= "?",
				unstaged = y ~= " ",
			})
		end
	end
	return entries, nil
end

return Git
