extends SceneTree
## PRO-151: «лаборатория» башен. Одна или две башни на классической карте против стандартной колонны врагов.
## Боевую логику не меняет: только расставляет башни и подменяет состав волны (как tests/adaptation_check.gd).
##
## Запуск (из папки godot): Godot --headless --path . --script res://tests/tower_lab.gd [-- --out=lab.csv]
## Два режима:
##   throughput — враги бессмертны (hp = 1e9): суммарный урон за проход колонны, отсюда урон на монету;
##   kill       — честное здоровье: доля убитых и p50 дистанции гибели (сколько волны «держит» конфигурация).

const DT := 1.0 / 30.0
const COUNT := 20

## Профили целей: волна задаёт здоровье по формуле фенотипа, гены — защиту.
const PROFILES := {
	"w8_plain": {"wave": 8, "g": {"tough": 0.25, "swift": 0.2}},
	"w8_armor": {"wave": 8, "g": {"tough": 0.25, "swift": 0.2, "plated": 0.9}},
	"w15_armor": {"wave": 15, "g": {"tough": 0.35, "swift": 0.2, "plated": 0.9}},
	"w15_fast": {"wave": 15, "g": {"tough": 0.25, "swift": 0.9, "plated": 0.3}},
	"w15_air": {"wave": 15, "g": {"tough": 0.25, "swift": 0.2, "plated": 0.3, "wings": 0.6}},
	"w15_resist": {"wave": 15, "g": {"tough": 0.3, "swift": 0.2, "plated": 0.5, "ember": 0.9, "frost": 0.9}},
	"w25_armor": {"wave": 25, "g": {"tough": 0.45, "swift": 0.2, "plated": 0.95}},
}

## Конфигурации: список башен [kind, level, branch]. Пары — для связок и Маяка.
func configs() -> Array:
	var out: Array = []
	for k in TDConfig.TOWER_KINDS:
		if k == "beacon":
			continue
		out.append([[k, 1, ""]])
		out.append([[k, 2, ""]])
		out.append([[k, 3, "a"]])
		out.append([[k, 3, "b"]])
	for pair in [["arrow", "arrow"], ["arrow", "frost"], ["arrow", "ember"], ["arrow", "beacon"], ["sniper", "sniper"],
			["sniper", "frost"], ["sniper", "beacon"], ["cannon", "frost"], ["cannon", "ember"], ["tesla", "frost"],
			["arrow", "poison"], ["flak", "net"]]:
		out.append([[pair[0], 1, ""], [pair[1], 1, ""]])
		out.append([[pair[0], 3, DEFAULT_BRANCH[pair[0]]], [pair[1], 3, DEFAULT_BRANCH[pair[1]]]])
	return out

const DEFAULT_BRANCH := {"arrow": "a", "cannon": "b", "ember": "b", "frost": "a", "sniper": "b", "poison": "b",
	"flak": "b", "tesla": "a", "net": "a", "beacon": "b"}


func _genome(p: Dictionary) -> Dictionary:
	var g := {}
	for k in TDGenome.GENES:
		g[k] = float(p["g"].get(k, 0.0))
	return g


func _best_cells(m: TDMap, r: float, air: bool) -> Array:
	var cells: Array = []
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if m.is_path(x, y) or m.is_blocked(x, y):
				continue
			var c := Vector2(x + 0.5, y + 0.5)
			var s := 0.0
			for i in 160:
				var p: Vector2 = m.fly_pos_at((i + 0.5) / 160.0 * m.fly_length) if air else m.pos_at((i + 0.5) / 160.0 * m.length)
				if p.distance_to(c) <= r:
					s += 1.0
			cells.append([s, x, y])
	cells.sort_custom(func(a, b): return a[0] > b[0])
	return cells


func run(cfg: Array, prof_id: String, immortal: bool) -> Dictionary:
	var prof: Dictionary = PROFILES[prof_id]
	var w: int = prof["wave"]
	var m := TDMap.classic()
	var g := TDGame.new(4243, m, {})
	g.gold = 1000000
	g.lives = 1000000
	g.wave = w
	var ge := _genome(prof)
	var air: bool = float(ge["wings"]) > TDGenome.TRAIT_THRESHOLD
	var cost := 0
	var first := Vector2i(-1, -1)
	for spec in cfg:
		var kind: String = spec[0]
		var def := TDConfig.tower_def(kind, int(spec[1]), String(spec[2]))
		var spot := Vector2i(-1, -1)
		if kind == "beacon":
			# Маяк рядом с первой башней
			for c in _best_cells(m, 1.5, false):
				if g.tower_at(c[1], c[2]) == null and Vector2(c[1], c[2]).distance_to(Vector2(first)) <= 1.5:
					spot = Vector2i(c[1], c[2])
					break
		else:
			for c in _best_cells(m, def["range"], air):
				if g.tower_at(c[1], c[2]) == null:
					spot = Vector2i(c[1], c[2])
					break
		var before := g.gold
		g.place_tower(kind, spot.x, spot.y)
		var t := g.tower_at(spot.x, spot.y)
		while t.level < int(spec[1]):
			g.upgrade_tower(t, String(spec[2]))
		cost += before - g.gold
		if first.x < 0:
			first = spot
	g.upcoming = []
	for i in COUNT:
		g.upcoming.append(ge.duplicate())
	g.start_wave()
	var seen := {}
	var prog: Array = []
	var guard := 0
	while g.phase == "wave" and guard < 30 * 600:
		g.step(DT)
		guard += 1
		for e in g.enemies:
			if immortal and not seen.has(e.id):
				e.hp = 1.0e9
			seen[e.id] = true
	var dealt := 0.0
	for k in g.damage_by:
		dealt += g.damage_by[k]
	for f in g.finished:
		prog.append(float(f["fitness"]))
	prog.sort()
	var p50: float = prog[prog.size() / 2] if not prog.is_empty() else -1.0
	return {"cost": cost, "dealt": dealt, "killed": g.killed, "leaked": g.leaked, "p50": p50, "hp": TDGenome.phenotype(ge, w)["hp"]}


func _initialize() -> void:
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
	var lines: Array[String] = ["config,profile,cost,dmg_pass,dmg_per_gold,killed,count,p50_death,enemy_hp"]
	for cfg in configs():
		var name := " + ".join(cfg.map(func(s): return "%s%d%s" % [s[0], s[1], s[2]]))
		for pid in PROFILES:
			var th := run(cfg, pid, true)
			var kl := run(cfg, pid, false)
			lines.append("%s,%s,%d,%.0f,%.2f,%d,%d,%.3f,%.0f" % [name, pid, th["cost"], th["dealt"], th["dealt"] / maxf(1.0, th["cost"]), kl["killed"], COUNT, kl["p50"], th["hp"]])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		var f2 := FileAccess.open(out_path.get_basename() + "_advisor.csv", FileAccess.WRITE)
		f2.store_string("\n".join(advisor_lines()) + "\n")
		f2.close()
	else:
		for l in lines:
			print(l)
	quit()


## Звёзды советника (TDAdvisor.rate_towers) для тех же профилей: на пустом поле и при обороне в духе владельца.
func advisor_lines() -> Array[String]:
	var out: Array[String] = ["profile,board,kind,stars,note"]
	for pid in PROFILES:
		for board in ["empty", "owner"]:
			var prof: Dictionary = PROFILES[pid]
			var m := TDMap.classic()
			var g := TDGame.new(4243, m, {})
			g.gold = 1000000
			g.wave = prof["wave"]
			if board == "owner":
				for kind in ["arrow", "arrow", "arrow", "sniper", "sniper", "frost", "ember", "poison"]:
					for c in _best_cells(m, TDConfig.TOWERS[kind]["range"], false):
						if g.tower_at(c[1], c[2]) == null:
							g.place_tower(kind, c[1], c[2])
							break
			g.upcoming = []
			for i in COUNT:
				g.upcoming.append(_genome(prof))
			var r := TDAdvisor.rate_towers(g, TDAdvisor.wave_info(g))
			for k in TDConfig.TOWER_KINDS:
				out.append("%s,%s,%s,%d,%s" % [pid, board, k, r[k]["stars"], String(r[k]["note"]).replace(",", ";")])
	return out
