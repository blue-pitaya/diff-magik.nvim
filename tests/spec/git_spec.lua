local h = require("helpers")
local Git = require("diff-magik.git")

local test = h.test

---@param repo Git
local function entries_by_path(repo)
	local entries = repo:get_changed_files()
	table.sort(entries, function(a, b)
		return a.path < b.path
	end)
	return entries
end

test("Git.new resolves the top level from a subdirectory", function()
	local root = h.repo({ ["sub/a.txt"] = { "a" } })

	h.eq(root, Git.new(vim.fs.joinpath(root, "sub")).root)
end)

test("Git.new resolves the top level from a directory that no longer exists", function()
	local root = h.repo({ ["a.txt"] = { "a" } })

	h.eq(root, Git.new(vim.fs.joinpath(root, "gone", "deeper")).root)
end)

test("get_changed_files reports the status and staging of each file", function()
	local root = h.repo({
		["modified.txt"] = { "one" },
		["deleted.txt"] = { "gone" },
		["staged.txt"] = { "s" },
	})
	h.write(root .. "/modified.txt", { "two" })
	os.remove(root .. "/deleted.txt")
	h.write(root .. "/staged.txt", { "s2" })
	h.git(root, { "add", "staged.txt" })
	h.write(root .. "/new.txt", { "new" })

	h.eq({
		{ path = "deleted.txt", status = "D", staged = false, unstaged = true },
		{ path = "modified.txt", status = "M", staged = false, unstaged = true },
		{ path = "new.txt", status = "A", staged = false, unstaged = true },
		{ path = "staged.txt", status = "M", staged = true, unstaged = false },
	}, entries_by_path(Git.from_root(root)))
end)

test("get_changed_files keeps spaces in paths", function()
	local root = h.repo({ ["dir with space/a b.txt"] = { "one" } })
	h.write(root .. "/dir with space/a b.txt", { "two" })

	h.eq(
		{ { path = "dir with space/a b.txt", status = "M", staged = false, unstaged = true } },
		entries_by_path(Git.from_root(root))
	)
end)

test("get_changed_files reports a staged rename as a deletion and an addition", function()
	local root = h.repo({ ["a.txt"] = { "same" } })
	h.git(root, { "mv", "a.txt", "b.txt" })

	h.eq({
		{ path = "a.txt", status = "D", staged = true, unstaged = false },
		{ path = "b.txt", status = "A", staged = true, unstaged = false },
	}, entries_by_path(Git.from_root(root)))
end)

test("get_changed_files limits the scan to the pathspec", function()
	local root = h.repo({ ["a.txt"] = { "a" }, ["b.txt"] = { "b" } })
	h.write(root .. "/a.txt", { "a2" })
	h.write(root .. "/b.txt", { "b2" })

	h.eq(
		{ { path = "b.txt", status = "M", staged = false, unstaged = true } },
		Git.from_root(root):get_changed_files({ "b.txt" })
	)
end)

test("base_lines diffs a modified file against HEAD", function()
	local root = h.repo({ ["a.txt"] = { "one", "two" } })
	h.write(root .. "/a.txt", { "one", "three" })

	h.eq({ lines = { "one", "two" }, label = "HEAD" }, Git.from_root(root):base_lines("a.txt"))
end)

test("base_lines diffs an untracked file against an empty base", function()
	local root = h.repo({ ["a.txt"] = { "a" } })
	h.write(root .. "/new.txt", { "new" })

	h.eq({ lines = {}, label = "HEAD" }, Git.from_root(root):base_lines("new.txt"))
end)

test("base_lines diffs a staged then reverted file against the index", function()
	local root = h.repo({ ["a.txt"] = { "one" } })
	h.write(root .. "/a.txt", { "two" })
	h.git(root, { "add", "a.txt" })
	h.write(root .. "/a.txt", { "one" })

	h.eq({ lines = { "two" }, label = "INDEX" }, Git.from_root(root):base_lines("a.txt"))
end)

test("base_lines diffs a deleted file against HEAD", function()
	local root = h.repo({ ["a.txt"] = { "one" } })
	os.remove(root .. "/a.txt")

	h.eq({ lines = { "one" }, label = "HEAD" }, Git.from_root(root):base_lines("a.txt"))
end)

test("base is the empty tree in a repository without commits", function()
	local root = h.repo()

	h.eq("4b825dc642cb6eb9a060e54bf8d69288fbee4904", Git.from_root(root):base())
end)

test("base_lines diffs a new file against an empty base in a repository without commits", function()
	local root = h.repo()
	h.write(root .. "/new.txt", { "new" })

	h.eq({ lines = {}, label = "HEAD" }, Git.from_root(root):base_lines("new.txt"))
end)

test("toggle_stage stages a modified file and unstages it again", function()
	local root = h.repo({ ["a.txt"] = { "one" } })
	h.write(root .. "/a.txt", { "two" })
	local repo = Git.from_root(root)

	h.eq(true, repo:toggle_stage("a.txt"))
	h.eq({ { path = "a.txt", status = "M", staged = true, unstaged = false } }, entries_by_path(repo))

	h.eq(true, repo:toggle_stage("a.txt"))
	h.eq({ { path = "a.txt", status = "M", staged = false, unstaged = true } }, entries_by_path(repo))
end)

test("toggle_stage stages a new file and unstages it again in a repository without commits", function()
	local root = h.repo()
	h.write(root .. "/new.txt", { "new" })
	local repo = Git.from_root(root)

	h.eq(true, repo:toggle_stage("new.txt"))
	h.eq({ { path = "new.txt", status = "A", staged = true, unstaged = false } }, entries_by_path(repo))

	h.eq(true, repo:toggle_stage("new.txt"))
	h.eq({ { path = "new.txt", status = "A", staged = false, unstaged = true } }, entries_by_path(repo))
end)

test("reset restores a modified file to its HEAD content", function()
	local root = h.repo({ ["a.txt"] = { "one" } })
	h.write(root .. "/a.txt", { "two" })

	h.eq(true, Git.from_root(root):reset("a.txt"))
	h.eq({ "one" }, h.read(root .. "/a.txt"))
end)

test("reset restores a staged file to its HEAD content", function()
	local root = h.repo({ ["a.txt"] = { "one" } })
	h.write(root .. "/a.txt", { "two" })
	h.git(root, { "add", "a.txt" })

	h.eq(true, Git.from_root(root):reset("a.txt"))
	h.eq({ "one" }, h.read(root .. "/a.txt"))
end)
