class_name TDEnv
extends RefCounted
## Окружение карты: биом по сиду, препятствия (деревья, валуны, пруды), мелкая флора.
## Всё детерминировано от сида, на геймплей не влияет.

const IDS := ["forest", "autumn", "winter", "swamp", "volcanic", "dungeon"]

const BIOMES := {
	"forest": {
		"name": "Древний лес", "pond_tint": "#9bc8d1", "castle_glow": "#a7ffb2",
		"weights": {"pine": 22, "oak": 30, "bush": 16, "rock1": 12, "rock2": 8, "pond": 8, "crystal": 4},
		"pine_tint": "#ffffff", "oak_tint": "#ffffff", "bush_tint": "#ffffff",
		"flora": ["#ffe27a", "#ffffff", "#ff9ad0", "#9ad7ff"], "flora_kind": "flower",
		"ambient": "leaf", "ambient_cols": ["#8fd35a", "#b6e070", "#6fb84a"], "ambient_rate": 1.4,
	},
	"autumn": {
		"name": "Золотая осень", "pond_tint": "#c89055", "castle_glow": "#ffd486",
		"weights": {"pine": 14, "oak": 40, "bush": 18, "rock1": 12, "rock2": 8, "pond": 4, "crystal": 4},
		"pine_tint": "#e9d9a0", "oak_tint": "#ff9a46", "bush_tint": "#e0803a",
		"flora": ["#d94a3a", "#ffb347", "#f1e3c0"], "flora_kind": "mushroom",
		"ambient": "leaf", "ambient_cols": ["#ff8a3c", "#e0503a", "#ffc04a", "#c97a2a"], "ambient_rate": 1.4,
	},
	"winter": {
		"name": "Ледяные пики", "pond_tint": "#a9e6ff", "castle_glow": "#9de7ff",
		"weights": {"pine": 42, "oak": 6, "bush": 10, "rock1": 18, "rock2": 14, "pond": 6, "crystal": 8},
		"pine_tint": "#dcefff", "oak_tint": "#b9cde0", "bush_tint": "#cfe3f3",
		"flora": ["#e8f6ff", "#bfe6ff"], "flora_kind": "ice",
		"ambient": "snow", "ambient_cols": ["#ffffff", "#dff0ff"], "ambient_rate": 10.0,
	},
	"swamp": {
		"name": "Мшистые топи", "pond_tint": "#57b5a1", "castle_glow": "#68f3d7",
		"weights": {"pine": 8, "oak": 26, "bush": 14, "rock1": 10, "rock2": 6, "pond": 30, "crystal": 6},
		"pine_tint": "#6f9a78", "oak_tint": "#7d9c62", "bush_tint": "#6c9a6a",
		"flora": ["#8be86a", "#c9a0ff", "#7ddcc8"], "flora_kind": "glow",
		"ambient": "rain", "ambient_cols": ["#91cfc6", "#b6eee1", "#8aaeb0"], "ambient_rate": 24.0,
	},
	"volcanic": {
		"name": "Пепельные пустоши", "pond_tint": "#ff8241", "castle_glow": "#ff7138",
		"weights": {"pine": 12, "oak": 12, "bush": 9, "rock1": 22, "rock2": 18, "pond": 15, "crystal": 12},
		"pine_tint": "#b56247", "oak_tint": "#8f4b3d", "bush_tint": "#ff9252",
		"flora": ["#ffd35a", "#ff713d", "#bd3a24"], "flora_kind": "ember",
		"ambient": "ash", "ambient_cols": ["#ff9a4a", "#d85b35", "#76656b"], "ambient_rate": 8.0,
	},
	"dungeon": {
		"name": "Забытое подземелье", "pond_tint": "#9464c9", "castle_glow": "#c38cff",
		"weights": {"pine": 12, "oak": 14, "bush": 14, "rock1": 18, "rock2": 14, "pond": 8, "crystal": 20},
		"pine_tint": "#aaa2b5", "oak_tint": "#8d819e", "bush_tint": "#a28db5",
		"flora": ["#c38cff", "#76daed", "#edb6ff"], "flora_kind": "rune",
		"ambient": "dust", "ambient_cols": ["#c4b5d6", "#8e839d", "#b38bd6"], "ambient_rate": 7.0,
	},
}

var map: TDMap
var biome_id: String
var b: Dictionary
var decor: Array = []
var flora: Array = []


static func biome_of_seed(seed_value: int) -> String:
	return IDS[absi(seed_value) % IDS.size()]


static func biome_name(seed_value: int) -> String:
	return BIOMES[biome_of_seed(seed_value)]["name"]


static func _hash(x: int, y: int, salt: int = 0) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


func _init(m: TDMap) -> void:
	map = m
	biome_id = biome_of_seed(m.seed_value)
	b = BIOMES[biome_id]
	_build()


func _pick_kind(h: float) -> String:
	var total := 0.0
	for k in b["weights"]:
		total += b["weights"][k]
	var r := h * total
	for k in b["weights"]:
		r -= b["weights"][k]
		if r <= 0.0:
			return k
	return "rock1"


func _build() -> void:
	decor.clear()
	flora.clear()
	var s := map.seed_value
	for c in map.blocked:
		var kind := _pick_kind(_hash(c.x, c.y, s + 1))
		if kind == "pond":
			kind = "bush" if biome_id == "swamp" else "rock1"
		# Keep the castle approach readable while retaining a marker for blocked cells.
		if (Vector2(c) + Vector2(0.5, 0.5)).distance_to(map.points.back()) < 2.0:
			kind = "rock1"
		# в верхнем ряду высокие деревья и кристаллы торчали бы за край поля — ставим низкий декор
		if c.y == 0 and kind in ["pine", "oak", "crystal"]:
			kind = "bush" if _hash(c.x, c.y, s + 5) < 0.5 else "rock1"
		# Tall props stay at least one complete cell away from the route.
		var near_road := false
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				if map.cells.has(c + Vector2i(offset_x, offset_y)):
					near_road = true
		if kind in ["pine", "oak"] and (near_road or _hash(c.x, c.y, s + 9) < 0.35):
			kind = "bush" if _hash(c.x, c.y, s + 10) < 0.5 else "rock1"
		decor.append({
			"c": c, "kind": kind,
			"flip": -1.0 if _hash(c.x, c.y, s + 2) < 0.5 else 1.0,
			"ph": _hash(c.x, c.y, s + 3) * TAU,
			"sc": 0.9 + 0.2 * _hash(c.x, c.y, s + 4),
		})
	decor.sort_custom(func(a, d): return a["c"].y < d["c"].y)
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			var c := Vector2i(x, y)
			if map.cells.has(c) or map.blocked.has(c):
				continue
			var h := _hash(x, y, s + 11)
			if h < 0.08:
				var n := 1 + int(_hash(x, y, s + 12) * 1.6)
				for i in n:
					flora.append({
						"p": Vector2(x + 0.12 + 0.76 * _hash(x, y, s + 20 + i), y + 0.12 + 0.76 * _hash(x, y, s + 30 + i)),
						"col": Color(b["flora"][int(_hash(x, y, s + 40 + i) * b["flora"].size()) % b["flora"].size()]),
						"ph": _hash(x, y, s + 50 + i) * TAU,
						"sz": 0.8 + 0.5 * _hash(x, y, s + 60 + i),
					})


## Источники света для аддитивного слоя: [{p, size, col, flick}] в клетках.
func lights() -> Array:
	var out: Array = []
	for d in decor:
		if d["kind"] == "crystal":
			out.append({"p": Vector2(d["c"].x + 0.5, d["c"].y + 0.35), "size": 26.0, "col": Color("#b58cff"), "flick": 0.10, "ph": d["ph"]})
		elif d["kind"] == "pond" and biome_id in ["swamp", "volcanic", "dungeon"]:
			out.append({"p": Vector2(d["c"].x + 0.5, d["c"].y + 0.5), "size": 22.0, "col": Color(b["pond_tint"]), "flick": 0.18, "ph": d["ph"]})
	return out


func draw(ci: CanvasItem, cs: float, t: float) -> void:
	_draw_flora(ci, cs, t)
	for d in decor:
		_draw_decor(ci, cs, t, d)


func _draw_flora(ci: CanvasItem, cs: float, t: float) -> void:
	var k := cs / 48.0
	var kind: String = b["flora_kind"]
	for f in flora:
		var p: Vector2 = f["p"] * cs
		var sway := sin(t * 1.6 + f["ph"]) * 1.6 * k
		var sz: float = f["sz"] * k
		var col: Color = f["col"]
		match kind:
			"flower":
				ci.draw_line(p, p + Vector2(sway, -5.0 * sz), Color("#2f6a3a"), 1.4 * k)
				var top := p + Vector2(sway, -5.0 * sz)
				for i in 4:
					var a: float = i * TAU / 4.0 + float(f["ph"])
					ci.draw_circle(top + Vector2(cos(a), sin(a)) * 1.9 * sz, 1.5 * sz, col)
				ci.draw_circle(top, 1.2 * sz, Color("#fff3b0"))
			"mushroom":
				ci.draw_rect(Rect2(p + Vector2(-0.9, -2.2) * sz, Vector2(1.8, 3.2) * sz), Color("#efe6d2"))
				ci.draw_circle(p + Vector2(0, -3.0 * sz), 3.1 * sz, col)
				ci.draw_circle(p + Vector2(-1.0, -3.6) * sz, 0.7 * sz, Color(1, 1, 1, 0.8))
			"ice":
				var tw := 0.5 + 0.5 * sin(t * 2.0 + f["ph"])
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4.2) * sz, p + Vector2(1.8, -1.0) * sz, p + Vector2(0, 0.6) * sz, p + Vector2(-1.8, -1.0) * sz]), Color(col.r, col.g, col.b, 0.55 + 0.35 * tw))
			"glow":
				ci.draw_line(p, p + Vector2(sway, -6.0 * sz), Color("#2b5a44"), 1.4 * k)
				ci.draw_circle(p + Vector2(sway, -6.0 * sz), 2.2 * sz, Color(col.r, col.g, col.b, 0.75))
			"ember":
				var top := p + Vector2(sway, -3.0 * sz)
				ci.draw_colored_polygon(PackedVector2Array([top + Vector2(0, -3.0 * sz), top + Vector2(1.8 * sz, 1.2 * sz), top + Vector2(0, 0), top + Vector2(-1.8 * sz, 1.2 * sz)]), Color(col.r, col.g, col.b, 0.75))
				ci.draw_circle(top, 0.9 * sz, Color("#fff0a3"))
			"rune":
				var pulse := 0.5 + 0.5 * sin(t * 2.0 + f["ph"])
				var rune_col := Color(col.r, col.g, col.b, 0.25 + 0.35 * pulse)
				ci.draw_arc(p, 2.2 * sz, 0.0, TAU, 4, rune_col, 1.0 * k, true)
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -2.2) * sz, p + Vector2(1.2, 0) * sz, p + Vector2(0, 2.2) * sz, p + Vector2(-1.2, 0) * sz]), rune_col)


func _tint(kind: String) -> Color:
	match kind:
		"pine":
			return Color(b["pine_tint"])
		"oak":
			return Color(b["oak_tint"])
		"bush":
			return Color(b["bush_tint"])
	return Color.WHITE


func _draw_decor(ci: CanvasItem, cs: float, t: float, d: Dictionary) -> void:
	var c: Vector2i = d["c"]
	var kind: String = d["kind"]
	var center := (Vector2(c.x, c.y) + Vector2(0.5, 0.5)) * cs
	if kind == "pond":
		var pond := TDSprites.tex("d_pond")
		if pond != null:
			var side := cs * 1.12
			ci.draw_texture_rect(pond, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false, Color(b["pond_tint"]))
			for i in 3:
				var ph: float = d["ph"] + i * 2.1
				var a := 0.5 + 0.5 * sin(t * 1.3 + ph)
				var pp := center + Vector2(cos(ph) * 0.16, sin(ph * 1.3) * 0.08) * cs
				ci.draw_arc(pp, cs * 0.08, PI * 1.1, PI * 1.9, 8, Color(1, 1, 1, 0.35 * a), 1.2, true)
		return
	var biome_visuals: Dictionary = TDArt.biome_meta.get(biome_id, {}) if TDArt.ok() else {}
	var prop_paths: Dictionary = biome_visuals.get("props", {})
	var prop_path: String = prop_paths.get(kind, "")
	var custom_prop: Texture2D = TDArt.tex(prop_path) if not prop_path.is_empty() else null
	if custom_prop != null:
		var big := kind == "pine" or kind == "oak"
		var size: float = float(custom_prop.get_width()) * cs / 64.0
		var base := center + Vector2(0, cs * 0.40)
		ci.draw_set_transform(base + Vector2(size * 0.10, 0), 0.0, Vector2(1.0, 0.32))
		ci.draw_circle(Vector2.ZERO, size * (0.30 if big else 0.34), Color(0, 0, 0, 0.28))
		var sway := 0.0 # Native pixel grid; weather provides motion around static props.
		ci.draw_set_transform(base, sway, Vector2(d["flip"], 1.0))
		ci.draw_texture_rect(custom_prop, Rect2(Vector2(-size * 0.5, -size), Vector2(size, size)), false)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var tile_paths: Dictionary = TDArt.meta.get("tiles", {}) if TDArt.ok() else {}
	var choices: Array = []
	if kind in ["pine", "oak"]:
		var tree_key := "tree_autumn" if biome_id == "autumn" else "tree_green"
		choices = tile_paths.get(tree_key, [])
	elif kind == "bush":
		choices = tile_paths.get("tuft", [])
	elif kind in ["rock1", "rock2"]:
		choices = tile_paths.get("rock", [])
	if not choices.is_empty():
		var pick := int(_hash(c.x, c.y, map.seed_value + 71) * choices.size()) % choices.size()
		var tile: Texture2D = TDArt.tex(choices[pick])
		if tile == null:
			return
		var side: float = cs * (0.92 if kind == "bush" else 1.05) * float(d["sc"])
		ci.draw_texture_rect(tile, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		return
	var tex := TDSprites.tex("d_" + kind)
	if tex == null:
		return
	var big := kind == "pine" or kind == "oak"
	var size: float = cs * (1.62 if big else (1.1 if kind == "crystal" else 1.0)) * d["sc"]
	var base := center + Vector2(0, cs * 0.40)
	# тень
	ci.draw_set_transform(base + Vector2(size * 0.10, 0), 0.0, Vector2(1.0, 0.32))
	ci.draw_circle(Vector2.ZERO, size * (0.30 if big else 0.34), Color(0, 0, 0, 0.30))
	var sway := 0.0
	if kind == "pine" or kind == "oak" or kind == "bush":
		sway = sin(t * 1.1 + d["ph"]) * (0.025 if kind != "bush" else 0.012) + sin(t * 2.3 + d["ph"] * 2.0) * 0.008
	ci.draw_set_transform(base, sway, Vector2(d["flip"], 1.0))
	var s := size / 128.0
	ci.draw_texture_rect(tex, Rect2(Vector2(-64.0, -116.0) * s, Vector2(size, size)), false, _tint(kind))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
