extends SceneTree
## Seven modular sprites per generated atlas. Re-running preserves projectile metadata.

const ROOT := "res://assets/custom_towers/"
const KINDS := ["arrow", "cannon", "ember", "frost", "sniper", "poison", "flak", "tesla", "net", "beacon"]

func _initialize() -> void:
	var file := FileAccess.open(ROOT + "custom_towers.json", FileAccess.READ)
	var metadata: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	for kind in KINDS:
		var atlas := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "source/tiers/" + kind + ".png"))
		if atlas == null:
			quit(1)
			return
		var levels: Array = metadata["towers"][kind]["levels"]
		for tier in 3:
			var source := clean(cell(atlas, tier, 0))
			var height: int = [80, 96, 112][tier]
			var body_height: int = [40, 58, 76][tier]
			var body_width: int = [54, 58, 60][tier]
			source.resize(body_width, body_height, Image.INTERPOLATE_NEAREST)
			var base := Image.create(64, height, false, Image.FORMAT_RGBA8)
			base.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i((64 - body_width) / 2, height - body_height))
			var path: String = ROOT + kind + "_base_%d.png" % (tier + 1)
			base.save_png(ProjectSettings.globalize_path(path))
			levels[tier]["base"] = path
			levels[tier]["base_size"] = [64, height]
			levels[tier]["ground"] = height
			levels[tier]["mount"] = height - body_height + roundi(body_height * [0.19, 0.18, 0.25][tier])
			levels[tier]["pixel_scale"] = 64
		for variant in 4:
			var source := clean(cell(atlas, variant, 1))
			# Place the physical bearing (near the bottom of each painted head) at 48,48.
			var pivot_y := 0.91
			if kind == "poison" and variant == 3:
				pivot_y = 0.95
			var reach: float = [36.0, 42.0, 48.0, 48.0][variant]
			var max_width: float = [58.0, 68.0, 88.0, 78.0][variant]
			var scale := minf(max_width / source.get_width(), reach / (source.get_height() * pivot_y))
			var width := maxi(1, roundi(source.get_width() * scale))
			var height := maxi(1, roundi(source.get_height() * scale))
			source.resize(width, height, Image.INTERPOLATE_NEAREST)
			var weapon := Image.create(96, 96, false, Image.FORMAT_RGBA8)
			weapon.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(48 - width / 2, 48 - roundi(height * pivot_y)))
			var suffix: String = ["1", "2", "3a", "3b"][variant]
			var path: String = ROOT + kind + "_weapon_" + suffix + ".png"
			weapon.save_png(ProjectSettings.globalize_path(path))
			var data := {"file": path, "frame": 96, "frame_h": 96, "frames": 1, "cols": 1, "idle": 1, "forward_degrees": -90}
			if variant < 2:
				levels[variant]["weapon"] = data
			else:
				if variant == 2:
					levels[2]["weapon"] = data.duplicate(true)
					levels[2]["branches"] = {}
				levels[2]["branches"]["a" if variant == 2 else "b"] = {"weapon": data}
		print("Prepared distinct tiers and branches: ", kind)
	file = FileAccess.open(ROOT + "custom_towers.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata, "  ") + "\n")
	quit()

func cell(sheet: Image, column: int, row: int) -> Image:
	var x0 := roundi(float(column) * sheet.get_width() / 4.0)
	var y0 := roundi(float(row) * sheet.get_height() / 2.0)
	var x1 := roundi(float(column + 1) * sheet.get_width() / 4.0)
	var y1 := roundi(float(row + 1) * sheet.get_height() / 2.0)
	return sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))

func clean(source: Image) -> Image:
	source.resize(192, 192, Image.INTERPOLATE_NEAREST)
	var visited := PackedByteArray()
	visited.resize(192 * 192)
	for y in 192:
		for x in 192:
			var color := source.get_pixel(x, y)
			source.set_pixel(x, y, Color.TRANSPARENT if color.a < 0.68 else Color(color.r, color.g, color.b, 1))
	var largest: Array[Vector2i] = []
	for y in 192:
		for x in 192:
			if visited[y * 192 + x] != 0 or source.get_pixel(x, y).a == 0:
				continue
			var component: Array[Vector2i] = [Vector2i(x, y)]
			visited[y * 192 + x] = 1
			var cursor := 0
			while cursor < component.size():
				var p: Vector2i = component[cursor]
				cursor += 1
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n := p + Vector2i(dx, dy)
						if n.x >= 0 and n.y >= 0 and n.x < 192 and n.y < 192 and visited[n.y * 192 + n.x] == 0 and source.get_pixelv(n).a > 0:
							visited[n.y * 192 + n.x] = 1
							component.append(n)
			if component.size() > largest.size():
				largest = component
	var result := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	for p in largest:
		result.set_pixelv(p, source.get_pixelv(p))
	return result.get_region(result.get_used_rect())
