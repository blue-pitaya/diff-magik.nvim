local h = require("helpers")
local Config = require("diff-magik.config")

local test = h.test

test("new overrides the given options and keeps the defaults of the rest", function()
	local config = Config.new({
		keys = { close = { "Q" } },
		highlights = { added = "MyAdded" },
		fold_context = 5,
	})

	h.eq({ "Q" }, config.keys.close)
	h.eq({ "<CR>", "o" }, config.keys.open)
	h.eq("MyAdded", config.highlights.added)
	h.eq("Changed", config.highlights.changed)
	h.eq(5, config.fold_context)
	h.eq("split", config.diff_style)
end)
