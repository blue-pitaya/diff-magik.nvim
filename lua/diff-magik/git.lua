local CommandRunner = require("diff-magik.command-runner")
local util = require("diff-magik.util")

---@class Git
---@field root string
---@field git CommandRunner runs git in root
---@field has_head? boolean
---@field empty_tree? string
local Git = {}
Git.__index = Git

local EMPTY_TREE_SHA1 = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

---@param path string
---@param config Config
---@return Git repo
---@return string? err
function Git.new(path, config)
	local repo_root_path = util.nearest_existing_parent_dir(path)
	if repo_root_path == nil then
		return util.fail(("no existing directory in '%s'"):format(path))
	end

	local git = CommandRunner.new({ "git", "-C", repo_root_path }, config)
	local lines, err = git:run({ "rev-parse", "--show-toplevel" })
	if err ~= nil then
		return util.fail(err)
	end
	return Git.from_root(lines[1], config), nil
end

---@param root string
---@param config Config
---@return Git
function Git.from_root(root, config)
	return setmetatable({ root = root, git = CommandRunner.new({ "git", "-C", root }, config) }, Git)
end

---@return string
function Git:base()
	if self.has_head == nil then
		local _, err = self.git:run({ "rev-parse", "--verify", "--quiet", "HEAD" })
		self.has_head = err == nil
	end
	if self.has_head then
		return "HEAD"
	end

	if not self.empty_tree then
		local lines, err = self.git:run({ "hash-object", "-t", "tree", "--stdin" }, { stdin = "" })
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
	local lines, err = self.git:run({ "diff", "--name-only", self:base(), "--", rel })
	if err ~= nil then
		return util.fail(err)
	end
	return #lines == 0, nil
end

---@param rel string
---@return boolean ok
---@return string? err
function Git:stage(rel)
	local _, err = self.git:run({ "add", "--", rel })
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
		_, err = self.git:run({ "rm", "--cached", "--quiet", "--force", "--", rel })
	else
		_, err = self.git:run({ "restore", "--staged", "--", rel })
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
		_, err = self.git:run({ "checkout", self:base(), "--", rel })
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
	return self.git:run({ "show", ("%s:%s"):format(self:base(), rel) })
end

---@param rel string
---@return string[] lines
---@return string? err
function Git:index_lines(rel)
	return self.git:run({ "show", (":%s"):format(rel) })
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

	local records, err = self.git:run(args, { sep = "\0" })
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
