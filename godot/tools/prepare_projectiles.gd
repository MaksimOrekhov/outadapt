extends SceneTree

const ROOT := "res://assets/custom_towers/"

func _initialize() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "source/projectiles.png"))
	var meta_file := FileAccess.open(ROOT + "custom_towers.json", FileAccess.READ)
	var metadata: Dictionary = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	for i in 3:
		var kind: String = ["arrow", "flak", "sniper"][i]
		var source := cell(atlas, i, 0)
		source = source.get_region(Rect2i(0, int(source.get_height() * 0.4), source.get_width(), int(source.get_height() * 0.32)))
		threshold(source)
		# Projectile silhouettes are connected; discard stray atlas artifacts.
		# Find the opaque silhouette using a flood fill without altering its palette.
		keep_main(source)
		var used := source.get_used_rect()
		if used.size.x == 0:
			push_error("Empty projectile " + kind)
			quit(1)
			return
		source = source.get_region(used)
		var scale := 40.0 / source.get_width()
		source.resize(40, maxi(1, roundi(source.get_height() * scale)), Image.INTERPOLATE_NEAREST)
		var projectile := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		projectile.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), (Vector2i(48, 48) - source.get_size()) / 2)
		projectile.save_png(ProjectSettings.globalize_path(ROOT + kind + "_projectile.png"))
		var effects: Array[Image] = []
		var bounds := Rect2i()
		for phase in 3:
			var effect := cell(atlas, phase, i + 1)
			threshold(effect)
			effects.append(effect)
			bounds = effect.get_used_rect() if phase == 0 else bounds.merge(effect.get_used_rect())
		var impact := Image.create(144, 48, false, Image.FORMAT_RGBA8)
		var effect_scale := 36.0 / maxf(bounds.size.x, bounds.size.y)
		for phase in 3:
			var effect := effects[phase].get_region(bounds)
			effect.resize(maxi(1, roundi(bounds.size.x * effect_scale)), maxi(1, roundi(bounds.size.y * effect_scale)), Image.INTERPOLATE_NEAREST)
			impact.blit_rect(effect, Rect2i(Vector2i.ZERO, effect.get_size()), Vector2i(phase * 48, 0) + (Vector2i(48, 48) - effect.get_size()) / 2)
		impact.save_png(ProjectSettings.globalize_path(ROOT + kind + "_impact.png"))
		for level in metadata["towers"][kind]["levels"]:
			level["projectile"] = {"file": ROOT + kind + "_projectile.png", "frame": 48, "frames": 1, "cols": 1, "forward_degrees": 0, "display_size": 0.55, "custom": true}
			level["impact"] = {"file": ROOT + kind + "_impact.png", "frame": 48, "frames": 3, "cols": 3, "fps": 24, "display_size": 0.38}
	var output := FileAccess.open(ROOT + "custom_towers.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(metadata, "  ") + "\n")
	print("Prepared 3 physical projectiles and 3 animated impacts for all tower levels")
	quit()

func cell(atlas: Image, x: int, y: int) -> Image:
	var x0 := roundi(float(x) * atlas.get_width() / 3.0)
	var y0 := roundi(float(y) * atlas.get_height() / 4.0)
	return atlas.get_region(Rect2i(x0, y0, roundi(float(x + 1) * atlas.get_width() / 3.0) - x0, roundi(float(y + 1) * atlas.get_height() / 4.0) - y0))

func threshold(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			image.set_pixel(x, y, Color.TRANSPARENT if c.a < 0.65 else Color(c.r, c.g, c.b, 1.0))

func keep_main(image: Image) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var largest: Array[Vector2i] = []
	for y in h:
		for x in w:
			if visited[y * w + x] != 0 or image.get_pixel(x, y).a == 0:
				continue
			var component: Array[Vector2i] = [Vector2i(x, y)]
			visited[y * w + x] = 1
			var cursor := 0
			while cursor < component.size():
				var p: Vector2i = component[cursor]
				cursor += 1
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = p + offset
					if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and visited[n.y * w + n.x] == 0 and image.get_pixelv(n).a > 0:
						visited[n.y * w + n.x] = 1
						component.append(n)
			if component.size() > largest.size():
				largest = component
	var result := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for p in largest:
		result.set_pixelv(p, image.get_pixelv(p))
	image.copy_from(result)
