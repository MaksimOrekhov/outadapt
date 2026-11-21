extends SceneTree
## PRO-141: расстановки при одинаковом бюджете на картах с двумя порталами и на развилках с одним порталом.
##   godot --headless --path godot --script res://tests/portal_layouts.gd -- --seeds=20 [--seed-from=0] [--waves=14] --out=…json
## Не бот: одинаковый набор из 10 башен первого уровня (без улучшений и перков), золото не ограничивает, жизней с запасом.
## Второй портал открыт с самого начала (волна 2, расписание не проверяется — только «куда падает оборона»): смотрим покрытие
## ворот каждого входа и сколько башен достаёт оба. Расстановки:
##   camp0   — «лагерь у первого портала»: клетки, максимально накрывающие ворота (первые 20% пути) первого входа;
##   camp1   — то же у второго портала;
##   split   — поровну: башни по очереди у ворот первого и второго входа;
##   dual    — «двойное назначение»: клетка, накрывающая больше всего точек ворот ОБОИХ входов (самый сильный способ закрыть оба);
##   bot     — как бот харнесса: длина всех дорог в радиусе с весом доли врагов;
##   one     — вся оборона вдоль первой дороги (второй вход бот не защищает).
## На развилке с одним порталом ворота обеих дорог — один общий ствол, поэтому camp0 накрывает оба по построению.
## Метрики (обычные волны): cov20 ворот каждого входа, доля башен, достающих оба входа, прорывов на волну по дорогам.

const KINDS := ["arrow", "cannon", "frost", "sniper", "arrow", "cannon", "ember", "arrow", "tesla", "frost"]
const LAYOUTS := ["camp0", "camp1", "split", "dual", "bot", "one"]

var seeds := 20
var seed_from := 0
var waves := 14
var out_path := ""


func mean(a: Array) -> float:
	if a.is_empty():
		return NAN
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func gate_points(m: TDMap, rid: int) -> Array[Vector2]:
	var r: TDPath = m.routes[rid]
	var out: Array[Vector2] = []
	for i in 12:
		out.append(r.pos_at((i + 0.5) / 12.0 * 0.2 * r.length))
	return out


func path_points(m: TDMap, rid: int) -> Array[Vector2]:
	var r: TDPath = m.routes[rid]
	var out: Array[Vector2] = []
	for i in 60:
		out.append(r.pos_at((i + 0.5) / 60.0 * r.length))
	return out


func hits(pts: Array, c: Vector2, r: float) -> int:
	var n := 0
	for p in pts:
		if (p as Vector2).distance_to(c) <= r:
			n += 1
	return n


func place_next(g: TDGame, layout: String, i: int) -> void:
	var m := g.map
	var kind: String = KINDS[i]
	var r: float = TDConfig.TOWERS[kind]["range"]
	var g0 := gate_points(m, 0)
	var g1 := gate_points(m, 1)
	var p0 := path_points(m, 0)
	var best := Vector2i(-1, -1)
	var best_v := -1.0
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if not g.can_place(kind, x, y):
				continue
			var c := Vector2(x + 0.5, y + 0.5)
			var v := 0.0
			match layout:
				"camp0":
					v = hits(g0, c, r)
				"camp1":
					v = hits(g1, c, r)
				"split":
					v = hits(g0 if i % 2 == 0 else g1, c, r)
				"dual":
					v = hits(g0, c, r) + hits(g1, c, r) + 0.5 * mini(hits(g0, c, r), hits(g1, c, r))
				"bot":
					for rt in m.routes:
						var w := m.share_at(rt.id)
						for s in 80:
							if rt.pos_at((s + 0.5) / 80.0 * rt.length).distance_to(c) <= r:
								v += w
				"one":
					v = hits(p0, c, r)
			# слабое предпочтение клеток ближе к центру, чтобы результат не зависел от порядка обхода
			v += 0.001 * (8.0 - c.distance_to(Vector2(8, 5)))
			if v > best_v:
				best_v = v
				best = Vector2i(x, y)
	if best.x >= 0:
		g.place_tower(kind, best.x, best.y)


func coverage(g: TDGame) -> Dictionary:
	var out := {"cov": [0.0, 0.0], "both": 0.0}
	var shooters: Array = []
	for t in g.towers:
		if not t.def.has("aura") and t.def["ground"]:
			shooters.append(t)
	for rid in 2:
		var pts := gate_points(g.map, rid)
		var hit := 0
		for p in pts:
			for t in shooters:
				if p.distance_to(Vector2(t.x + 0.5, t.y + 0.5)) <= g.t_range(t):
					hit += 1
					break
		out["cov"][rid] = float(hit) / pts.size()
	var both := 0
	var g0 := gate_points(g.map, 0)
	var g1 := gate_points(g.map, 1)
	for t in shooters:
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		if hits(g0, c, g.t_range(t)) > 0 and hits(g1, c, g.t_range(t)) > 0:
			both += 1
	out["both"] = float(both) / maxi(1, shooters.size())
	return out


func run(mapname: String, layout: String, seed_v: int) -> Dictionary:
	var m: TDMap
	if TDMap.PORTAL_MAPS.has(mapname):
		m = TDMap.portal_test(mapname, 2, 1, 50)
	else:
		m = TDMap.generate(seed_v, mapname)
		if m.fork_fallback:
			return {}
	var g := TDGame.new(seed_v, m, {"lives": 100000})
	g.gold = 100000
	for i in KINDS.size():
		place_next(g, layout, i)
	var cov := coverage(g)
	var leaks := [0, 0]
	var n_waves := 0
	g.wave = 2 if m.portal2 else g.wave
	for _w in waves:
		if not g.offer.is_empty():
			g.offer = []
		var normal := g.wave % 10 != 0 and g.upcoming_special == ""
		g.start_wave()
		for _i in 20000:
			g.step(0.05)
			if g.phase != "wave":
				break
		if not normal:
			continue
		n_waves += 1
		for f in g.finished:
			if float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD:
				continue
			if float(f["fitness"]) >= 1.5:
				leaks[int(f["route"])] += 1
	return {"cov0": cov["cov"][0], "cov1": cov["cov"][1], "both": cov["both"], "leaks0": float(leaks[0]) / maxi(1, n_waves), "leaks1": float(leaks[1]) / maxi(1, n_waves)}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed-from="):
			seed_from = int(a.substr(12))
		elif a.begins_with("--waves="):
			waves = int(a.substr(8))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	var report := {"seeds": seeds, "seed_from": seed_from, "waves": waves, "rows": []}
	print("| Карта | Расстановка | cov20 ворот: 1-й / 2-й вход | башен, достающих оба входа | прорывов на волну: 1-й / 2-й вход | карт |")
	print("|---|---|---|---|---|---|")
	for mapname in ["portal_a", "portal_b", "fork_even", "fork_skew"]:
		for layout in LAYOUTS:
			var acc := {"cov0": [], "cov1": [], "both": [], "leaks0": [], "leaks1": []}
			var n := 0
			for i in seeds:
				var r := run(mapname, layout, (seed_from + i + 1) * 4243)
				if r.is_empty():
					continue
				n += 1
				for k in acc:
					acc[k].append(r[k])
			var row := {"map": mapname, "layout": layout, "maps": n}
			for k in acc:
				row[k] = mean(acc[k])
			report["rows"].append(row)
			print("| %s | %s | %.2f / %.2f | %.2f | %.2f / %.2f | %d |" % [mapname, layout, row["cov0"], row["cov1"], row["both"], row["leaks0"], row["leaks1"], n])
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit()
