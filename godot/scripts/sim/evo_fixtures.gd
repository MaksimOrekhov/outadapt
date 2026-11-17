class_name TDEvoFixtures
extends RefCounted
## PRO-191: воспроизводимые состояния роя для проверок и кадров интерфейса эволюции.
## Состояния не задаются руками: забег проходит настоящие концы волн (TDGame._end_wave → TDStrains.end_wave),
## а удары башен записываются в накопитель сигнатуры так же, как в бою. Подменяется только сам бой:
## все враги волны считаются убитыми, урон распределён по башням с заданными весами.
## Используется в tests/evo_ui_check.gd и в демо-кадрах (`-- --shot=... --ui=evo:<имя>[:swarm|:over]`).

const NAMES: Array[String] = ["quiet", "quiet_off", "wave7", "incubating", "announced", "appear_next", "active_hulk",
	"brood_next", "flock_next", "fading", "multi", "locked", "boss_off", "stealth_off", "armor_off", "defeat_hulk", "defeat_unknown"]


## Свободные клетки у дороги, по порядку пути (для расстановки башен).
static func road_cells(g: TDGame) -> Array:
	var out: Array = []
	var seen := {}
	for c in g.map.order:
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = c + d
			if seen.has(n) or n.x < 0 or n.y < 0 or n.x >= TDConfig.COLS or n.y >= TDConfig.ROWS:
				continue
			seen[n] = true
			if not g.map.cells.has(n) and not g.map.blocked.has(n):
				out.append(n)
	return out


## Поставить башни по кругу из kinds, равномерно вдоль дороги (from..to — доля пути).
static func place(g: TDGame, kinds: Array, from: float = 0.0, to: float = 1.0) -> void:
	var cells := road_cells(g)
	var a: int = int(cells.size() * from)
	var b: int = maxi(a + 1, int(cells.size() * to))
	var span: Array = cells.slice(a, b)
	var step: float = float(span.size()) / maxf(1.0, float(kinds.size()))
	for i in kinds.size():
		var start: int = int(i * step)
		for j in span.size():
			var c: Vector2i = span[(start + j) % span.size()]
			g.gold += 1000
			if g.place_tower(kinds[i], c.x, c.y):
				break


## Одна волна без боя: все враги убиты, урон по обычным врагам распределён по башням с весами weights {kind: вес}.
static func play_wave(g: TDGame, weights: Dictionary) -> void:
	g.start_wave()
	g.finished = []
	for i in g.wave_genomes.size():
		g.finished.append({"genome": g.wave_genomes[i], "fitness": float(g.wave_genomes.size() - i)})
	g.pending = []
	g.pending_boss = {}
	g.enemies.clear()
	g.killed = g.wave_genomes.size()
	g.damage_by = TDGame._zero_damage()
	var total := 1000.0 + 120.0 * g.wave
	var by_kind := {}
	for t in g.towers:
		if weights.has(t.kind):
			by_kind[t.kind] = int(by_kind.get(t.kind, 0)) + 1
	for t in g.towers:
		var w: float = float(weights.get(t.kind, 0.0))
		if w <= 0.0:
			continue
		var dealt: float = total * w / float(by_kind[t.kind])
		g.damage_by[t.kind] = float(g.damage_by.get(t.kind, 0.0)) + dealt
		if g.strains_on():
			var tp := Vector2(t.x + 0.5, t.y + 0.5)
			TDStrains.record_hit(g.strain_acc, t.def, t.kind, tp, tp + Vector2(1.5, 0.0), false, dealt, false)
			TDStrains.record_time(g.strain_acc, false, 1.0)
	g._end_wave()
	if not g.offer.is_empty():
		g.choose_perk(g.offer[0])


## По умолчанию закрыты те же башни, что у нового игрока без достижений (TDMeta.TOWER_UNLOCK): Сеть и Тесла.
const FIRST_RUN_LOCKED := ["net", "tesla"]


static func _new(on: bool, difficulty: String = "hard", locked: Array = FIRST_RUN_LOCKED, seed_v: int = 4243) -> TDGame:
	var meta := {"difficulty": difficulty}
	if on:
		meta["swarm_model"] = TDStrains.MODEL
	if not locked.is_empty():
		meta["locked"] = locked
	return TDGame.new(seed_v, null, meta)


## Играть волны, пока cond(g) не станет истинным (не больше limit волн).
static func _until(g: TDGame, weights: Dictionary, cond: Callable, limit: int = 30) -> TDGame:
	for _i in limit:
		if cond.call(g):
			return g
		play_wave(g, weights)
	return g


static func _phase(g: TDGame, p: String) -> String:
	return String(g.strains.get("pk", {}).get(p, {}).get("phase", "quiet"))


## Состояние по имени (см. NAMES). Неизвестное имя — пустой забег.
static func build(name: String) -> TDGame:
	var rapid := {"arrow": 0.75, "ember": 0.2, "frost": 0.05}
	var burst := {"sniper": 0.85, "arrow": 0.15}
	var mixed := {"arrow": 0.2, "cannon": 0.25, "frost": 0.1, "ember": 0.1, "sniper": 0.2, "poison": 0.15}
	var g: TDGame
	match name:
		"quiet", "quiet_off":
			g = _new(name == "quiet", "normal")
			# смешанная оборона с ПВО и Маяком; волна 16 — до ближайшего босса и нового признака больше двух волн
			place(g, ["arrow", "cannon", "frost", "ember", "sniper", "flak", "poison", "cannon", "flak", "beacon", "arrow", "sniper"])
			_until(g, mixed, func(x): return x.wave == 16)
		"wave7":
			# как на кадре первого живого плейтеста: оборона на лучниках и огне, hard, конец 7-й волны
			g = _new(true)
			place(g, ["arrow", "arrow", "ember", "arrow", "arrow", "frost", "arrow", "ember"], 0.0, 0.6)
			for _i in 7:
				play_wave(g, rapid)
		"incubating":
			g = _new(true, "normal")
			place(g, ["arrow", "arrow", "ember", "arrow", "cannon", "frost", "flak", "sniper"])
			_until(g, {"arrow": 0.62, "ember": 0.08, "cannon": 0.15, "sniper": 0.1, "frost": 0.05},
				func(x): return float(x.strains.get("pk", {}).get("hulk", {}).get("inc", 0.0)) >= TDThreats.MAYBE_MIN, 12)
		"announced":
			g = _new(true)
			place(g, ["arrow", "arrow", "ember", "arrow", "arrow", "frost", "flak", "arrow"])
			_until(g, rapid, func(x): return _phase(x, "hulk") == "announced")
		"appear_next":
			g = _new(true)
			place(g, ["arrow", "arrow", "ember", "arrow", "arrow", "frost", "flak", "arrow"])
			_until(g, rapid, func(x): return _phase(x, "hulk") == "active")
		"active_hulk":
			g = _new(true)
			place(g, ["arrow", "arrow", "ember", "arrow", "arrow", "frost", "flak", "arrow"])
			_until(g, rapid, func(x): return _phase(x, "hulk") == "active")
			play_wave(g, rapid)
			play_wave(g, rapid)
		"brood_next":
			g = _new(true)
			place(g, ["sniper", "sniper", "arrow", "sniper", "flak", "sniper"])
			_until(g, burst, func(x): return _phase(x, "brood") == "active")
		"flock_next":
			g = _new(true)
			place(g, ["cannon", "cannon", "poison", "cannon", "poison", "cannon"], 0.0, 0.5)
			_until(g, {"cannon": 0.75, "poison": 0.25}, func(x): return _phase(x, "flock") == "active")
		"fading":
			g = _new(true)
			place(g, ["arrow", "arrow", "ember", "arrow", "arrow", "frost", "flak", "arrow", "sniper", "cannon", "cannon", "poison"])
			_until(g, rapid, func(x): return _phase(x, "hulk") == "active")
			_until(g, {"sniper": 0.35, "cannon": 0.4, "poison": 0.25}, func(x): return _phase(x, "hulk") == "fading", 8)
		"multi":
			g = _new(true)
			place(g, ["sniper", "sniper", "cannon", "cannon"], 0.0, 0.15)
			_until(g, {"sniper": 0.85, "cannon": 0.15}, func(x): return _phase(x, "brood") in ["announced", "active"] and _phase(x, "flock") in ["announced", "active"], 16)
		"locked":
			g = _new(true, "hard", ["sniper", "tesla", "net"])
			place(g, ["arrow", "arrow", "ember", "arrow", "arrow", "frost", "flak", "arrow"])
			_until(g, rapid, func(x): return _phase(x, "hulk") == "announced")
		"boss_off":
			g = _new(false, "normal")
			place(g, ["arrow", "cannon", "frost", "ember", "sniper", "flak", "poison", "cannon"])
			_until(g, mixed, func(x): return x.wave == 10)
		"stealth_off":
			g = _new(false, "normal")
			place(g, ["arrow", "cannon", "frost", "ember", "sniper", "flak", "poison", "cannon"])
			_until(g, mixed, func(x): return x.wave == 9)
		"armor_off":
			g = _new(false, "hard")
			place(g, ["arrow", "arrow", "cannon", "arrow", "sniper", "arrow", "flak"])
			_until(g, {"arrow": 0.5, "cannon": 0.25, "sniper": 0.2, "flak": 0.05}, func(x): return x.wave == 8)
		"defeat_hulk":
			g = build("active_hulk")
			defeat(g, {"hulk": 7}, 3)
		"defeat_unknown":
			g = build("quiet_off")
			defeat(g, {}, 0)
			g.leak_known = false
		_:
			g = _new(false)
	return g


## Поражение в текущей волне: настоящий старт волны, затем учёт прорывов тем же кодом, что и в бою (TDGame.note_leak).
static func defeat(g: TDGame, strain_leaks: Dictionary, normal_leaks: int) -> void:
	g.start_wave()
	for p in strain_leaks:
		for _i in int(strain_leaks[p]):
			var e := TDGame.Enemy.new()
			e.strain = p
			e.ph = {"fly": p == "flock", "stealth": false}
			g.note_leak(e)
	for _i in normal_leaks:
		var e2 := TDGame.Enemy.new()
		e2.ph = {"fly": false, "stealth": false}
		g.note_leak(e2)
	g.leaked = int(g.wave_leaks.get("total", 0))
	g.run_leaked += g.leaked
	g.lives = 0
	g.phase = "over"
