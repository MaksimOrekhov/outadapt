class_name TDArt
extends RefCounted
## Авторские башни, враги и биомы; Spire (Foozle, CC0) — снаряды, попадания и эффекты.
## Данные готовит tools/import_spire.py → assets/spire/spire.json. Здесь — загрузка и рисование кадров.
## Масштаб: 1 пиксель исходника = клетка / 64 (тайл и основание башни — 64 пикселя в ширину).

const DIR := "res://assets/spire/"

static var meta: Dictionary = {}
static var biome_meta: Dictionary = {}
static var custom_towers: Dictionary = {}
static var custom_enemies: Dictionary = {}
static var _tex: Dictionary = {}
static var _loaded := false


static func ok() -> bool:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(DIR + "spire.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				meta = d
		var biome_file := FileAccess.open("res://assets/biomes/biomes.json", FileAccess.READ)
		if biome_file != null:
			var biome_data = JSON.parse_string(biome_file.get_as_text())
			if biome_data is Dictionary:
				biome_meta = biome_data.get("biomes", {})
		var custom_file := FileAccess.open("res://assets/custom_towers/custom_towers.json", FileAccess.READ)
		if custom_file != null:
			var custom_data = JSON.parse_string(custom_file.get_as_text())
			if custom_data is Dictionary:
				custom_towers = custom_data.get("towers", {})
		var enemy_file := FileAccess.open("res://assets/custom_enemies/custom_enemies.json", FileAccess.READ)
		if enemy_file != null:
			var enemy_data = JSON.parse_string(enemy_file.get_as_text())
			if enemy_data is Dictionary:
				custom_enemies = enemy_data.get("enemies", {})
	return not meta.is_empty()


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		var resource_path := path if path.begins_with("res://") else DIR + path
		_tex[path] = load(resource_path) if ResourceLoader.exists(resource_path) else null
	return _tex[path]


static func tower_level(kind: String, level: int, branch: String = "") -> Dictionary:
	if not ok():
		return {}
	var has_base: bool = meta["towers"].has(kind)
	if not has_base and not custom_towers.has(kind):
		return {}
	var index := clampi(level, 1, 3) - 1
	# башни, добавленные позже, целиком описаны в custom_towers.json
	var data: Dictionary = meta["towers"][kind]["levels"][index].duplicate(true) if has_base else {}
	if custom_towers.has(kind):
		var custom: Dictionary = custom_towers[kind]["levels"][index]
		for key in custom:
			data[key] = custom[key].duplicate(true) if custom[key] is Dictionary or custom[key] is Array else custom[key]
	if level >= 3 and data.get("branches", {}).has(branch):
		var specialization: Dictionary = data["branches"][branch]
		for key in specialization:
			data[key] = specialization[key].duplicate(true) if specialization[key] is Dictionary else specialization[key]
	return data


static func is_custom_tower(kind: String) -> bool:
	return ok() and custom_towers.has(kind)


static func enemy_model(species_name: String) -> Dictionary:
	if not ok():
		return {}
	return custom_enemies.get(species_name, {})


## Прямоугольник кадра i в листе анимации ({frame, frame_h, cols}).
static func frame_rect(a: Dictionary, i: int) -> Rect2:
	var fw: float = a["frame"]
	var fh: float = a.get("frame_h", fw)
	var cols: int = int(a.get("cols", 1))
	var n: int = int(a.get("frames", 1))
	i = posmod(i, maxi(1, n))
	var row := floori(float(i) / float(cols))
	return Rect2((i % cols) * fw, row * fh, fw, fh)


## Кадр анимации с центром в pos. unit — экранных пикселей на пиксель исходника.
static func draw_frame(ci: CanvasItem, a: Dictionary, i: int, pos: Vector2, unit: float, rot: float = 0.0, flip: bool = false, mod: Color = Color.WHITE) -> void:
	var t := tex(a["file"])
	if t == null:
		return
	var src := frame_rect(a, i)
	var sz := src.size * unit
	ci.draw_set_transform(pos, rot, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect_region(t, Rect2(-sz * 0.5, sz), src, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Вид врага по геному: главная черта выбирает существо из пакета.
static func species(genome: Dictionary, fly: bool, boss: bool) -> String:
	if boss:
		return "magma_crab"
	if fly:
		if genome.get("veil", 0.0) > 0.5:
			return "voidbutterfly"
		var best := "flying_locust"
		var bv := 0.25
		for pair in [
			["ember", "firewasp"], ["plated", "clampbeetle"], ["frost", "frost_moth"],
			["regen", "sporebat"], ["tough", "rune_drake"], ["split", "splitwing"], ["ward", "stormray"],
		]:
			if genome.get(pair[0], 0.0) > bv:
				bv = genome[pair[0]]
				best = pair[1]
		return best
	var g := "leafbug"
	var v := 0.28
	for pair in [
		["plated", "scorpion"], ["ember", "magma_crab"], ["swift", "firebug"],
		["regen", "rotcap"], ["tough", "basalt_tortoise"],
		["split", "split_slime"], ["ward", "rune_guardian"],
	]:
		if genome.get(pair[0], 0.0) > v:
			v = genome[pair[0]]
			g = pair[1]
	return g
