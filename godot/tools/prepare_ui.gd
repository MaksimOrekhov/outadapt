extends SceneTree

func _initialize() -> void:
	var root := "res://assets/ui/"
	var frames := Image.load_from_file(ProjectSettings.globalize_path(root + "source/frames.png"))
	var icons := Image.load_from_file(ProjectSettings.globalize_path(root + "source/icons.png"))
	var names := ["frame", "inset", "button", "hover", "selected", "primary"]
	for i in names.size():
		var region := Rect2i(i % 3 * frames.get_width() / 3, i / 3 * frames.get_height() / 2, frames.get_width() / 3, frames.get_height() / 2)
		var image := frames.get_region(region)
		image.resize(96, 96, Image.INTERPOLATE_NEAREST)
		image.save_png(ProjectSettings.globalize_path(root + names[i] + ".png"))
	var icon_names := ["lives", "coin", "wave", "info", "pause", "play", "fast", "menu", "sell", "upgrade", "star", "lock", "target", "gene-wings", "speed", "help"]
	for i in icon_names.size():
		var region := Rect2i(i % 4 * icons.get_width() / 4, i / 4 * icons.get_height() / 4, icons.get_width() / 4, icons.get_height() / 4)
		var image := icons.get_region(region)
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a < 0.5:
					image.set_pixel(x, y, Color.TRANSPARENT)
		var used := image.get_used_rect()
		image = image.get_region(used)
		var scale := 44.0 / maxf(image.get_width(), image.get_height())
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_NEAREST)
		var canvas := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), (Vector2i(48, 48) - image.get_size()) / 2)
		canvas.save_png(ProjectSettings.globalize_path(root + "icon_" + icon_names[i] + ".png"))
	print("Prepared fantasy UI: 6 skins, 16 icons")
	quit()
