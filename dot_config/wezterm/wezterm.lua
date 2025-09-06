local wezterm = require("wezterm")
local fonts = require("fonts")
local keys = require("keys")
local bar = require("plugins.bar")
local theme = require("themes.melange_dark")
require("plugins.zen-mode-vim")

local config = wezterm.config_builder()

config.colors = theme
config.default_workspace = "~"

config.warn_about_missing_glyphs = true
config.enable_scroll_bar = false
config.window_padding = {
	left = "0.50cell",
	right = "0cell",
	top = "0cell",
	bottom = "0cell",
}
config.scrollback_lines = 3500
config.window_decorations = "RESIZE"
config.use_resize_increments = false

config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = false
config.tab_and_split_indices_are_zero_based = true

config.window_background_opacity = 0.95
config.macos_window_background_blur = 8
config.animation_fps = 60
config.window_close_confirmation = "NeverPrompt"
config.prefer_egl = true

config.initial_rows = 40
config.initial_cols = 150

config.command_palette_rows = 14
config.command_palette_bg_color = theme.selection_bg
config.command_palette_fg_color = theme.selection_fg
config.show_update_window = false

config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 800

config.enable_kitty_graphics = true
config.enable_tab_bar = false

fonts.setup(config)
keys.setup(config)
bar.setup(config)

return config
