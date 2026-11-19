extends SceneTree
## PRO-139: телеметрия прототипа развилки по маршрутам и нагрузка. Только измерение — коэффициенты не подбираются.
##   godot --headless --path godot --script res://tests/fork_probe.gd [-- --waves=15 --seeds=5 --out=../build/fork/probe.json]
## Расстановки (одинаковый набор башен, без улучшений, жизней с запасом — смотрим распределение, а не победу):
##   trunk — у общего входа и слияния; hub — в середине между ветками; north — только у северной ветки; split — поровну.
## Метрики на маршрут (обычные волны): gate20 — доля наземных, убитых в первых 20% своего маршрута; p90 — 90-й перцентиль
## пройденной доли своего маршрута (прорыв = 1,5); leaks — прорывы на волну; cov20 — доля точек первых 20% маршрута,
## которые достаёт хоть одна наземная башня. Нагрузка: мс на шаг симуляции при 300 врагах и 24 башнях, развилка против обычной карты.

const KINDS := ["arrow", "cannon", "frost", "sniper", "arrow", "cannon", "ember", "arrow"]
const LAYOUTS := {
	"fork": {
		"trunk": [Vector2i(1, 3), Vector2i(1, 5), Vector2i(2, 3), Vector2i(2, 5), Vector2i(12, 3), Vector2i(12, 5), Vector2i(13, 3), Vector2i(13, 5)],
		"hub": [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4), Vector2i(5, 3), Vector2i(7, 5), Vector2i(9, 3)],
		"north": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(9, 0), Vector2i(6, 2), Vector2i(8, 2)],
		"split": [Vector2i(5, 0), Vector2i(7, 0), Vector2i(9, 0), Vector2i(6, 2), Vector2i(5, 8), Vector2i(7, 8), Vector2i(9, 8), Vector2i(6, 6)],
	},
	"fork_uneven": {
		"trunk": [Vector2i(1, 3), Vector2i(1, 5), Vector2i(2, 3), Vector2i(2, 5), Vector2i(13, 3), Vector2i(13, 5), Vector2i(14, 3), Vector2i(14, 5)],
		"hub": [Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(4, 5), Vector2i(10, 5)],
		"north": [Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(6, 3), Vector2i(7, 3), Vector2i(10, 3)],
		"split": [Vector2i(5, 1), Vector2i(7, 1), Vector2i(7, 3), Vector2i(10, 3), Vector2i(5, 7), Vector2i(7, 7), Vector2i(9, 7), Vector2i(6, 9)],
	},
}

var waves := 15
var seeds := 5
var out_path := ""


func pct(vals: Array, q: float) -> float:
	if vals.is_empty():
		return NAN
	var s := vals.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(q * s.size()))]


func mean(vals: Array) -> float:
	if vals.is_empty():
		return NAN
	var t := 0.0
	for v in vals:
		t += v
	return t / vals.size()


func cov20(g: TDGame, r: TDPath) -> float:
	var n := 0
	var hit := 0
	for i in 16:
		var p := r.pos_at((i + 0.5) / 16.0 * 0.2 * r.length)
		n += 1
		for t in g.towers:
			if t.def.has("aura") or not t.def["ground"]:
				continue
			if p.distance_to(Vector2(t.x + 0.5, t.y + 0.5)) <= g.t_range(t):
				hit += 1
				break
	return float(hit) / n


func run(variant: String, layout: String, seed_v: int) -> Dictionary:
	var g := TDGame.new(seed_v, TDMap.fork_test(variant), {"lives": 100000})
	g.gold = 100000
	var cells: Array = LAYOUTS[variant][layout]
	for i in cells.size():
		if not g.place_tower(KINDS[i], cells[i].x, cells[i].y):
			push_error("%s/%s: нельзя поставить %s в %s (%s)" % [variant, layout, KINDS[i], cells[i], g.place_problem(KINDS[i], cells[i].x, cells[i].y)])
	var acc := {}
	for r in g.map.routes:
		acc[r.id] = {"gate": [], "prog": [], "leaks": 0, "n": 0, "cov20": cov20(g, r)}
	for w in waves:
		if not g.offer.is_empty():
			g.choose_perk(g.offer[0])
		var normal := g.wave % 10 != 0 and g.upcoming_special == ""
		g.start_wave()
		for _i in 20000:
			g.step(0.05)
			if g.phase != "wave":
				break
		if not normal:
			continue
		var by := {}
		for f in g.finished:
			if float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD:
				continue
			var rid: int = f["route"]
			if not by.has(rid):
				by[rid] = []
			by[rid].append(float(f["fitness"]))
		for rid in by:
			var a: Dictionary = acc[rid]
			var fs: Array = by[rid]
			var gate := 0
			var lk := 0
			for x in fs:
				if x < 0.2:
					gate += 1
				if x >= 1.5:
					lk += 1
			a["gate"].append(float(gate) / fs.size())
			a["prog"].append(pct(fs, 0.9))
			a["leaks"] += lk
			a["n"] += 1
	var res := {}
	for rid in acc:
		var a: Dictionary = acc[rid]
		res[rid] = {"gate20": mean(a["gate"]), "p90": mean(a["prog"]), "leaks": float(a["leaks"]) / maxi(1, a["n"]), "cov20": a["cov20"]}
	return res


func load_ms(map: TDMap) -> float:
	var g := TDGame.new(77, map, {"lives": 100000})
	g.gold = 100000
	var placed := 0
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if placed < 24 and (x + y) % 3 == 0 and g.place_tower(["arrow", "cannon", "frost", "tesla"][placed % 4], x, y):
				placed += 1
	g.phase = "wave"
	var rng := TDRng.new(9)
	for i in 300:
		var e := TDGame.Enemy.new()
		e.id = g.next_id
		g.next_id += 1
		e.genome = TDGenome.random_genome(rng, 10)
		e.ph = TDGenome.phenotype(e.genome, 10).duplicate()
		e.ph["hp"] = 1e9
		e.hp = e.ph["hp"]
		e.route = map.route_for(i)
		e.dist = float(i % 60) * 0.3
		g.enemies.append(e)
	var t0 := Time.get_ticks_usec()
	for _i in 200:
		g.step(0.02)
	return (Time.get_ticks_usec() - t0) / 1000.0 / 200.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--waves="):
			waves = int(a.substr(8))
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	var report := {"waves": waves, "seeds": seeds, "layouts": {}, "load": {}}
	print("| Карта | Расстановка | Маршрут | gate20 | p90 | прорывов на волну | cov20 |")
	print("|---|---|---|---|---|---|---|")
	for variant in LAYOUTS:
		for layout in LAYOUTS[variant]:
			var per := {}
			for s in seeds:
				var r := run(variant, layout, (s + 1) * 4243)
				for rid in r:
					if not per.has(rid):
						per[rid] = {"gate20": [], "p90": [], "leaks": [], "cov20": []}
					for m in r[rid]:
						if r[rid][m] == r[rid][m]:
							per[rid][m].append(r[rid][m])
			report["layouts"]["%s/%s" % [variant, layout]] = {}
			for rid in per:
				var row := {}
				for m in per[rid]:
					row[m] = mean(per[rid][m])
				report["layouts"]["%s/%s" % [variant, layout]][str(rid)] = row
				print("| %s | %s | %s | %.2f | %.2f | %.2f | %.2f |" % [variant, layout, "0 · север" if rid == 0 else "1 · юг", row["gate20"], row["p90"], row["leaks"], row["cov20"]])
	var single := load_ms(TDMap.generate(1003))
	var fork := load_ms(TDMap.fork_test("fork"))
	report["load"] = {"single_ms_per_step": single, "fork_ms_per_step": fork}
	print("\nНагрузка (300 врагов, 24 башни, шаг 0,02 с): обычная карта %.2f мс/шаг, развилка %.2f мс/шаг (×%.2f)" % [single, fork, fork / single])
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit()
