local wezterm = require("wezterm")

local M = {}

function M.setup(config)
	config.font = wezterm.font_with_fallback({
		"Dank Mono",
		"Fira Code",
		"Jetbrains Mono",
	})
	config.font_size = 14.0
	config.line_height = 1.1
	config.adjust_window_size_when_changing_font_size = false
	config.window_frame = {
		font = wezterm.font({ family = "Dank Mono", weight = "Regular" }),
		font_size = 14.0,
	}
end

return M
