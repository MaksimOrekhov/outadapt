class_name TDVfx
extends RefCounted
## Частицы и эффекты. Работает только на косметике: свой генератор случайных чисел,
## на симуляцию не влияет. Координаты в клетках, размеры в «пикселях при клетке 48».

## Через сколько секунд снаряд долетает до цели (с этим же сдвигом показываем попадание).
const DELAY := {
	"arrow": 0.10, "cannon": 0.26, "ember": 0.09, "frost": 0.11,
	"sniper": 0.04, "poison": 0.17, "flak": 0.12, "tesla": 0.02, "net": 0.12,
}
const MAX_PARTS := 1600

var parts: Array[Dictionary] = []
var glows: Array[Dictionary] = []
var shake: float = 0.0
var flash: float = 0.0
var flash_col: Color = Color.WHITE
var cs: float = 56.0
var time: float = 0.0
var rng := RandomNumberGenerator.new()
var motes: Array[Dictionary] = []
## Источники света (аддитивные): [{p, size, col, flick, ph}], заполняет поле каждый кадр.
var lights: Array = []
## Погода биома: листопад, снег, дождь, пепел или пыль.
var ambient: String = ""
var ambient_cols: Array = []
var ambient_rate: float = 0.0
var _amb_acc: float = 0.0
var _acc := {"portal": 0.0, "castle": 0.0}
var _ring_t: Dictionary = {}


func _init() -> void:
	rng.randomize()


func clear() -> void:
	parts.clear()
	glows.clear()
	shake = 0.0
	flash = 0.0
	motes.clear()


func _r(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


## Добавляет частицу. glow=true — в аддитивный слой (свечение, искры).
func add(d: Dictionary, glow: bool = false) -> void:
	if parts.size() + glows.size() > MAX_PARTS:
		return
	var base := {"delay": 0.0, "drag": 0.0, "grav": 0.0, "grow": 0.0, "v": Vector2.ZERO, "size": 3.0, "kind": "dot", "life": 0.5}
	for k in base:
		if not d.has(k):
			d[k] = base[k]
	d["t"] = d["life"]
	if glow:
		glows.append(d)
	else:
		parts.append(d)


# ── обновление ────────────────────────────────────────────────

func update(dt: float) -> void:
	time += dt
	shake = maxf(0.0, shake - dt * 2.2)
	flash = maxf(0.0, flash - dt * 2.6)
	_step(parts, dt)
	_step(glows, dt)


func _step(list: Array[Dictionary], dt: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		var p: Dictionary = list[i]
		if p["delay"] > 0.0:
			p["delay"] -= dt
			i -= 1
			continue
		p["t"] -= dt
		if p["t"] <= 0.0:
			list.remove_at(i)
			i -= 1
			continue
		if p["kind"] == "orbit":
			p["ang"] += p["w"] * dt
			p["rad"] = maxf(0.02, p["rad"] + p["rad_v"] * dt)
			p["c"] = p["c"] + Vector2(0, -p.get("rise", 0.0) * dt)
			p["p"] = p["c"] + _dir(p["ang"]) * p["rad"]
		elif p.has("p"):
			var v: Vector2 = p["v"]
			if p["kind"] == "leaf" or p["kind"] == "flake":
				var age: float = p["life"] - p["t"]
				v.x = p["vx0"] + sin(p["ph"] + age * (2.2 if p["kind"] == "leaf" else 1.3)) * (0.55 if p["kind"] == "leaf" else 0.25)
				p["rot"] = p.get("rot", 0.0) + p.get("rot_v", 0.0) * dt
				if p["p"].y > TDConfig.ROWS + 0.5:
					p["t"] = 0.0
			v.y += p["grav"] * dt
			v *= maxf(0.0, 1.0 - p["drag"] * dt)
			p["v"] = v
			p["p"] += v * dt
		p["size"] += p["grow"] * dt
		i -= 1


# ── события симуляции ────────────────────────────────────────

func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		"shot":
			_shot(ev)
		"hit":
			_hit(ev)
		"death":
			_death(ev)
		"leak":
			_leak(ev)
		"sell":
			_sell(ev)
		"upgrade":
			_upgrade(ev)
		"split":
			_split_fx(ev)


func _shot(ev: Dictionary) -> void:
	var kind: String = ev["kind"]
	# Physical arrow sprites and their impacts are rendered once by the board.
	if kind in ["arrow", "flak", "sniper", "net"] and TDArt.tower_level(kind, int(ev.get("level", 1))).get("projectile", {}).get("custom", false):
		return
	var from: Vector2 = ev["from"]
	var to: Vector2 = ev["to"]
	var col: Color = ev["color"]
	var d: float = DELAY.get(kind, 0.1)
	var dir := (to - from).normalized()
	var dist := from.distance_to(to)
	# вспышка у дула (у прыжка молнии дула нет)
	var hop: bool = ev.get("hop", false)
	var muzzle := from if hop else from + dir * 0.34
	if not hop:
		add({"kind": "glow", "p": muzzle, "size": 30.0 if kind == "cannon" else 20.0, "life": 0.14, "col": col}, true)
		for i in (7 if kind == "cannon" else 3):
			add({"kind": "spark", "p": muzzle, "v": dir.rotated(_r(-0.5, 0.5)) * _r(2.0, 5.0), "drag": 4.0, "life": _r(0.1, 0.22), "size": 2.0, "col": col.lightened(0.4)}, true)
	match kind:
		"arrow":
			add({"kind": "tracer", "a": from + dir * 0.3, "b": to, "life": d, "col": Color("#fff1c4"), "width": 1.6, "len": 0.55}, true)
			_impact_sparks(to, col, 5, d)
		"cannon":
			add({"kind": "ball", "a": from + dir * 0.3, "b": to, "life": d, "col": Color("#2b303c"), "size": 5.5, "arc": 0.5})
			add({"kind": "ball", "a": from + dir * 0.3, "b": to, "life": d, "col": Color("#ffb347"), "size": 9.0, "arc": 0.5, "fade": true}, true)
			_explosion(to, ev["splash"], d)
		"ember":
			for i in 7:
				var spread := _r(-0.18, 0.18)
				add({"kind": "dot", "p": from + dir * 0.3, "v": (dir.rotated(spread)) * (dist / d) * _r(0.9, 1.1), "life": d * _r(0.8, 1.05), "size": _r(3.5, 6.0),
					"col": Color("#ff8a3c").lerp(Color("#ffd35a"), _r(0, 1)), "delay": _r(0.0, d * 0.35), "grow": -3.0}, true)
			_burst_fire(to, d, 6)
		"frost":
			add({"kind": "tracer", "a": from + dir * 0.3, "b": to, "life": d, "col": Color("#bfeaff"), "width": 2.4, "len": 0.7}, true)
			for i in 5:
				add({"kind": "dot", "p": from + dir * 0.35, "v": dir.rotated(_r(-0.35, 0.35)) * (dist / d) * _r(0.6, 0.95), "life": d * 0.9, "size": _r(1.6, 2.8), "col": Color("#e8f8ff"), "delay": _r(0.0, d * 0.4)}, true)
			_burst_ice(to, d, 6)
		"sniper":
			add({"kind": "tracer", "a": from + dir * 0.3, "b": to, "life": 0.16, "col": Color("#f1e3ff"), "width": 2.2, "len": dist}, true)
			add({"kind": "tracer", "a": from + dir * 0.3, "b": to, "life": 0.22, "col": _a(col, 0.5), "width": 6.0, "len": dist}, true)
			add({"kind": "ring", "p": to, "r0": 0.05, "r1": 0.55, "life": 0.28, "col": Color("#e6d3ff"), "width": 2.0, "delay": d}, true)
			_impact_sparks(to, col, 8, d)
			shake = maxf(shake, 0.12)
		"poison":
			add({"kind": "ball", "a": from + dir * 0.3, "b": to, "life": d, "col": Color("#7ddc5a"), "size": 5.0, "arc": 0.35}, true)
			_burst_poison(to, d, 7)
		"tesla":
			_lightning(muzzle, to, col)
		"flak":
			for o in [Vector2.ZERO, dir.orthogonal() * 0.08, -dir.orthogonal() * 0.08]:
				add({"kind": "tracer", "a": from + dir * 0.3 + o, "b": to + o, "life": d, "col": Color("#ffe29a"), "width": 1.6, "len": 0.5}, true)
			_explosion(to, ev["splash"], d, true)


static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## Молния: ломаная из коротких трассеров, яркая середина и мягкое свечение.
func _lightning(a: Vector2, b: Vector2, col: Color) -> void:
	var n := 6
	var pts: Array[Vector2] = [a]
	var nrm := (b - a).normalized().orthogonal()
	for i in range(1, n):
		pts.append(a.lerp(b, float(i) / n) + nrm * _r(-0.16, 0.16))
	pts.append(b)
	for i in n:
		var seg_len := pts[i].distance_to(pts[i + 1])
		add({"kind": "tracer", "a": pts[i], "b": pts[i + 1], "life": 0.14, "col": _a(col, 0.45), "width": 5.0, "len": seg_len}, true)
		add({"kind": "tracer", "a": pts[i], "b": pts[i + 1], "life": 0.12, "col": Color("#f4fdff"), "width": 1.8, "len": seg_len}, true)
	add({"kind": "glow", "p": b, "size": 34.0, "life": 0.18, "col": col}, true)
	_impact_sparks(b, col, 5, 0.0)


func _split_fx(ev: Dictionary) -> void:
	var at: Vector2 = ev["pos"]
	add({"kind": "ring", "p": at, "r0": 0.1, "r1": 0.7, "life": 0.35, "col": Color("#e08af0"), "width": 2.5}, true)
	for i in 8:
		add({"kind": "spark", "p": at, "v": _dir(_r(0, TAU)) * _r(1.0, 2.6), "drag": 3.0, "life": _r(0.25, 0.45), "size": 2.2, "col": Color("#f2c4ff")}, true)


func _impact_sparks(at: Vector2, col: Color, n: int, delay: float) -> void:
	add({"kind": "glow", "p": at, "size": 16.0, "life": 0.14, "col": col.lightened(0.3), "delay": delay}, true)
	for i in n:
		add({"kind": "spark", "p": at, "v": _dir(_r(0, TAU)) * _r(2.0, 5.5), "drag": 5.0, "life": _r(0.12, 0.3), "size": 1.8, "col": col.lightened(0.5), "delay": delay}, true)


func _explosion(at: Vector2, radius: float, delay: float, small: bool = false) -> void:
	var k := 0.6 if small else 1.0
	add({"kind": "glow", "p": at, "size": 70.0 * radius * k, "life": 0.28, "col": Color("#ffb04a"), "delay": delay}, true)
	add({"kind": "glow", "p": at, "size": 36.0 * radius * k, "life": 0.18, "col": Color("#fff2c8"), "delay": delay}, true)
	add({"kind": "ring", "p": at, "r0": 0.08, "r1": radius, "life": 0.34, "col": Color("#ffd28a"), "width": 3.0, "delay": delay}, true)
	for i in int(16 * k):
		add({"kind": "spark", "p": at, "v": _dir(_r(0, TAU)) * _r(1.5, 4.5) * radius, "drag": 3.0, "grav": 1.5, "life": _r(0.25, 0.55), "size": 2.2, "col": Color("#ffc070").lerp(Color("#ff6a2a"), _r(0, 1)), "delay": delay}, true)
	for i in int(7 * k):
		add({"kind": "smoke", "p": at + _dir(_r(0, TAU)) * _r(0.0, 0.3) * radius, "v": Vector2(_r(-0.3, 0.3), _r(-0.6, -0.2)), "drag": 1.0, "life": _r(0.6, 1.0), "size": _r(8.0, 14.0), "grow": 22.0, "col": Color("#3a3d48"), "delay": delay})
	if not small:
		add({"kind": "scorch", "p": at, "size": 22.0 * radius, "life": 2.5, "col": Color("#000000"), "delay": delay})
		shake = maxf(shake, 0.30)


func _burst_fire(at: Vector2, delay: float, n: int) -> void:
	add({"kind": "glow", "p": at, "size": 28.0, "life": 0.22, "col": Color("#ff7a2a"), "delay": delay}, true)
	for i in n:
		add({"kind": "dot", "p": at + _dir(_r(0, TAU)) * 0.08, "v": Vector2(_r(-0.5, 0.5), _r(-1.8, -0.6)), "drag": 1.2, "life": _r(0.3, 0.6), "size": _r(3.5, 6.0), "grow": -6.0,
			"col": Color("#ff8a3c").lerp(Color("#ffd35a"), _r(0, 1)), "delay": delay}, true)


func _burst_ice(at: Vector2, delay: float, n: int) -> void:
	add({"kind": "glow", "p": at, "size": 26.0, "life": 0.22, "col": Color("#7fd0ff"), "delay": delay}, true)
	add({"kind": "ring", "p": at, "r0": 0.05, "r1": 0.5, "life": 0.3, "col": Color("#bfeaff"), "width": 2.0, "delay": delay}, true)
	for i in n:
		add({"kind": "shard", "p": at, "v": _dir(_r(0, TAU)) * _r(1.0, 3.0), "drag": 3.0, "life": _r(0.3, 0.55), "size": _r(3.0, 5.0), "rot": _r(0, TAU), "col": Color("#cdefff"), "delay": delay}, true)


func _burst_poison(at: Vector2, delay: float, n: int) -> void:
	add({"kind": "glow", "p": at, "size": 30.0, "life": 0.4, "col": Color("#6ad040"), "delay": delay}, true)
	for i in n:
		add({"kind": "bubble", "p": at + _dir(_r(0, TAU)) * _r(0.0, 0.25), "v": Vector2(_r(-0.25, 0.25), _r(-1.0, -0.35)), "life": _r(0.5, 0.9), "size": _r(3.0, 6.0), "col": Color("#8be86a"), "delay": delay})


func _hit(ev: Dictionary) -> void:
	var kind: String = ev["kind"]
	var delay: float = DELAY.get(kind, 0.1)
	var at: Vector2 = ev["pos"]
	var dmg: float = ev["dmg"]
	if dmg >= 14.0 and not ev["boosted"]:
		add({"kind": "text", "p": at + Vector2(_r(-0.1, 0.1), -0.32), "v": Vector2(0, -0.9), "drag": 1.5, "life": 0.55, "text": str(int(round(dmg))), "col": Color("#ffffff"), "size": 13.0, "delay": delay})
	match ev["dtype"]:
		"fire":
			for i in 2:
				add({"kind": "dot", "p": at + _dir(_r(0, TAU)) * 0.1, "v": Vector2(_r(-0.4, 0.4), _r(-1.4, -0.6)), "life": _r(0.25, 0.45), "size": _r(2.5, 4.5), "grow": -5.0, "col": Color("#ff9a4a"), "delay": delay}, true)
		"frost":
			add({"kind": "ring", "p": at, "r0": 0.05, "r1": 0.32, "life": 0.25, "col": Color("#bfeaff"), "width": 1.6, "delay": delay}, true)


func _death(ev: Dictionary) -> void:
	var at: Vector2 = ev["pos"]
	var boss: bool = ev["boss"]
	var delay: float = DELAY.get(ev["kind"], 0.0) if ev["kind"] != "poison" else 0.0
	var col := _genome_color(ev["genome"], boss)
	var n: int = 30 if boss else int(9 + ev["size"] * 14.0)
	add({"kind": "glow", "p": at, "size": 80.0 if boss else 34.0, "life": 0.3, "col": col, "delay": delay}, true)
	add({"kind": "ring", "p": at, "r0": 0.1, "r1": 1.6 if boss else 0.55, "life": 0.5 if boss else 0.32, "col": col.lightened(0.3), "width": 3.0 if boss else 2.0, "delay": delay}, true)
	for i in n:
		add({"kind": "dot", "p": at, "v": _dir(_r(0, TAU)) * _r(0.8, 3.2 if not boss else 5.0), "drag": 2.5, "grav": 2.0, "life": _r(0.35, 0.8), "size": _r(2.5, 5.0 if not boss else 8.0), "grow": -3.0, "col": col.lerp(Color.WHITE, _r(0, 0.5)), "delay": delay}, true)
	for i in (3 if not boss else 12):
		add({"kind": "smoke", "p": at + _dir(_r(0, TAU)) * 0.1, "v": Vector2(_r(-0.2, 0.2), _r(-0.7, -0.25)), "drag": 1.0, "life": _r(0.5, 0.9), "size": _r(6.0, 10.0), "grow": 18.0, "col": Color("#2c303c"), "delay": delay})
	# золото
	add({"kind": "text", "p": at + Vector2(0, -0.2), "v": Vector2(0, -0.7), "drag": 0.8, "life": 0.95 if not boss else 1.6, "text": "+%d" % ev["gold"], "col": Color("#ffd35a"), "size": 15.0 if not boss else 24.0, "icon": "coin", "delay": delay + 0.05})
	if boss:
		shake = 1.0
		flash = 0.5
		flash_col = Color("#ffe8b0")


func _genome_color(g: Dictionary, boss: bool) -> Color:
	if boss:
		return Color("#ff6b7a")
	var best := Color("#9aa7bd")
	var best_v := 0.3
	for t in TDBoard.TRAITS:
		if g[t[0]] > best_v:
			best_v = g[t[0]]
			best = Color(t[1])
	return best


func _leak(ev: Dictionary) -> void:
	var at: Vector2 = ev["pos"]
	var boss: bool = ev["boss"]
	shake = maxf(shake, 0.9 if boss else 0.55)
	flash = 0.45 if boss else 0.28
	flash_col = Color("#ff3b4a")
	add({"kind": "ring", "p": at, "r0": 0.2, "r1": 1.4, "life": 0.5, "col": Color("#ff6b7a"), "width": 3.0}, true)
	add({"kind": "glow", "p": at, "size": 90.0, "life": 0.4, "col": Color("#ff3b4a")}, true)
	add({"kind": "text", "p": at + Vector2(-0.4, -0.5), "v": Vector2(0, -0.9), "drag": 0.8, "life": 1.1, "text": "−%d" % (TDConfig.BOSS_LEAK if boss else 1), "col": Color("#ff6b7a"), "size": 22.0, "icon": "lives"})


## Улучшение: столб света, искры закручиваются вокруг башни и уходят вверх, вспышка, надпись.
func _upgrade(ev: Dictionary) -> void:
	var at: Vector2 = ev["pos"] + Vector2(0, 0.3)
	var col := Color(TDConfig.TOWERS[ev["kind"]]["color"])
	var gold := Color("#ffd35a")
	var lv: int = ev["level"]
	var main := gold if lv >= 3 else col.lerp(Color.WHITE, 0.35)
	add({"kind": "beam", "p": at, "w": 0.9 if lv >= 3 else 0.7, "h": 3.2 if lv >= 3 else 2.4, "life": 0.9, "col": main}, true)
	add({"kind": "glow", "p": at + Vector2(0, -0.3), "size": 110.0 if lv >= 3 else 80.0, "life": 0.5, "col": main}, true)
	var n := 26 if lv >= 3 else 16
	for i in n:
		add({"kind": "orbit", "c": at + Vector2(0, -_r(0.0, 0.3)), "ang": i * TAU / n, "w": 6.0, "rad": 0.55, "rad_v": -0.35, "rise": _r(1.2, 2.2),
			"p": at, "life": _r(0.6, 0.95), "size": _r(1.6, 2.6), "col": main.lightened(0.3)}, true)
	for i in 10:
		add({"kind": "spark", "p": at, "v": Vector2(_r(-1.6, 1.6), _r(-2.5, -0.5)), "drag": 3.0, "life": _r(0.3, 0.55), "size": 1.8, "col": main.lightened(0.5)}, true)
	for i in 8:
		var a := _r(0, TAU)
		add({"kind": "smoke", "p": at + _dir(a) * 0.35, "v": _dir(a) * _r(0.3, 0.8), "drag": 3.0, "life": _r(0.3, 0.5), "size": _r(4.0, 6.0), "grow": 8.0, "col": Color("#8a8f9e")})
	var name: String = ev.get("branch_name", "")
	var txt := ("Уровень %d" % lv) if name == "" else name
	add({"kind": "text", "p": at + Vector2(0, -1.1), "v": Vector2(0, -0.5), "drag": 0.8, "life": 1.3, "text": txt, "col": gold, "size": 17.0})
	shake = maxf(shake, 0.3 if lv >= 3 else 0.2)


func _sell(ev: Dictionary) -> void:
	var at: Vector2 = ev["pos"]
	for i in 5:
		add({"kind": "coin", "p": at, "v": Vector2(_r(-1.2, 1.2), _r(-2.8, -1.4)), "grav": 7.0, "life": _r(0.55, 0.85), "size": _r(8.0, 11.0), "rot": _r(0, TAU), "col": Color("#ffd35a")})
	add({"kind": "text", "p": at + Vector2(0, -0.3), "v": Vector2(0, -0.8), "drag": 0.8, "life": 1.0, "text": "+%d" % ev["gain"], "col": Color("#ffd35a"), "size": 16.0, "icon": "coin"})
	for i in 7:
		var a := _r(0, TAU)
		add({"kind": "smoke", "p": at, "v": _dir(a) * _r(0.5, 1.3), "drag": 3.0, "life": _r(0.3, 0.5), "size": _r(4.0, 7.0), "grow": 10.0, "col": Color("#6d7385")})


# ── непрерывные эффекты ──────────────────────────────────────

func update_world(dt: float, g: TDGame) -> void:
	# статусы на врагах
	for e in g.enemies:
		var p := g.pos_of(e)
		if e.ph["fly"]:
			p.y -= 0.15
		if e.scorch_t > 0.0 and _r(0, 1) < dt * 16.0:
			add({"kind": "dot", "p": p + Vector2(_r(-0.15, 0.15), 0.05), "v": Vector2(_r(-0.2, 0.2), _r(-1.3, -0.7)), "life": _r(0.3, 0.55), "size": _r(2.5, 4.5), "grow": -4.0, "col": Color("#ff8a3c").lerp(Color("#ffd35a"), _r(0, 1))}, true)
		if e.slow_t > 0.0 and _r(0, 1) < dt * 9.0:
			add({"kind": "shard", "p": p + Vector2(_r(-0.2, 0.2), _r(-0.2, 0.15)), "v": Vector2(0, 0.25), "life": _r(0.4, 0.7), "size": _r(2.5, 4.0), "rot": _r(0, TAU), "col": Color("#d6f2ff")}, true)
		if e.poison_t > 0.0 and _r(0, 1) < dt * 8.0:
			add({"kind": "bubble", "p": p + Vector2(_r(-0.15, 0.15), _r(-0.1, 0.1)), "v": Vector2(_r(-0.1, 0.1), _r(-0.9, -0.4)), "life": _r(0.4, 0.8), "size": _r(2.5, 4.5), "col": Color("#8be86a")})
		if e.ph["regen"] > 0.0 and e.hp < e.ph["hp"] and _r(0, 1) < dt * 4.0:
			add({"kind": "plus", "p": p + Vector2(_r(-0.2, 0.2), -0.1), "v": Vector2(0, -0.7), "life": 0.6, "size": 5.0, "col": Color("#7ddc5a")})
		if e.boss and _r(0, 1) < dt * 22.0:
			add({"kind": "dot", "p": p + _dir(_r(0, TAU)) * _r(0.2, 0.5), "v": Vector2(_r(-0.3, 0.3), _r(-1.0, -0.3)), "life": _r(0.4, 0.8), "size": _r(2.5, 5.0), "grow": -3.0, "col": Color("#ff4a5a")}, true)
	# постоянные эффекты башен
	for t in g.towers:
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		match t.kind:
			"ember":
				if _r(0, 1) < dt * 7.0:
					add({"kind": "dot", "p": c + Vector2(_r(-0.12, 0.12), -0.05), "v": Vector2(_r(-0.1, 0.1), _r(-0.9, -0.5)), "life": _r(0.4, 0.7), "size": _r(2.0, 3.5), "grow": -3.0, "col": Color("#ff9a4a")}, true)
			"frost":
				if _r(0, 1) < dt * 3.5:
					add({"kind": "shard", "p": c + _dir(_r(0, TAU)) * 0.3, "v": Vector2(0, 0.2), "life": _r(0.5, 0.9), "size": _r(2.0, 3.2), "rot": _r(0, TAU), "col": Color("#d6f2ff")}, true)
			"poison":
				if _r(0, 1) < dt * 3.5:
					add({"kind": "bubble", "p": c + _dir(_r(0, TAU)) * 0.25, "v": Vector2(0, -0.5), "life": _r(0.5, 0.9), "size": _r(2.0, 3.5), "col": Color("#8be86a")})
			"beacon":
				_ring_t[t.id] = float(_ring_t.get(t.id, 0.0)) - dt
				if _ring_t[t.id] <= 0.0:
					_ring_t[t.id] = 1.8
					pass
	# портал и замок
	var pts := g.map.points
	_acc["castle"] += dt * 5.0
	while _acc["castle"] >= 1.0:
		_acc["castle"] -= 1.0
		var ce: Vector2 = pts[pts.size() - 1]
		add({"kind": "dot", "p": ce + Vector2(_r(-0.3, 0.3), _r(-0.1, 0.2)), "v": Vector2(_r(-0.1, 0.1), _r(-0.7, -0.3)), "life": _r(0.7, 1.3), "size": _r(1.8, 3.0), "grow": -1.5, "col": Color("#ff6b7a")}, true)
	# погода биома
	if ambient != "" and ambient_rate > 0.0:
		_amb_acc += dt * ambient_rate
		while _amb_acc >= 1.0:
			_amb_acc -= 1.0
			var col: Color = Color(ambient_cols[rng.randi() % ambient_cols.size()])
			match ambient:
				"leaf":
					add({"kind": "leaf", "p": Vector2(_r(-1.0, TDConfig.COLS), -0.4), "v": Vector2(0.4, _r(0.45, 0.8)), "vx0": _r(0.2, 0.7), "ph": _r(0, TAU), "rot": _r(0, TAU), "rot_v": _r(-3.0, 3.0), "size": _r(3.5, 5.5), "col": col, "life": 14.0})
				"snow":
					add({"kind": "flake", "p": Vector2(_r(-1.0, TDConfig.COLS + 1.0), -0.3), "v": Vector2(0.0, _r(0.6, 1.2)), "vx0": _r(-0.1, 0.25), "ph": _r(0, TAU), "size": _r(1.4, 2.8), "col": col, "life": 14.0})
				"spore":
					add({"kind": "spore", "p": Vector2(_r(0, TDConfig.COLS), _r(0, TDConfig.ROWS)), "v": Vector2(_r(-0.1, 0.1), _r(-0.35, -0.12)), "size": _r(1.6, 3.0), "col": col, "life": _r(4.0, 7.0)}, true)
				"rain":
					add({"kind": "rain", "p": Vector2(_r(-0.5, TDConfig.COLS), _r(-0.5, TDConfig.ROWS)), "v": Vector2(-0.8, _r(5.0, 7.0)), "size": _r(3.0, 5.5), "col": col, "life": _r(1.5, 2.5)})
				"ash":
					add({"kind": "ash", "p": Vector2(_r(-0.5, TDConfig.COLS), -0.4), "v": Vector2(_r(-0.25, 0.25), _r(0.35, 0.9)), "size": _r(1.5, 2.8), "rot": _r(0.0, TAU), "col": col, "life": _r(8.0, 13.0)})
				"dust":
					add({"kind": "dust", "p": Vector2(_r(0, TDConfig.COLS), _r(0, TDConfig.ROWS)), "v": Vector2(_r(-0.08, 0.08), _r(-0.14, -0.04)), "size": _r(1.0, 2.1), "col": col, "life": _r(4.0, 7.0)})
	# пылинки-светлячки
	if motes.is_empty():
		for i in 8:
			motes.append({"p": Vector2(_r(0, TDConfig.COLS), _r(0, TDConfig.ROWS)), "ph": _r(0, TAU), "sp": _r(0.2, 0.6), "sz": _r(1.2, 2.4)})
	for m in motes:
		m["p"] += Vector2(sin(time * 0.4 + m["ph"]) * 0.18, -m["sp"] * 0.25) * dt
		if m["p"].y < -0.3:
			m["p"] = Vector2(_r(0, TDConfig.COLS), TDConfig.ROWS + 0.3)


# ── рисование ─────────────────────────────────────────────────

func draw_normal(ci: CanvasItem) -> void:
	var k := cs / 48.0
	for p in parts:
		if p["delay"] > 0.0:
			continue
		var frac: float = clampf(p["t"] / p["life"], 0.0, 1.0)
		var pos: Vector2 = p["p"] * cs if p.has("p") else Vector2.ZERO
		var col: Color = p["col"]
		match p["kind"]:
			"smoke":
				ci.draw_circle(pos, maxf(0.5, p["size"] * k), TDVfx._a(col, 0.42 * frac))
			"scorch":
				ci.draw_circle(pos, p["size"] * k, TDVfx._a(col, 0.28 * minf(1.0, frac * 3.0)))
			"bubble":
				var r: float = p["size"] * k
				ci.draw_circle(pos, r, TDVfx._a(col, 0.25 * frac))
				ci.draw_arc(pos, r, 0.0, TAU, 12, TDVfx._a(col.lightened(0.3), 0.9 * frac), 1.2, true)
			"ball":
				var q := _ball_pos(p)
				var r2: float = p["size"] * k
				ci.draw_circle(q + Vector2(0, 8.0 * k * sin(PI * (1.0 - frac))), r2 * 0.8, Color(0, 0, 0, 0.25))
				ci.draw_circle(q, r2, col)
				ci.draw_circle(q - Vector2(r2 * 0.3, r2 * 0.3), r2 * 0.35, TDVfx._a(Color.WHITE, 0.25))
			"coin":
				var tex := TDIcons.tex("coin")
				var s: float = p["size"] * k
				ci.draw_set_transform(pos, p["rot"] + (1.0 - frac) * 9.0, Vector2.ONE)
				ci.draw_texture_rect(tex, Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), false, TDVfx._a(col, minf(1.0, frac * 2.5)))
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"text":
				var rise_alpha := minf(1.0, frac * 2.5)
				var font := TDUI.font_bold
				var sz := int(p["size"] * k)
				var txt: String = p["text"]
				var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
				var x0 := pos.x - w * 0.5
				if p.has("icon"):
					x0 -= 7.0 * k
					ci.draw_texture_rect(TDIcons.tex(p["icon"]), Rect2(Vector2(x0, pos.y - sz * 0.85), Vector2(sz * 0.9, sz * 0.9)), false, TDVfx._a(col, rise_alpha))
					x0 += sz
				else:
					x0 = pos.x - w * 0.5
				var tp := Vector2(x0, pos.y)
				ci.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.75 * rise_alpha))
				ci.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, TDVfx._a(col, rise_alpha))
			"leaf":
				var lr: float = p["size"] * k
				var ca: float = cos(p["rot"])
				var sa: float = sin(p["rot"])
				var pts := PackedVector2Array()
				for q in [Vector2(-1.0, 0.0), Vector2(-0.5, -0.55), Vector2(0.5, -0.55), Vector2(1.0, 0.0), Vector2(0.5, 0.55), Vector2(-0.5, 0.55)]:
					pts.append(pos + Vector2(q.x * ca - q.y * sa * (0.5 + 0.5 * sin(p["rot"] * 1.7)), q.x * sa + q.y * ca) * lr)
				ci.draw_colored_polygon(pts, TDVfx._a(col, 0.9 * minf(1.0, frac * 4.0)))
			"flake":
				ci.draw_circle(pos, p["size"] * k, TDVfx._a(col, 0.85 * minf(1.0, frac * 5.0)))
			"rain":
				var length: float = float(p["size"]) * k
				ci.draw_line(pos, pos + Vector2(-0.7, length), TDVfx._a(col, 0.52 * minf(1.0, frac * 4.0)), maxf(0.7, k))
			"ash":
				var ash_size: float = float(p["size"]) * k
				var ash_points := PackedVector2Array([pos + Vector2(0, -ash_size), pos + Vector2(ash_size * 0.65, 0), pos + Vector2(0, ash_size), pos + Vector2(-ash_size * 0.65, 0)])
				ci.draw_colored_polygon(ash_points, TDVfx._a(col, 0.75 * minf(1.0, frac * 4.0)))
			"dust":
				ci.draw_circle(pos, maxf(0.4, p["size"] * k * frac), TDVfx._a(col, 0.32 * minf(1.0, frac * 3.0)))
			"plus":
				var s2: float = p["size"] * k
				var c2 := TDVfx._a(col, frac)
				ci.draw_line(pos - Vector2(s2, 0), pos + Vector2(s2, 0), c2, 2.0)
				ci.draw_line(pos - Vector2(0, s2), pos + Vector2(0, s2), c2, 2.0)
			_:
				ci.draw_circle(pos, maxf(0.4, p["size"] * k * frac), TDVfx._a(col, frac))


func _ball_pos(p: Dictionary) -> Vector2:
	var prog: float = 1.0 - clampf(p["t"] / p["life"], 0.0, 1.0)
	var a: Vector2 = p["a"]
	var b: Vector2 = p["b"]
	var q := a.lerp(b, prog)
	var arc: float = p.get("arc", 0.0)
	q.y -= sin(PI * prog) * arc
	return q * cs


## Мягкое световое пятно: радиальный градиент без краёв (вместо вложенных кругов).
static var _soft_tex: Texture2D = null


static func _soft_glow(ci: CanvasItem, pos: Vector2, r: float, col: Color) -> void:
	if _soft_tex == null:
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = gr
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_soft_tex = gt
	ci.draw_texture_rect(_soft_tex, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


static func _soft_glow_rect(ci: CanvasItem, r: Rect2, col: Color) -> void:
	_soft_glow(ci, Vector2.ZERO, 1.0, Color(0, 0, 0, 0))
	ci.draw_texture_rect(_soft_tex, r, false, col)


func draw_add(ci: CanvasItem) -> void:
	var k := cs / 48.0
	# источники света
	for l in lights:
		var fl: float = 1.0 + l["flick"] * sin(time * 7.0 + l["ph"]) + l["flick"] * 0.5 * sin(time * 13.0 + l["ph"] * 2.0)
		var lc: Color = l["col"]
		var lp: Vector2 = l["p"] * cs
		var lr2: float = l["size"] * k * fl
		_soft_glow(ci, lp, lr2, TDVfx._a(lc, 0.22))
	# светлячки
	for m in motes:
		var tw := 0.5 + 0.5 * sin(time * 1.6 + m["ph"])
		ci.draw_circle(m["p"] * cs, m["sz"] * k, Color(0.7, 0.85, 1.0, 0.10 + 0.22 * tw))
	for p in glows:
		if p["delay"] > 0.0:
			continue
		var frac: float = clampf(p["t"] / p["life"], 0.0, 1.0)
		var col: Color = p["col"]
		var al: float = p.get("alpha", 1.0)
		match p["kind"]:
			"glow":
				var r: float = p["size"] * k * (0.6 + 0.6 * (1.0 - frac))
				var pos: Vector2 = p["p"] * cs
				_soft_glow(ci, pos, r, TDVfx._a(col, 0.32 * frac))
				ci.draw_circle(pos, r * 0.3, TDVfx._a(col, 0.30 * frac))
			"beam":
				# столб света: мягкий градиент, вытянутый вверх
				var bp: Vector2 = p["p"] * cs
				var bw: float = p["w"] * cs * (0.6 + 0.4 * frac)
				var bh: float = p["h"] * cs * (1.0 - 0.3 * frac)
				var a2 := sin(PI * minf(1.0, (1.0 - frac) * 1.6)) if frac > 0.4 else frac * 1.6
				_soft_glow_rect(ci, Rect2(bp.x - bw * 0.5, bp.y - bh, bw, bh * 1.15), TDVfx._a(col, 0.55 * a2))
				_soft_glow_rect(ci, Rect2(bp.x - bw * 0.18, bp.y - bh * 0.95, bw * 0.36, bh * 1.05), TDVfx._a(Color.WHITE, 0.45 * a2))
			"ring":
				var rr: float = lerpf(p["r0"], p["r1"], 1.0 - pow(frac, 2.0)) * cs
				ci.draw_arc(p["p"] * cs, rr, 0.0, TAU, 48, TDVfx._a(col, 0.85 * frac * al), p["width"] * k, true)
			"spark":
				var v: Vector2 = p["v"]
				var pos2: Vector2 = p["p"] * cs
				var tail := pos2 - v * 0.05 * cs
				ci.draw_line(tail, pos2, TDVfx._a(col, frac), maxf(1.0, p["size"] * k), true)
			"tracer":
				var prog: float = 1.0 - frac
				var a: Vector2 = p["a"] * cs
				var b: Vector2 = p["b"] * cs
				var head := a.lerp(b, minf(1.0, prog * 1.15))
				var length: float = p["len"] * cs
				var dirv := (b - a).normalized()
				var tail2 := head - dirv * minf(length, head.distance_to(a))
				ci.draw_line(tail2, head, TDVfx._a(col, 0.35), p["width"] * 2.6 * k, true)
				ci.draw_line(tail2, head, TDVfx._a(col, 1.0), p["width"] * k, true)
				ci.draw_circle(head, p["width"] * 1.4 * k, TDVfx._a(Color.WHITE, 0.8))
			"ball":
				var q := _ball_pos(p)
				var r3: float = p["size"] * k * 1.8
				ci.draw_circle(q, r3, TDVfx._a(col, 0.25))
				ci.draw_circle(q, r3 * 0.5, TDVfx._a(col, 0.6))
			"shard":
				var pos3: Vector2 = p["p"] * cs
				var s: float = p["size"] * k * (0.5 + 0.5 * frac)
				var ang: float = p["rot"]
				var d1 := Vector2(cos(ang), sin(ang)) * s
				var d2 := d1.orthogonal() * 0.45
				ci.draw_colored_polygon(PackedVector2Array([pos3 + d1, pos3 + d2, pos3 - d1, pos3 - d2]), TDVfx._a(col, frac))
			_:
				var pos4: Vector2 = p["p"] * cs
				var sz: float = maxf(0.4, p["size"] * k * (frac if p["kind"] == "dot" else 1.0))
				ci.draw_circle(pos4, sz * 1.8, TDVfx._a(col, 0.18 * frac))
				ci.draw_circle(pos4, sz, TDVfx._a(col, 0.9 * frac))
