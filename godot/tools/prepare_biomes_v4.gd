extends SceneTree
## Deterministic sprite slicing and native-size import of the generated v4 atlases.
const ROOT := "res://assets/biomes/"
const IDS := ["forest", "autumn", "winter", "swamp", "volcanic", "dungeon"]
const PROP_KINDS := ["oak", "pine", "bush", "rock1", "rock2", "crystal"]

func _initialize() -> void:
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "biomes.json"))
	var roads := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "source/roads-v4.png"))
	if roads == null:
		quit(1)
		return
	for biome in IDS:
		var atlas := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "source/" + biome + "-v4.png"))
		if atlas == null:
			quit(1)
			return
		var variants: Array = []
		var reference: Image
		for col in 4:
			var surface := cell(atlas, col, 0)
			if col == 3:
				var road_index := IDS.find(biome)
				var w := roads.get_width() / 3
				var h := roads.get_height() / 2
				surface = roads.get_region(Rect2i((road_index % 3) * w, (road_index / 3) * h, w, h))
			var inset := maxi(4, roundi(surface.get_width() * 0.025))
			surface = surface.get_region(Rect2i(inset, inset, surface.get_width() - inset * 2, surface.get_height() - inset * 2))
			surface.resize(256, 256, Image.INTERPOLATE_NEAREST)
			var average := Color(0, 0, 0, 1)
			for sample_y in range(0, 256, 8):
				for sample_x in range(0, 256, 8):
					var sample := surface.get_pixel(sample_x, sample_y)
					average.r += sample.r / 1024.0
					average.g += sample.g / 1024.0
					average.b += sample.b / 1024.0
			for y in 256:
				for x in 256:
					var color := surface.get_pixel(x, y)
					color.a = 1.0
					if col < 3: color = color.lerp(average, 0.25)
					if col == 3:
						color = color.lerp(average, 0.10)
					surface.set_pixel(x, y, color)
			seamless(surface)
			if col == 0:
				reference = surface.duplicate()
			elif col < 3:
				# Every ground variant shares the same boundary for mixed patch tiling.
				for y in 256:
					for x in 256:
						var edge := mini(mini(x, 255 - x), mini(y, 255 - y))
						if edge < 16:
							surface.set_pixel(x, y, reference.get_pixel(x, y) if edge == 0 else surface.get_pixel(x, y).lerp(reference.get_pixel(x, y), 1.0 - float(edge) / 16.0))
			var path: String = ROOT + ("road_surface_" if col == 3 else "ground_") + biome + ("" if col == 0 or col == 3 else "_%d" % (col + 1)) + ".png"
			surface.save_png(ProjectSettings.globalize_path(path))
			if col < 3: variants.append(path)
		var props: Dictionary = {}
		for index in PROP_KINDS.size():
			var source := clean(cell(atlas, index % 4, 1 + index / 4), biome == "winter")
			var large := index < 2
			var canvas_size := 128 if large else 64
			var fit := Vector2(114, 122) if large else Vector2(46, 44)
			var factor := minf(fit.x / source.get_width(), fit.y / source.get_height())
			source.resize(maxi(1, roundi(source.get_width() * factor)), maxi(1, roundi(source.get_height() * factor)), Image.INTERPOLATE_NEAREST)
			var canvas := Image.create(canvas_size, canvas_size, false, Image.FORMAT_RGBA8)
			canvas.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i((canvas_size - source.get_width()) / 2, canvas_size - 2 - source.get_height()))
			var kind: String = PROP_KINDS[index]
			var path: String = ROOT + "props/" + biome + "_" + kind + "_v4.png"
			canvas.save_png(ProjectSettings.globalize_path(path))
			props[kind] = path
		metadata["biomes"][biome]["ground_variants"] = variants
		metadata["biomes"][biome]["props"] = props
		metadata["biomes"][biome]["pixel_scale"] = 64
		print("Prepared biome: ", biome)
	var output := FileAccess.open(ROOT + "biomes.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(metadata, "\t") + "\n")
	quit()

func cell(atlas: Image, col: int, row: int) -> Image:
	var x := roundi(col * atlas.get_width() / 4.0)
	var y := roundi(row * atlas.get_height() / 3.0)
	return atlas.get_region(Rect2i(x, y, roundi((col + 1) * atlas.get_width() / 4.0) - x, roundi((row + 1) * atlas.get_height() / 3.0) - y))

func seamless(image: Image) -> void:
	for i in 16:
		var weight := 0.5 * (1.0 - float(i) / 16.0)
		for y in 256:
			var left := image.get_pixel(i, y)
			var right := image.get_pixel(255 - i, y)
			image.set_pixel(i, y, left.lerp(right, weight))
			image.set_pixel(255 - i, y, right.lerp(left, weight))
		for x in 256:
			var top := image.get_pixel(x, i)
			var bottom := image.get_pixel(x, 255 - i)
			image.set_pixel(x, i, top.lerp(bottom, weight))
			image.set_pixel(x, 255 - i, bottom.lerp(top, weight))

	# Exact boundary equality also avoids one-byte rounding differences at the corners.
	for i in 256:
		image.set_pixel(255, i, image.get_pixel(0, i))
	for i in 256:
		image.set_pixel(i, 255, image.get_pixel(i, 0))

func clean(image: Image, snow: bool) -> Image:
	image.resize(192, 192, Image.INTERPOLATE_NEAREST)
	# Generated alpha is hardened; white matte is removed only when connected to the cell edge.
	var background: Array[Vector2i] = []
	var visited := PackedByteArray()
	visited.resize(192 * 192)
	for y in 192:
		for x in 192:
			var color := image.get_pixel(x, y)
			if color.a < 0.94 or (not snow and minf(color.r, minf(color.g, color.b)) > 0.87 and maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) < 0.08):
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)
			if x == 0 or x == 191 or y == 0 or y == 191:
				background.append(Vector2i(x, y))
	var cursor := 0
	while cursor < background.size():
		var p := background[cursor]
		cursor += 1
		if p.x < 0 or p.y < 0 or p.x >= 192 or p.y >= 192 or visited[p.y * 192 + p.x] != 0: continue
		visited[p.y * 192 + p.x] = 1
		var color := image.get_pixelv(p)
		if color.a != 0 and (minf(color.r, minf(color.g, color.b)) < 0.89 or maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) > 0.07): continue
		image.set_pixelv(p, Color.TRANSPARENT)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]: background.append(p + offset)
	visited.fill(0)
	var largest: Array[Vector2i] = []
	for y in 192:
		for x in 192:
			if visited[y * 192 + x] != 0 or image.get_pixel(x, y).a == 0: continue
			var component: Array[Vector2i] = [Vector2i(x, y)]
			visited[y * 192 + x] = 1
			cursor = 0
			while cursor < component.size():
				var p: Vector2i = component[cursor]
				cursor += 1
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n := p + Vector2i(dx, dy)
						if n.x >= 0 and n.y >= 0 and n.x < 192 and n.y < 192 and visited[n.y * 192 + n.x] == 0 and image.get_pixelv(n).a > 0:
							visited[n.y * 192 + n.x] = 1
							component.append(n)
			if component.size() > largest.size(): largest = component
	var result := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	for p in largest: result.set_pixelv(p, image.get_pixelv(p))
	return result.get_region(result.get_used_rect())
