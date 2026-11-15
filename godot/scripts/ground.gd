class_name TDGround
extends Control
## Земля биома и цельная текстурированная дорога с округлёнными поворотами.

var map: TDMap
var _grass: Texture2D
var _tiles: Dictionary = {}
var _road_surface: Texture2D
var _variants: Array[Texture2D] = []
var _road_native: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var grade := ShaderMaterial.new()
	grade.shader = preload("res://assets/ui/terrain-grade.gdshader")
	material = grade
	_load_tiles()


func _load_tiles() -> void:
	if TDArt.ok():
		var paths: Dictionary = TDArt.meta.get("tiles", {})
		_grass = TDArt.tex(paths.get("grass", ""))
		for key in ["road_h", "road_v", "corner_rd", "corner_ld", "corner_ru", "corner_lu"]:
			var overlay_path: String = "res://assets/biomes/roads/" + str(key) + ".png"
			var overlay := TDArt.tex(overlay_path)
			_tiles[key] = overlay if overlay != null else TDArt.tex(paths.get(key, ""))


func set_map(value: TDMap) -> void:
	map = value
	_road_native = null
	_variants.clear()
	var biome_id := TDEnv.biome_of_seed(value.seed_value)
	var visuals: Dictionary = TDArt.biome_meta.get(biome_id, {}) if TDArt.ok() else {}
	var ground_path: String = visuals.get("ground", "")
	_road_surface = TDArt.tex(visuals.get("road_surface", ""))
	if not ground_path.is_empty():
		_grass = TDArt.tex(ground_path)
	for path in visuals.get("ground_variants", []):
		var variant := TDArt.tex(path)
		if variant != null: _variants.append(variant)
	var road_paths: Dictionary = visuals.get("roads", {})
	for key in ["road_h", "road_v", "corner_rd", "corner_ld", "corner_ru", "corner_lu"]:
		var road_path: String = road_paths.get(key, "")
		if not road_path.is_empty():
			var road: Texture2D = TDArt.tex(road_path)
			if road != null:
				_tiles[key] = road
	queue_redraw()


func _dir_name(d: Vector2i) -> String:
	if d.x > 0: return "r"
	if d.x < 0: return "l"
	if d.y > 0: return "d"
	return "u"


func _road_texture(index: int) -> Texture2D:
	var here: Vector2i = map.order[index]
	var dirs: Array[String] = []
	if index > 0:
		dirs.append(_dir_name(map.order[index - 1] - here))
	if index + 1 < map.order.size():
		dirs.append(_dir_name(map.order[index + 1] - here))
	if dirs.size() == 2:
		if dirs.has("r") and dirs.has("d"): return _tiles.get("corner_rd")
		if dirs.has("l") and dirs.has("d"): return _tiles.get("corner_ld")
		if dirs.has("r") and dirs.has("u"): return _tiles.get("corner_ru")
		if dirs.has("l") and dirs.has("u"): return _tiles.get("corner_lu")
	var horizontal := dirs.is_empty() or dirs.has("r") or dirs.has("l")
	return _tiles.get("road_h" if horizontal else "road_v")


func _draw() -> void:
	if map == null:
		return
	var cell := minf(size.x / TDConfig.COLS, size.y / TDConfig.ROWS)
	var rect_size := Vector2(cell, cell)
	if _grass != null:
		# Large, low-contrast patches keep the ground from reading as a small repeating grid.
		var patch_size := rect_size * 4.0
		for y in range(-4, TDConfig.ROWS, 4):
			for x in range(-3, TDConfig.COLS + 1, 4):
				var center := (Vector2(x, y) + Vector2(2.0, 2.0)) * cell
				var grass := _grass if _variants.is_empty() else _variants[int(TDEnv._hash(x, y, map.seed_value) * _variants.size()) % _variants.size()]
				draw_texture_rect(grass, Rect2(center - patch_size * 0.5, patch_size), false, Color(0.92, 0.94, 0.96))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#547341"))
	if _road_surface != null:
		_draw_road(cell)
		return
	for i in map.order.size():
		var tile := _road_texture(i)
		if tile == null:
			continue
		var c: Vector2i = map.order[i]
		draw_texture_rect(tile, Rect2(Vector2(c.x, c.y) * cell, rect_size), false)


func _draw_road(cell: float) -> void:
	if _road_native == null:
		_build_road_native()
	if _road_native != null:
		draw_texture_rect(_road_native, Rect2(Vector2.ZERO, Vector2(TDConfig.COLS, TDConfig.ROWS) * cell), false)

func _build_road_native() -> void:
	# Rasterize the edge once on the same 64px/cell grid as the source textures.
	var cell := 64.0
	var line := PackedVector2Array()
	line.append(map.points[0] * cell)
	for i in range(1, map.points.size() - 1):
		var p: Vector2 = map.points[i] * cell
		var incoming: Vector2 = (map.points[i] - map.points[i - 1]).normalized()
		var outgoing: Vector2 = (map.points[i + 1] - map.points[i]).normalized()
		var radius := minf(cell * 0.9, minf(p.distance_to(map.points[i - 1] * cell), p.distance_to(map.points[i + 1] * cell)) * 0.45)
		var a := p - incoming * radius
		var b := p + outgoing * radius
		for step in 9:
			var t := float(step) / 8.0
			line.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	var layout := map.castle_layout(Vector2(TDConfig.COLS, TDConfig.ROWS) * cell)
	line.append(layout["road_end"])
	var borders := Geometry2D.offset_polyline(line, cell * 0.45, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	var surfaces := Geometry2D.offset_polyline(line, cell * 0.43, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	var surface := _road_surface.get_image()
	var image := Image.create(TDConfig.COLS * 64, TDConfig.ROWS * 64, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var point := Vector2(x + 0.5, y + 0.5)
			var inside := false
			for polygon in surfaces:
				if Geometry2D.is_point_in_polygon(point, polygon):
					inside = true
					break
			var color := surface.get_pixel(x % surface.get_width(), y % surface.get_height())
			if inside:
				image.set_pixel(x, y, color)
			else:
				for polygon in borders:
					if Geometry2D.is_point_in_polygon(point, polygon):
						image.set_pixel(x, y, Color(color.r * 0.65, color.g * 0.65, color.b * 0.65, 1))
						break
	_road_native = ImageTexture.create_from_image(image)
