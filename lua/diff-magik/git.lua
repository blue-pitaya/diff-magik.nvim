---@class Git
---@field root string absolute path to the git repo's top level
local Git = {}
Git.__index = Git

---@param args string[]
local function run(args)
	local cmd = { "git" }
	vim.list_extend(cmd, args)
	local result = vim.system(cmd, { text = true }):wait()
	if result.code ~= 0 then
		return nil
	end
	return vim.split(result.stdout, "\n", { trimempty = true })
end

---@param dir string
function Git.new(dir)
	local out = run({ "-C", dir, "rev-parse", "--show-toplevel" })
	local root = out and out[1] or nil
	if not root then
		return nil
	end
	return setmetatable({ root = root }, Git)
end

---@param rel string path to the file, relative to `self.root`
function Git:is_tracked(rel)
	return run({ "-C", self.root, "ls-files", "--error-unmatch", "--", rel }) ~= nil
end

---@param rel string
function Git:diff_name_only(rel)
	return run({ "-C", self.root, "diff", "--name-only", "HEAD", "--", rel })
end

---@param rel string
function Git:head_lines(rel)
	return run({ "-C", self.root, "show", ("HEAD:%s"):format(rel) })
end

---@param line string
---@return { status: string, path: string }
local function parse_name_status(line)
	local status, rest = line:match("^(%S+)\t(.*)$")
	status = status and status:sub(1, 1) or "?"

	if status == "R" or status == "C" then
		-- rename/copy lines are "STATUS\told\tnew"
		local _, new_path = rest:match("^(.*)\t(.*)$")
		return { status = status, path = new_path or rest }
	end

	return { status = status, path = rest }
end

---@return { status: string, path: string }[]|nil
function Git:get_changed_files()
	local tracked = run({ "-C", self.root, "diff", "--ignore-submodules", "--name-status", "HEAD" })
	if not tracked then
		return nil
	end

	local untracked = run({ "-C", self.root, "ls-files", "--others", "--exclude-standard" }) or {}

	local entries = {}
	for _, line in ipairs(tracked) do
		table.insert(entries, parse_name_status(line))
	end
	for _, path in ipairs(untracked) do
		table.insert(entries, { status = "?", path = path })
	end
	return entries
end

return Git
