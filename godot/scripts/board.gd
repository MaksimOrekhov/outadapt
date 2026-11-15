class_name TDBoard
extends Control
## Игровое поле: рисует карту, башни, врагов и эффекты, ловит клики.

signal cell_clicked(cell: Vector2i, button: int)

const FX_TEXT_LIFE := 0.6
const BASE_WIDTH := 0.80
const WEAPON_SIDE := 1.22
const WEAPON_FPS := 20.0
## Главная черта врага по порядку приоритета: [ген, цвет, иконка].
const TRAITS := [
	["ember", "#ef6a3c", "gene-ember"], ["frost", "#62bdf0", "gene-frost"],
	["plated", "#b9c2d0", "gene-plated"], ["swift", "#ffd35a", "gene-swift"],
	["tough", "#ff7a8a", "gene-tough"], ["regen", "#7ddc5a", "gene-regen"],
	["wings", "#89d8ff", "gene-wings"], ["veil", "#ba9cff", "gene-veil"],
	["split", "#e08af0", "gene-split"], ["ward", "#9bd4ff", "gene-ward"],
]
const GENE_TINT := {
	"ember": "#ff8a5c", "frost": "#8fd3ff", "tough": "#ff8f9c", "swift": "#ffd35a",
	"regen": "#8be86a", "plated": "#c4ccd8", "wings": "#89d8ff", "veil": "#ba9cff",
	"split": "#e08af0", "ward": "#9bd4ff",
}

var _enemy_models: Dictionary = {}
var _enemy_shields: Dictionary = {}
var game: TDGame
var tool: String = ""
var audio: TDAudio
var hover_cell := Vector2i(-1, -1)
var hover_pos := Vector2(-1, -1)
var hovered_enemy: TDGame.Enemy = null
## Клетки дороги без обстрела (подсвечиваются красным).
var vfx := TDVfx.new()
## Выбранная игроком башня: рисуем кольцо дальности.
var selected: TDGame.Tower = null

var _cs := 56.0
## Где поле лежит внутри сцены (рамка вокруг); тряска экрана добавляется поверх.
var base_pos := Vector2.ZERO
var _time := 0.0
var _layer: TDFxLayer
## Пиксельные тайлы лежат под полем; main создаёт узел и передаёт сюда.
var ground: TDGround
var env: TDEnv
var _spire_shots: Array[Dictionary] = []
var _spire_deaths: Array[Dictionary] = []
var _spire_collapses: Array[Dictionary] = []
var _attack_start: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layer = TDFxLayer.new()
	_layer.vfx = vfx
	add_child(_layer)


func cell_size() -> float:
	return _cs


func set_game(g: TDGame) -> void:
	game = g
	game.emit_events = true
	env = TDEnv.new(g.map)
	if ground != null:
		ground.set_map(g.map)
	vfx.ambient = env.b["ambient"]
	vfx.ambient_cols = env.b["ambient_cols"]
	vfx.ambient_rate = env.b["ambient_rate"]
	hovered_enemy = null
	_spire_shots.clear()
	_spire_deaths.clear()
	_spire_collapses.clear()
	_attack_start.clear()
	vfx.clear()


static func dominant(e: TDGame.Enemy) -> Array:
	var best := []
	var best_v := 0.3
	for t in TRAITS:
		if e.genome[t[0]] > best_v:
			best_v = e.genome[t[0]]
			best = [t[0], Color(t[1]), t[2]]
	return best


func _process(delta: float) -> void:
	_time += delta
	if game == null:
		return
	for ev in game.events:
		if ev["type"] == "shot":
			var hop: bool = ev.get("hop", false)
			if not hop:
				var lv: int = ev.get("level", 1)
				ev["from"] = ev["from"] + Vector2(0, _muzzle_lift(ev["kind"], lv))
				_attack_start[int(ev.get("tower_id", -1))] = _time
			var travel: float = TDVfx.DELAY.get(ev["kind"], 0.1)
			var art_level := TDArt.tower_level(ev["kind"], int(ev.get("level", 1)))
			var impact: Dictionary = art_level.get("impact", {})
			var impact_life := maxf(0.22, float(impact.get("frames", 1)) / 18.0) if not impact.is_empty() else 0.0
			_spire_shots.append({"event": ev.duplicate(), "age": 0.0, "travel": travel, "life": travel + impact_life})
		elif ev["type"] == "death":
			_spire_deaths.append({
				"species": TDArt.species(ev["genome"], ev["fly"], ev["boss"]),
				"pos": ev["pos"], "heading": ev.get("heading", Vector2.RIGHT),
				"size": ev["size"], "boss": ev["boss"], "fly": ev["fly"], "genome": ev["genome"],
				"age": 0.0, "duration": 0.62,
			})
		elif ev["type"] == "sell":
			_spire_collapses.append({"pos": ev["pos"], "age": 0.0, "duration": 0.75})
		if audio != null:
			audio.on_event(ev)
		vfx.on_event(ev)
	game.events.clear()
	_update_spire_animations(delta)
	vfx.cs = _cs
	vfx.update(delta)
	vfx.update_world(delta, game)
	# тряска экрана: двигаем весь слой поля
	var amp := vfx.shake * vfx.shake * 7.0
	position = base_pos + (Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) if amp > 0.05 else Vector2.ZERO)
	if ground != null:
		ground.position = position
	_collect_lights()
	hovered_enemy = null
	if hover_pos.x >= 0.0:
		var best_d := 0.7
		for e in game.enemies:
			var d := game.pos_of(e).distance_to(hover_pos)
			if d < best_d:
				best_d = d
				hovered_enemy = e
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_set_hover(ev.position)
	elif ev is InputEventMouseButton and ev.pressed:
		var c := _cell_at(ev.position)
		if c.x >= 0:
			cell_clicked.emit(c, ev.button_index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_cell = Vector2i(-1, -1)
		hover_pos = Vector2(-1, -1)


func _cell_at(p: Vector2) -> Vector2i:
	var x := int(floor(p.x / _cs))
	var y := int(floor(p.y / _cs))
	if x < 0 or y < 0 or x >= TDConfig.COLS or y >= TDConfig.ROWS:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _set_hover(p: Vector2) -> void:
	hover_cell = _cell_at(p)
	hover_pos = p / _cs


# ── рисование ─────────────────────────────────────────────────

static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


static func _hash(x: int, y: int, salt: int = 0) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xFFFF) / 65535.0


func _icon(name: String, color: Color, center: Vector2, sz: float) -> void:
	var t := TDIcons.tex(name)
	if t == null:
		return
	draw_texture_rect(t, Rect2(center - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, color)


func _dashed_circle(c: Vector2, r: float, col: Color, width: float, dashes: int = 28, phase: float = 0.0) -> void:
	var step := TAU / dashes
	for i in dashes:
		var a := i * step + phase
		draw_arc(c, r, a, a + step * 0.55, 5, col, width, true)


static func _pop(t: float) -> float:
	# «выпрыгивание» при постройке: от 0 до 1 с небольшим перелётом
	var d := 0.38
	if t >= d:
		return 1.0
	var x := t / d - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x


func _draw() -> void:
	if game == null:
		return
	_cs = minf(size.x / TDConfig.COLS, size.y / TDConfig.ROWS)
	vfx.cs = _cs
	_draw_scorch()
	env.draw(self, _cs, _time)
	_draw_gates()
	_draw_actors()
	_draw_spire_collapses()
	_draw_selection()
	_draw_hover()
	_draw_spire_projectiles()
	vfx.draw_normal(self)
	_draw_text_fx()
	if vfx.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), _a(vfx.flash_col, vfx.flash * 0.45))


## Подпалины от взрывов лежат под всем остальным.
func _draw_scorch() -> void:
	var k := _cs / 48.0
	for p in vfx.parts:
		if p["kind"] == "scorch" and p["delay"] <= 0.0:
			var frac: float = clampf(p["t"] / p["life"], 0.0, 1.0)
			draw_circle(p["p"] * _cs, p["size"] * k, _a(Color(0, 0, 0), 0.30 * minf(1.0, frac * 3.0)))


func _draw_gates() -> void:
	var pts := game.map.points
	var st := pts[0] * _cs
	# портал: пульсирующее свечение, каменное кольцо, закрученная воронка
	var pside := _cs * 1.55
	# портал и замок целиком внутри поля: поле обрезается по краю
	st = Vector2(maxf(st.x, pside * 0.5), clampf(st.y, pside * 0.5, size.y - pside * 0.5))
	var portal := TDArt.tex("res://assets/biomes/portal.png")
	var portal_center := Vector2(st.x, maxf(pside * 0.5, pts[0].y * _cs - _cs * 0.25))
	if portal != null:
		draw_set_transform(portal_center + Vector2(0, pside * 0.43), 0.0, Vector2(1, 0.20))
		draw_circle(Vector2.ZERO, pside * 0.38, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var phase := int(_time * 8.0) % 8
		draw_texture_rect_region(portal, Rect2(portal_center - Vector2.ONE * pside * 0.5, Vector2.ONE * pside), Rect2(phase * 128, 0, 128, 128))
	# замок стоит у конца дороги
	var layout := game.map.castle_layout(size)
	var cside: float = layout["side"]
	var base: Vector2 = layout["base"]
	draw_set_transform(base + Vector2(cside * 0.06, 0), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, cside * 0.42, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var biome_visuals: Dictionary = TDArt.biome_meta.get(env.biome_id, {}) if TDArt.ok() else {}
	var castle_path: String = biome_visuals.get("castle", "")
	var t: Texture2D = TDArt.tex(castle_path) if not castle_path.is_empty() else TDSprites.tex("d_castle")
	if t != null:
		draw_texture_rect(t, Rect2(base - Vector2(cside * 0.5, cside), Vector2(cside, cside)), false)


func _collect_lights() -> void:
	var out: Array = env.lights()
	var pts := game.map.points
	out.append({"p": pts[0], "size": 44.0, "col": Color("#9a7bff"), "flick": 0.08, "ph": 0.0})
	var castle_p: Vector2 = game.map.castle_layout(size)["base"] / _cs + Vector2(0, -0.5)
	out.append({"p": castle_p, "size": 34.0, "col": Color(env.b["castle_glow"]), "flick": 0.05, "ph": 1.0})
	for t in game.towers:
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		if t.kind == "ember":
			out.append({"p": c + Vector2(0, -0.15), "size": 30.0, "col": Color("#ff8a3c"), "flick": 0.28, "ph": t.id})
		elif t.kind == "beacon":
			out.append({"p": c, "size": 34.0, "col": Color("#ffe27a"), "flick": 0.12, "ph": t.id})
		elif t.kind == "frost":
			out.append({"p": c, "size": 22.0, "col": Color("#7fd0ff"), "flick": 0.10, "ph": t.id})
		elif t.kind == "poison":
			out.append({"p": c, "size": 20.0, "col": Color("#7ddc5a"), "flick": 0.15, "ph": t.id})
		elif t.kind == "tesla":
			out.append({"p": c, "size": 24.0, "col": Color("#7fe3ff"), "flick": 0.35, "ph": t.id})
	vfx.lights = out


const ROTATING := ["arrow", "cannon", "ember", "frost", "sniper", "poison", "flak", "tesla", "net"]
## Generated magic heads are not barrels: keep them centered on their mount.
const CUSTOM_AIMED_HEADS := ["arrow", "flak", "cannon", "sniper", "net"]

var _ang: Dictionary = {}


func tower_anchor(t: TDGame.Tower) -> Vector2:
	return Vector2(t.x + 0.5, t.y + 0.80) * _cs


func tower_head_pos(t: TDGame.Tower) -> Vector2:
	var level_data := TDArt.tower_level(t.kind, t.level, t.branch)
	if level_data.is_empty():
		return tower_anchor(t)
	var ground_y: float = level_data["ground"]
	var mount_y: float = level_data["mount"]
	var width: float = float(level_data["base_size"][0])
	var unit := _cs / float(level_data.get("pixel_scale", width / BASE_WIDTH))
	return tower_anchor(t) + Vector2(0, (mount_y - ground_y) * unit)


func _muzzle_lift(kind: String, level: int) -> float:
	var level_data := TDArt.tower_level(kind, level)
	if level_data.is_empty():
		return -0.45
	var ground_y: float = level_data["ground"]
	var mount_y: float = level_data["mount"]
	var width: float = float(level_data["base_size"][0])
	return 0.80 + (mount_y - ground_y) / float(level_data.get("pixel_scale", width / BASE_WIDTH)) - 0.5


func _weapon_frame(weapon: Dictionary, tower_id: int) -> int:
	var frames: int = maxi(1, int(weapon.get("frames", 1)))
	var idle: int = clampi(int(weapon.get("idle", 1)), 1, frames)
	var elapsed: float = _time - float(_attack_start.get(tower_id, -1000.0))
	var attack_frames := frames - idle
	var attack_duration := float(attack_frames) / WEAPON_FPS
	if attack_frames > 0 and elapsed >= 0.0 and elapsed < attack_duration:
		return mini(frames - 1, idle + int(elapsed * WEAPON_FPS))
	return posmod(int(_time * 8.0 + tower_id), idle)


## Основание + голова. sc — масштаб перестройки при улучшении, mod — цвет (для призрака).
func _draw_tower_model(kind: String, level: int, branch: String, anchor: Vector2, sc: float, rot: float, head_off: Vector2, head_scale: float, mod: Color, tower_id: int = -1) -> Vector2:
	var level_data := TDArt.tower_level(kind, level, branch)
	if level_data.is_empty():
		return anchor
	var base_tex := TDArt.tex(level_data["base"])
	var base_size_data: Array = level_data["base_size"]
	var base_size := Vector2(float(base_size_data[0]), float(base_size_data[1]))
	var unit := _cs / float(level_data.get("pixel_scale", base_size.x / BASE_WIDTH))
	var ground_y: float = level_data["ground"]
	draw_set_transform(anchor, 0.0, Vector2(sc, sc))
	if base_tex != null:
		draw_texture_rect(base_tex, Rect2(Vector2(-base_size.x * 0.5, -ground_y) * unit, base_size * unit), false, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var head := anchor + Vector2(0, (float(level_data["mount"]) - ground_y) * unit * sc)
	var weapon: Dictionary = level_data.get("weapon", {})
	if not weapon.is_empty():
		var side_px := maxf(float(weapon["frame"]), float(weapon.get("frame_h", weapon["frame"])))
		var weapon_unit := _cs / float(level_data.get("pixel_scale", side_px / WEAPON_SIDE))
		var frame := _weapon_frame(weapon, tower_id)
		var weapon_angle := rot - deg_to_rad(float(weapon.get("forward_degrees", -90)))
		if TDArt.is_custom_tower(kind) and kind not in CUSTOM_AIMED_HEADS:
			weapon_angle = 0.0
		TDArt.draw_frame(self, weapon, frame, head + head_off, weapon_unit * sc * head_scale, weapon_angle, false, mod)
		if TDArt.is_custom_tower(kind) and tower_id >= 0:
			_draw_custom_muzzle(kind, head + head_off, rot, sc, tower_id)
	return head


func _draw_custom_muzzle(kind: String, weapon_center: Vector2, rot: float, sc: float, tower_id: int) -> void:
	if kind in ["arrow", "flak", "sniper", "net"]:
		return
	var age: float = _time - float(_attack_start.get(tower_id, -1000.0))
	if age < 0.0 or age >= 0.14:
		return
	var power := 1.0 - age / 0.14
	var direction := Vector2.UP.rotated(rot) if kind in CUSTOM_AIMED_HEADS else Vector2.ZERO
	var muzzle := weapon_center + direction * (_cs * 0.34 * sc)
	var color := Color(TDConfig.TOWERS[kind]["color"])
	TDVfx._soft_glow(self, muzzle, (7.0 + 5.0 * power) * _cs / 56.0, Color(color.r, color.g, color.b, 0.6 * power))
	draw_circle(muzzle, (2.4 + 2.2 * power) * _cs / 56.0, Color(1.0, 0.94, 0.72, power))


## One depth list: support points for ground actors; flying enemies form the last layer.
func actor_order() -> Array:
	var actors: Array = []
	for tower in game.towers:
		actors.append({"tower": tower, "y": tower_anchor(tower).y, "fly": false, "id": tower.id})
	for enemy in game.enemies:
		actors.append({"enemy": enemy, "y": game.pos_of(enemy).y * _cs, "fly": bool(enemy.ph["fly"]), "id": enemy.id})
	for death in _spire_deaths:
		actors.append({"death": death, "y": death["pos"].y * _cs, "fly": bool(death["fly"]), "id": 100000})
	actors.sort_custom(func(a, b):
		if a["fly"] != b["fly"]: return not a["fly"]
		if a["y"] != b["y"]: return a["y"] < b["y"]
		return a["id"] < b["id"])
	return actors

func _draw_actors() -> void:
	for actor in actor_order():
		if actor.has("tower"):
			_draw_tower(actor["tower"])
		elif actor.has("enemy"):
			_draw_enemy(actor["enemy"])
		else:
			_draw_enemy_death(actor["death"])

func _draw_tower(t: TDGame.Tower) -> void:
	var k := _cs / 48.0
	var def: Dictionary = t.def
	var anchor := tower_anchor(t)
	var sc := 1.0

	# голова: поворот к цели, отдача, «вспухание»
	var rot := 0.0
	if t.kind in ROTATING:
		var target: float = t.aim.angle()
		var cur: float = _ang.get(t.id, target)
		cur = lerp_angle(cur, target, 0.35)
		_ang[t.id] = cur
		rot = cur
	var kick := Vector2.ZERO
	if not TDArt.is_custom_tower(t.kind) or t.kind in CUSTOM_AIMED_HEADS:
		kick = -t.aim * t.recoil * 5.5 * k * sc
	var bob := Vector2.ZERO
	if TDArt.is_custom_tower(t.kind):
		bob.y += sin(_time * 2.8 + t.id) * 0.8 * k
	if t.kind == "frost":
		bob = Vector2(0, sin(_time * 2.2 + t.id) * 2.0 * k)
	elif t.kind == "poison":
		bob = Vector2(0, sin(_time * 3.0 + t.id) * 1.2 * k)
	elif t.kind == "tesla" and t.level >= 3:
		bob = Vector2(0, sin(_time * 2.6 + t.id) * 1.5 * k)
	var isc: float = 1.0 + 0.10 * t.recoil
	# перестройка при улучшении: приседает, пружинисто вырастает в новую модель и вспыхивает
	var u: float = t.upgraded_t
	if u < 0.12:
		sc *= 1.0 - 1.2 * u
	elif u < 0.6:
		sc *= 0.86 + 0.14 * _pop(u - 0.12)
	var head := _draw_tower_model(t.kind, t.level, t.branch, anchor, sc, rot, kick + bob, isc, Color.WHITE, t.id)
	if u < 0.5:
		var fl := (1.0 - u / 0.5) * 0.85
		_draw_tower_model(t.kind, t.level, t.branch, anchor, sc, rot, kick + bob, isc, Color(2.2, 2.0, 1.6, fl), t.id)

	if t.kind == "beacon":
		# вращающийся луч прожектора
		var reach: float = def["aura"]["radius"] * _cs * 0.8
		for i in 2:
			var a := _time * 1.1 + i * PI
			var pts := PackedVector2Array([head, head + Vector2(cos(a - 0.22), sin(a - 0.22)) * reach, head + Vector2(cos(a + 0.22), sin(a + 0.22)) * reach])
			draw_polygon(pts, PackedColorArray([Color(1.0, 0.9, 0.5, 0.30), Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.9, 0.5, 0.0)]))
	# цитадель: искры цвета башни поднимаются от кристаллов
	if t.level >= 3:
		var col := Color(def["color"])
		for i in 5:
			var ph := fmod(_time * 0.45 + i * 0.2 + t.id * 0.137, 1.0)
			var px := anchor.x + sin(ph * 6.0 + i * 1.7 + t.id) * _cs * 0.30
			var py := anchor.y - _cs * 0.25 - ph * _cs * 0.85
			var al := sin(ph * PI)
			TDVfx._soft_glow(self, Vector2(px, py), 7.0 * k, Color(col.r, col.g, col.b, 0.55 * al))
			draw_circle(Vector2(px, py), 1.4 * k, Color(1, 1, 1, 0.8 * al))


func _draw_spire_collapses() -> void:
	var effect: Dictionary = TDArt.meta.get("fx", {}).get("collapse", {}) if TDArt.ok() else {}
	if effect.is_empty():
		return
	for collapse in _spire_collapses:
		var i := mini(int(collapse["age"] / collapse["duration"] * effect["frames"]), int(effect["frames"]) - 1)
		var p: Vector2 = collapse["pos"] * _cs
		TDArt.draw_frame(self, effect, i, p + Vector2(0, -_cs * 0.2), _cs * 1.7 / float(effect["frame"]))


func _draw_spire_projectiles() -> void:
	for shot in _spire_shots:
		var ev: Dictionary = shot["event"]
		var level_data := TDArt.tower_level(ev["kind"], int(ev.get("level", 1)))
		if level_data.is_empty():
			continue
		var travel: float = shot["travel"]
		var age: float = shot["age"]
		var from: Vector2 = ev["from"]
		var to: Vector2 = ev["to"]
		if age < travel:
			var projectile: Dictionary = level_data.get("projectile", {})
			if projectile.is_empty():
				continue
			var progress := clampf(age / maxf(0.001, travel), 0.0, 1.0)
			var pos := from.lerp(to, progress) * _cs
			if projectile.get("custom", false):
				var muzzle := from + (to - from).normalized() * minf(0.3, from.distance_to(to) * 0.35)
				pos = muzzle.lerp(to, progress) * _cs
			var projectile_frames: int = maxi(1, int(projectile.get("frames", 1)))
			var projectile_frame := int(age * 20.0) % projectile_frames
			var rotation := 0.0
			if float(projectile.get("frame_h", projectile["frame"])) > float(projectile["frame"]) * 1.15:
				rotation = (to - from).angle() + PI * 0.5
			if projectile.has("forward_degrees"):
				rotation = (to - from).angle() - deg_to_rad(float(projectile["forward_degrees"]))
			var projectile_unit := _cs * 0.82 / 64.0
			if projectile.has("display_size"):
				projectile_unit = _cs * float(projectile["display_size"]) * 1.45 / float(projectile["frame"])
			TDArt.draw_frame(self, projectile, projectile_frame, pos, projectile_unit, rotation)
		else:
			var impact: Dictionary = level_data.get("impact", {})
			if impact.is_empty():
				continue
			var impact_age: float = age - travel
			var impact_frames: int = maxi(1, int(impact.get("frames", 1)))
			var fps: float = impact.get("fps", 18.0)
			if impact.has("fps") and impact_age >= float(impact_frames) / fps:
				continue
			var impact_frame := mini(int(impact_age * fps), impact_frames - 1)
			var center := to * _cs
			var radius_scale := 1.0 + float(ev.get("splash", 0.0)) * 0.12
			var impact_unit := _cs * float(impact.get("display_size", 0.88)) * radius_scale / float(impact["frame"])
			TDArt.draw_frame(self, impact, impact_frame, center, impact_unit)


func _draw_enemy_death(death: Dictionary) -> void:
	var custom_model := _enemy_visual_model(death["genome"], death["fly"], death["boss"])
	if not custom_model.is_empty():
		var progress := clampf(float(death["age"]) / float(death["duration"]), 0.0, 1.0)
		var tint := Color.WHITE.lerp(_enemy_color(death["genome"]), 0.12)
		tint.a = 1.0 - progress
		var side := enemy_canvas_side(death["genome"], death["fly"], death["boss"]) * _cs
		_draw_custom_enemy(custom_model, death["pos"] * _cs, side, death["heading"], tint, 0.0, death["fly"], 0.0, progress)


func _update_spire_animations(delta: float) -> void:
	for list in [_spire_shots, _spire_deaths, _spire_collapses]:
		for i in range(list.size() - 1, -1, -1):
			var entry: Dictionary = list[i]
			entry["age"] += delta
			var lifetime: float = float(entry.get("life", entry.get("duration", 0.0)))
			if entry["age"] >= lifetime:
				list.remove_at(i)


func _draw_selection() -> void:
	if selected == null:
		return
	var def: Dictionary = selected.def
	var c := (Vector2(selected.x, selected.y) + Vector2(0.5, 0.5)) * _cs
	var radius: float = (def["aura"]["radius"] if def.has("aura") else game.t_range(selected)) * _cs
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_circle(c, radius, Color(1, 1, 1, 0.06))
	draw_arc(c, radius, 0.0, TAU, 72, Color(1, 1, 1, 0.55), 2.0, true)
	var r := Rect2(selected.x * _cs, selected.y * _cs, _cs, _cs).grow(-1.0)
	draw_rect(r, Color(1.0, 0.83, 0.35, 0.55 + 0.35 * pulse), false, 2.5)


func _draw_hover() -> void:
	if hover_cell.x < 0:
		return
	var existing := game.tower_at(hover_cell.x, hover_cell.y)
	var kind := ""
	if existing != null:
		kind = existing.kind
	elif tool != "sell":
		kind = tool
	var rect := Rect2(hover_cell.x * _cs, hover_cell.y * _cs, _cs, _cs)
	if kind == "":
		if tool == "sell":
			draw_rect(rect.grow(-2.0), Color(1, 0.4, 0.4, 0.06), true)
		return
	var def: Dictionary = TDConfig.TOWERS[kind]
	var ok: bool = existing != null or game.can_place(kind, hover_cell.x, hover_cell.y)
	var c := rect.get_center()
	var radius: float = (def["aura"]["radius"] if def.has("aura") else game.range_of(kind)) * _cs
	var tint := Color(1, 1, 1) if ok else Color(1.0, 0.35, 0.35)
	var breathe := 0.5 + 0.5 * sin(_time * 4.0)
	draw_rect(rect.grow(-2.0), _a(tint, 0.10 + 0.05 * breathe), true)
	draw_rect(rect.grow(-2.0), _a(tint, 0.55), false, 1.5)
	draw_circle(c, radius, _a(tint, 0.07))
	draw_arc(c, radius, 0.0, TAU, 64, _a(tint, 0.45), 1.5, true)
	if existing == null:
		# призрак: настоящая модель башни 1-го уровня, полупрозрачная
		var gm := Color(1, 1, 1, 0.62) if ok else Color(1.0, 0.45, 0.45, 0.55)
		var anchor := Vector2(hover_cell.x + 0.5, hover_cell.y + 0.80) * _cs
		_draw_tower_model(kind, 1, "", anchor, 1.0 + 0.025 * breathe, 0.0, Vector2.ZERO, 1.0, gm)


func _enemy_color(g: Dictionary) -> Color:
	var total := 0.35
	var acc := Color("#8fb2e8") * 0.35
	for k in GENE_TINT:
		var w: float = g[k]
		acc += Color(GENE_TINT[k]) * w
		total += w
	var c := acc / total
	c.a = 1.0
	return c


## Generated enemies use one clean silhouette, animated procedurally in game:
## cardinal turns stay crisp, walking bounces, flying wings flap, hits stagger, deaths tumble.
func _draw_custom_enemy(model: Dictionary, center: Vector2, side: float, heading: Vector2, tint: Color, phase: float, flying: bool, hit: float = 0.0, death_progress: float = -1.0, silhouette: bool = false) -> void:
	var tex: Texture2D = model.get("texture", TDArt.tex(model["file"]))
	if tex == null:
		return
	if silhouette:
		var path: String = model.get("cache_key", model["file"])
		if not _enemy_shields.has(path):
			var mask := tex.get_image()
			for y in mask.get_height():
				for x in mask.get_width():
					mask.set_pixel(x, y, Color(1, 1, 1, mask.get_pixel(x, y).a))
			_enemy_shields[path] = ImageTexture.create_from_image(mask)
		tex = _enemy_shields[path]
	var draw_pos := center
	var forward_angle := deg_to_rad(float(model.get("forward_degrees", 90.0)))
	var angle := heading.angle() - forward_angle
	var scale_x := 1.0
	var scale_y := 1.0
	if model.get("snap_angle", true):
		angle = round(angle / (PI / 4.0)) * (PI / 4.0)
	if death_progress >= 0.0:
		var t := clampf(death_progress, 0.0, 1.0)
		draw_pos += heading * (side * 0.06 * t) + Vector2(0, side * (0.06 if flying else 0.02) * t)
		angle += PI * (0.78 if flying else 0.55) * t
		scale_x = 1.0 - 0.40 * t
		scale_y = 1.0 - 0.72 * t
	else:
		var gait := sin(phase)
		if flying:
			draw_pos.y += sin(phase * 0.5) * side * 0.055
			scale_x = 0.92 + 0.08 * (0.5 + 0.5 * cos(phase))
			scale_y = 0.94 + 0.06 * (0.5 + 0.5 * cos(phase + PI))
			angle += gait * 0.025
		else:
			draw_pos.y -= absf(gait) * side * 0.035
			scale_y = 0.96 + 0.04 * cos(phase * 2.0)
			angle += gait * 0.035
		if hit > 0.0:
			draw_pos -= heading * (side * 0.07 * hit)
			scale_y *= 1.0 - 0.13 * hit
			angle -= signf(gait) * 0.10 * hit
			tint = tint.lerp(Color.WHITE, 0.5 * hit)
	var pivot_data: Array = model.get("pivot", [32, 32])
	var pivot := Vector2(float(pivot_data[0]), float(pivot_data[1])) * (side / float(tex.get_width()))
	draw_set_transform(draw_pos, angle, Vector2(scale_x, scale_y))
	draw_texture_rect(tex, Rect2(-pivot, Vector2(side, side)), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Bake the footprint onto a native pixel grid once, avoiding fractional source pixels.
## Every prepared texture is rendered at cs/64, including the larger boss canvas.
func _enemy_visual_model(genome: Dictionary, fly: bool, boss: bool) -> Dictionary:
	var original := TDArt.enemy_model(TDArt.species(genome, fly, boss))
	if original.is_empty(): return {}
	var width := 77 if boss else (48 if maxf(float(genome.get("tough", 0)), float(genome.get("plated", 0))) >= 0.65 else 35)
	var key: String = original["file"] + ":%d" % width
	if _enemy_models.has(key): return _enemy_models[key]
	var texture := TDArt.tex(original["file"])
	if texture == null: return {}
	var source := texture.get_image()
	var bounds := source.get_used_rect()
	var factor := float(width) / maxf(bounds.size.x, bounds.size.y)
	var old_size := source.get_size()
	source.resize(maxi(1, roundi(old_size.x * factor)), maxi(1, roundi(old_size.y * factor)), Image.INTERPOLATE_NEAREST)
	var frame := 96 if boss else 64
	var pivot := Vector2i(48, 60) if boss else Vector2i(32, 40)
	var old_pivot: Array = original.get("pivot", [32, 32])
	var scaled_pivot := Vector2(float(old_pivot[0]) * source.get_width() / old_size.x, float(old_pivot[1]) * source.get_height() / old_size.y)
	var canvas := Image.create(frame, frame, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), pivot - Vector2i(scaled_pivot.round()))
	var model := original.duplicate(true)
	model["texture"] = ImageTexture.create_from_image(canvas)
	model["pivot"] = [pivot.x, pivot.y]
	model["frame"] = frame
	model["cache_key"] = key
	_enemy_models[key] = model
	return model

func enemy_canvas_side(genome: Dictionary, fly: bool, boss: bool) -> float:
	var model := _enemy_visual_model(genome, fly, boss)
	return float(model.get("frame", 64)) / 64.0

func _draw_enemy(e: TDGame.Enemy) -> void:
	var k := _cs / 48.0
	var gpos := game.pos_of(e)
	var p := gpos * _cs
	var r: float = e.ph["size"] * _cs + 2.0 * k
	var st := TDGame.status_of(e)
	var g: Dictionary = e.genome
	var hidden: bool = e.ph["stealth"] and not game.is_revealed(e)
	var al := 1.0
	if hidden:
		al = 0.28 + 0.06 * sin(_time * 6.0 + e.id)
	elif e.ph["stealth"]:
		al = 0.8
	var fly: bool = e.ph["fly"]
	var heading: Vector2 = game.map.heading_at(e.dist, fly)
	var side := enemy_canvas_side(e.genome, e.ph["fly"], e.boss) * _cs
	r = side * 0.30
	var spawn := _pop(clampf(e.dist / 0.5, 0.0, 1.0) * 0.38)

	# вид выбирают ключевые гены, а лёгкая подкраска сохраняет различимость вида.
	var tint := Color.WHITE.lerp(_enemy_color(g), 0.24)
	if st["chilled"]:
		tint = tint.lerp(Color("#9fdcff"), 0.35)
	elif st["scorched"]:
		tint = tint.lerp(Color("#ff9a5c"), 0.35)
	elif st["poisoned"]:
		tint = tint.lerp(Color("#7ddc5a"), 0.35)

	# тень
	draw_set_transform(p + Vector2(0, r * 0.85 + (9.0 * k if fly else 0.0)), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r * 0.95 * spawn, Color(0, 0, 0, 0.3 * al))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# лёгкое подпрыгивание дополняет покадровую походку из спрайт-листа.
	var bob := (-7.0 * k + sin(_time * 5.0 + e.id) * 2.5 * k) if fly else -absf(sin(e.dist * (7.0 + 3.0 * g["swift"]) + e.id)) * 2.4 * k
	var body := p + Vector2(0, bob)

	var custom_model := _enemy_visual_model(g, fly, e.boss)
	var enemy_mod := Color(tint.r, tint.g, tint.b, al)
	if not custom_model.is_empty():
		var gait_speed := 12.0 if fly else 10.0 + 3.0 * float(g["swift"])
		var phase := _time * gait_speed + e.id * 1.7
		if e.warded:
			# Four offset copies produce a silhouette rim, never a radius circle.
			for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_draw_custom_enemy(custom_model, body + offset * maxf(1.0, _cs / 64.0), side * spawn, heading, Color(0.45, 0.80, 1.0, 0.45 * al), phase, fly, e.hit_flash, -1.0, true)
		if e.lured_gene != "":
			# золотая кайма по силуэту: враг усилен приманкой (щит рисуется голубой каймой)
			for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				_draw_custom_enemy(custom_model, body + offset * maxf(1.0, _cs / 64.0), side * spawn, heading, Color(1.0, 0.82, 0.30, 0.55 * al), phase, fly, e.hit_flash, -1.0, true)
		_draw_custom_enemy(custom_model, body, side * spawn, heading, enemy_mod, phase, fly, e.hit_flash)

	if e.ph.get("ward", false):
		_icon("gene-ward", Color(0.55, 0.85, 1.0, 0.8 * al), body + Vector2(side * 0.24, -side * 0.24), _cs * 0.16)
	if e == hovered_enemy:
		# Small corner marker replaces a circle around the creature.
		draw_line(body + Vector2(-r, r), body + Vector2(-r, r - 4 * k), Color.WHITE, 1.0)
		draw_line(body + Vector2(-r, r), body + Vector2(-r + 4 * k, r), Color.WHITE, 1.0)

	var wbar := _cs * (0.85 if e.boss else 0.44)
	var by := maxf(3.0, body.y - side * 0.55)
	var show_hp := e.boss or e.hp < float(e.ph["hp"]) - 0.001
	if show_hp:
		var frac: float = clampf(e.hp / e.ph["hp"], 0.0, 1.0)
		var height := maxf(2.0, _cs * 0.04)
		draw_rect(Rect2(body.x - wbar * 0.5 - 1, by - 1, wbar + 2, height + 2), Color(0, 0, 0, 0.7))
		var hc := Color("#6fd36f") if frac > 0.5 else (Color("#e8c04a") if frac > 0.25 else Color("#e8604a"))
		draw_rect(Rect2(body.x - wbar * 0.5, by, wbar * frac, height), hc)
		if e.boss and e.shield_max > 0.0:
			var sf: float = clampf(e.shield / e.shield_max, 0.0, 1.0)
			draw_rect(Rect2(body.x - wbar * 0.5, by - height - 2, wbar, height), Color("#243447"))
			draw_rect(Rect2(body.x - wbar * 0.5, by - height - 2, wbar * sf, height), Color("#6ab7ff"))

	var marks: Array = []
	if st["chilled"]:
		marks.append(["st-frozen", Color("#9fdcff")])
	if st["scorched"]:
		marks.append(["st-burn", Color("#ff9a5c")])
	if st["poisoned"]:
		marks.append(["st-poison", Color("#7ddc5a")])
	for i in marks.size():
		_icon(marks[i][0], marks[i][1], Vector2(body.x + (i - (marks.size() - 1) / 2.0) * 9.0 * k, by - (7.0 * k if show_hp else 0.0)), 8.0 * k)


func _draw_text_fx() -> void:
	var font := TDUI.font_bold
	for f in game.fx:
		if f["text"] == "":
			continue
		var rise: float = (1.0 - f["t"] / FX_TEXT_LIFE) * 0.5
		var pos := Vector2(f["x1"] * _cs, (f["y1"] - rise) * _cs)
		var al := minf(1.0, f["t"] * 3.0)
		var col: Color = f["color"]
		draw_string_outline(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 15, 4, Color(0, 0, 0, 0.7 * al))
		draw_string(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 15, _a(col, al))


