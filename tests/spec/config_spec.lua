local h = require("helpers")
local config = require("diff-magik.config")

local test = h.test

test("setup overrides the given options and keeps the defaults of the rest", function()
	config.setup({
		keys = { close = { "Q" } },
		highlights = { added = "MyAdded" },
		width_mode = "constant",
	})

	h.eq({ "Q" }, config.options.keys.close)
	h.eq({ "<CR>", "o" }, config.options.keys.open)
	h.eq("MyAdded", config.options.highlights.added)
	h.eq("Changed", config.options.highlights.changed)
	h.eq("constant", config.options.width_mode)
	h.eq("split", config.options.diff_style)
end)
