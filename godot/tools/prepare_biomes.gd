extends SceneTree
## Slice generated world atlases into game-ready tiles, props and keeps.

const ROOT := "res://assets/biomes"
const BIOMES := ["forest", "autumn", "winter", "swamp", "volcanic", "dungeon"]
const PROP_NAMES := [
	"forest_oak", "forest_fir", "autumn_maple", "autumn_birch", "winter_fir", "winter_crystal",
	"forest_stump", "forest_mushrooms", "autumn_stump", "autumn_mushrooms", "winter_boulder", "winter_shrine",
	"swamp_willow", "swamp_reeds", "volcanic_dead_tree", "volcanic_obsidian", "dungeon_pillar", "dungeon_brazier",
	"swamp_mushrooms", "swamp_stone", "volcanic_boulder", "volcanic_vent", "dungeon_geode", "dungeon_urn",
]
const ROAD_NAMES := ["road_h", "road_v", "corner_rd", "corner_ld", "corner_ru", "corner_lu"]
const ROAD_COLORS := {
	"forest": "#c99562", "autumn": "#d9b07a", "winter": "#a6c9df",
	"swamp": "#817962", "volcanic": "#5c4145", "dungeon": "#888298",
}
const CASTLE_NAMES := ["forest", "autumn", "winter", "swamp", "volcanic", "dungeon"]
const PROP_FORMS := {
	"forest": {"pine": "forest_fir", "oak": "forest_oak", "bush": "forest_mushrooms", "rock1": "forest_stump", "rock2": "forest_mushrooms", "crystal": "forest_mushrooms"},
	"autumn": {"pine": "autumn_birch", "oak": "autumn_maple", "bush": "autumn_mushrooms", "rock1": "autumn_stump", "rock2": "autumn_mushrooms", "crystal": "autumn_mushrooms"},
	"winter": {"pine": "winter_fir", "oak": "winter_fir", "bush": "winter_shrine", "rock1": "winter_boulder", "rock2": "winter_shrine", "crystal": "winter_crystal"},
	"swamp": {"pine": "swamp_willow", "oak": "swamp_willow", "bush": "swamp_reeds", "rock1": "swamp_stone", "rock2": "swamp_mushrooms", "crystal": "swamp_stone"},
	"volcanic": {"pine": "volcanic_dead_tree", "oak": "volcanic_obsidian", "bush": "volcanic_vent", "rock1": "volcanic_boulder", "rock2": "volcanic_obsidian", "crystal": "volcanic_vent"},
	"dungeon": {"pine": "dungeon_pillar", "oak": "dungeon_brazier", "bush": "dungeon_urn", "rock1": "dungeon_urn", "rock2": "dungeon_pillar", "crystal": "dungeon_geode"},
}


func _initialize() -> void:
	var ground_atlas := _load_atlas("ground-atlas-v3.png")
	var props_atlas := _load_atlas("props-atlas-v3.png")
	var castle_atlas := _load_atlas("castle-atlas-v3.png")
	var road_surface_atlas := _load_atlas("road-atlas-v3.png")
	_prepare_portal()
	if ground_atlas == null or props_atlas == null or castle_atlas == null:
		quit(1)
		return
	var roads := _prepare_road_overlays()
	if roads.is_empty():
		quit(1)
		return
	var metadata: Dictionary = {}
	for i in BIOMES.size():
		var biome: String = BIOMES[i]
		var surface := _cell(road_surface_atlas, i, 3, 2)
		surface.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		_make_seamless(surface, 20)
		_save(surface, ROOT + "/road_surface_" + biome + ".png")
		var ground := _cell(ground_atlas, i, 3, 2)
		var gw := ground.get_width()
		var gh := ground.get_height()
		ground = ground.get_region(Rect2i(gw / 4, gh / 4, gw / 2, gh / 2))
		ground.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		_make_seamless(ground, 20)
		if not _save(ground, ROOT + "/ground_" + biome + ".png"):
			quit(1)
			return
		var castle := _cell(castle_atlas, i, 3, 2)
		if not _save_sprite(castle, ROOT + "/castle_" + biome + ".png", 192, 0.08, 176, 180):
			quit(1)
			return
		var prop_paths: Dictionary = {}
		for kind in PROP_FORMS[biome]:
			var prop_name: String = PROP_FORMS[biome][kind]
			prop_paths[kind] = "res://assets/biomes/props/" + prop_name + ".png"
		metadata[biome] = {
			"road_surface": ROOT + "/road_surface_" + biome + ".png",
			"ground": "res://assets/biomes/ground_" + biome + ".png",
			"castle": "res://assets/biomes/castle_" + biome + ".png",
			"roads": roads[biome],
			"props": prop_paths,
		}
	for i in PROP_NAMES.size():
		var name: String = PROP_NAMES[i]
		var prop := _cell(props_atlas, i, 6, 4)
		if not _save_sprite(prop, ROOT + "/props/" + name + ".png", 128, 0.48, 116, 118):
			quit(1)
			return
	var file := FileAccess.open(ROOT + "/biomes.json", FileAccess.WRITE)
	if file == null:
		push_error("Could not write biome metadata")
		quit(1)
		return
	file.store_string(JSON.stringify({"biomes": metadata}, "\t") + "\n")
	file.close()
	print("Prepared 6 biome ground tiles, 24 props, and 6 keeps")
	quit(0)


func _load_atlas(file_name: String) -> Image:
	var path := ProjectSettings.globalize_path(ROOT + "/source/" + file_name)
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Could not load biome atlas: " + path)
		return null
	return image


func _prepare_portal() -> void:
	var atlas := _load_atlas("portal-v4.png")
	var frames: Array[Image] = []
	for i in 8:
		var frame := _cell(atlas, i, 4, 2)
		_threshold_alpha(frame, 0.45)
		_keep_main_sprite(frame)
		frame.resize(128, 128, Image.INTERPOLATE_NEAREST)
		frames.append(frame)
	var sheet := Image.create(1024, 128, false, Image.FORMAT_RGBA8)
	for i in 8:
		var frame: Image = frames[0].duplicate()
		# Lock the masonry to frame zero. Only the inset doorway animates.
		for y in 128:
			for x in 128:
				var d := Vector2((float(x) / 128.0 - 0.5) / 0.235, (float(y) / 128.0 - 0.55) / 0.30)
				if d.length() < 1.0:
					frame.set_pixel(x, y, frames[0].get_pixel(x, y).lerp(frames[i].get_pixel(x, y), clampf((1.0 - d.length()) * 12.0, 0.0, 1.0)))
		sheet.blit_rect(frame, Rect2i(0, 0, 128, 128), Vector2i(i * 128, 0))
	_save(sheet, ROOT + "/portal.png")


func _prepare_road_overlays() -> Dictionary:
	var road_atlas := _load_atlas("road-atlas-v3.png")
	if road_atlas == null:
		return {}
	var output_dir := ProjectSettings.globalize_path(ROOT + "/roads")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("Could not create biome road directory")
		return {}
	var sources: Dictionary = {}
	for road_name in ROAD_NAMES:
		var source_path := ProjectSettings.globalize_path("res://assets/spire/tiles/" + road_name + ".png")
		var source := Image.load_from_file(source_path)
		if source == null or source.is_empty():
			push_error("Could not load road tile: " + source_path)
			return {}
		source.convert(Image.FORMAT_RGBA8)
		sources[road_name] = source
	var all_paths: Dictionary = {}
	for biome_index in BIOMES.size():
		var biome: String = BIOMES[biome_index]
		var biome_paths: Dictionary = {}
		for road_name in ROAD_NAMES:
			var road: Image = sources[road_name].duplicate()
			var material := _cell(road_atlas, biome_index, 3, 2)
			var mw := material.get_width()
			var mh := material.get_height()
			material = material.get_region(Rect2i(mw / 4, mh / 4, mw / 2, mh / 2))
			material.resize(road.get_width(), road.get_height(), Image.INTERPOLATE_LANCZOS)
			_make_seamless(material, maxi(2, road.get_width() / 8))
			for y in road.get_height():
				for x in road.get_width():
					var color := road.get_pixel(x, y)
					if color.a <= 0.0:
						continue
					# Original Spire tiles include green grass around the road. Let the biome ground show through there.
					if color.s > 0.18 and color.h >= 0.14 and color.h < 0.48:
						road.set_pixel(x, y, Color(0, 0, 0, 0))
					else:
						var surface := material.get_pixel(x, y)
						surface = surface.lerp(Color(ROAD_COLORS[biome]), 0.10)
						if biome == "winter":
							surface = surface.lerp(Color("#6e9eaf"), 0.4)
						var shade := 0.75 + 0.25 * color.v
						road.set_pixel(x, y, Color(surface.r * shade, surface.g * shade, surface.b * shade, color.a))
			var road_mask: Image = road.duplicate()
			for y in road.get_height():
				for x in road.get_width():
					var p := Vector2i(x, y)
					if road_mask.get_pixelv(p).a == 0.0:
						continue
					for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						var n: Vector2i = p + offset
						if n.x >= 0 and n.y >= 0 and n.x < road.get_width() and n.y < road.get_height() and road_mask.get_pixelv(n).a == 0.0:
							road.set_pixelv(p, road_mask.get_pixelv(p).darkened(0.32))
							break
			var path: String = ROOT + "/roads/" + biome + "_" + str(road_name) + ".png"
			if not _save(road, path):
				return {}
			biome_paths[road_name] = "res://assets/biomes/roads/" + biome + "_" + str(road_name) + ".png"
		all_paths[biome] = biome_paths
	return all_paths


func _cell(sheet: Image, index: int, columns: int, rows: int) -> Image:
	var column := index % columns
	var row := int(index / columns)
	var x0 := int(round(float(column) * sheet.get_width() / columns))
	var y0 := int(round(float(row) * sheet.get_height() / rows))
	var x1 := int(round(float(column + 1) * sheet.get_width() / columns))
	var y1 := int(round(float(row + 1) * sheet.get_height() / rows))
	return sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))


func _save_sprite(source: Image, path: String, canvas_size: int, threshold: float, max_width: int, max_height: int) -> bool:
	_threshold_alpha(source, threshold)
	_keep_main_sprite(source)
	var used := source.get_used_rect()
	if used.size.x == 0 or used.size.y == 0:
		push_error("Empty biome sprite: " + path)
		return false
	var sprite := source.get_region(used)
	var scale := minf(float(max_width) / sprite.get_width(), float(max_height) / sprite.get_height())
	var width := maxi(1, roundi(sprite.get_width() * scale))
	var height := maxi(1, roundi(sprite.get_height() * scale))
	sprite.resize(width, height, Image.INTERPOLATE_NEAREST)
	_threshold_alpha(sprite, 0.28)
	used = sprite.get_used_rect()
	sprite = sprite.get_region(used)
	width = sprite.get_width()
	height = sprite.get_height()
	var canvas := Image.create(canvas_size, canvas_size, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var dest := Vector2i((canvas_size - width) / 2, canvas_size - height)
	canvas.blit_rect(sprite, Rect2i(Vector2i.ZERO, Vector2i(width, height)), dest)
	var error := canvas.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Could not save biome sprite: " + path)
		return false
	return true


func _threshold_alpha(image: Image, threshold: float) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a < threshold:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))


func _keep_main_sprite(image: Image) -> void:
	# Atlas cells can contain fragments of neighbouring sprites. Keep the main silhouette.
	var w := image.get_width()
	var h := image.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var largest: Array[Vector2i] = []
	for y in h:
		for x in w:
			if visited[y * w + x] != 0 or image.get_pixel(x, y).a == 0.0:
				continue
			var component: Array[Vector2i] = [Vector2i(x, y)]
			visited[y * w + x] = 1
			var cursor := 0
			while cursor < component.size():
				var p: Vector2i = component[cursor]
				cursor += 1
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = p + offset
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					if visited[n.y * w + n.x] == 0 and image.get_pixelv(n).a > 0.0:
						visited[n.y * w + n.x] = 1
						component.append(n)
			if component.size() > largest.size():
				largest = component
	var clean := Image.create(w, h, false, Image.FORMAT_RGBA8)
	clean.fill(Color.TRANSPARENT)
	for p in largest:
		clean.set_pixelv(p, image.get_pixelv(p))
	image.copy_from(clean)


func _make_seamless(image: Image, edge_width: int) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var original: Image = image.duplicate()
	for y in height:
		for i in edge_width:
			var fade: float = 1.0 - float(i) / float(edge_width - 1)
			var left: Color = original.get_pixel(i, y)
			var right: Color = original.get_pixel(width - 1 - i, y)
			var shared: Color = left.lerp(right, 0.5)
			image.set_pixel(i, y, left.lerp(shared, fade))
			image.set_pixel(width - 1 - i, y, right.lerp(shared, fade))
	original = image.duplicate()
	for x in width:
		for i in edge_width:
			var fade: float = 1.0 - float(i) / float(edge_width - 1)
			var top: Color = original.get_pixel(x, i)
			var bottom: Color = original.get_pixel(x, height - 1 - i)
			var shared: Color = top.lerp(bottom, 0.5)
			image.set_pixel(x, i, top.lerp(shared, fade))
			image.set_pixel(x, height - 1 - i, bottom.lerp(shared, fade))


func _save(image: Image, path: String) -> bool:
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Could not save biome tile: " + path)
		return false
	return true
