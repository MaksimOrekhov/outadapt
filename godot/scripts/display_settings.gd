class_name TDDisplay
extends RefCounted

const PATH := "user://display.cfg"
static var config_path := PATH
static var values := {"resolution": Vector2i(1600, 900), "fullscreen": false, "vsync": true}

static func load_settings(window: Window) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) == OK:
		for key in values:
			values[key] = cfg.get_value("display", key, values[key])
	apply(window, values)

static func apply(window: Window, config: Dictionary) -> void:
	var screen := DisplayServer.screen_get_size(window.current_screen)
	var resolution: Vector2i = config.get("resolution", Vector2i(1600, 900))
	resolution = Vector2i(clampi(resolution.x, 960, maxi(960, screen.x)), clampi(resolution.y, 540, maxi(540, screen.y)))
	if config.get("fullscreen", false):
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.size = resolution
		window.position = DisplayServer.screen_get_position(window.current_screen) + (screen - resolution) / 2
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if config.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	values = {"resolution": resolution, "fullscreen": bool(config.get("fullscreen", false)), "vsync": bool(config.get("vsync", true))}

static func save() -> Error:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("display", key, values[key])
	return cfg.save(config_path)
