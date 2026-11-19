extends SceneTree
## PRO-213: расстановки при одинаковом бюджете на сгенерированных развилках. Коэффициенты не подбираются: смотрим, что
## даёт распределение обороны по дорогам и держит ли лагерь у входа обе дороги.
##   godot --headless --path godot --script res://tests/fork_layouts.gd [-- --seeds=20 --waves=15 --out=../build/fork/layouts.json]
## Одинаковый набор башен (10 штук первого уровня, без улучшений и перков), жизней с запасом — смотрим распределение, а не победу.
##   gate  — «лагерь у входа»: клетки, накрывающие первые 20% обеих дорог (как в PRO-192);
##   split — поровну: по очереди лучшая клетка для собственных клеток северной и южной дороги;
##   north — одна сторона: только собственные клетки северной дороги;
##   bot   — как бот харнесса: длина всех дорог в радиусе с весом доли врагов.
## Метрики на дорогу (обычные волны): gate20, p90 (своей дороги), прорывов на волну, cov20 и own — доля первых 20% и
## собственных клеток дороги, которые достаёт хоть одна башня.

const KINDS := ["arrow", "cannon", "frost", "sniper", "arrow", "cannon", "ember", "arrow", "tesla", "frost"]
const LAYOUTS := ["gate", "split", "north", "bot"]

var seeds := 20
var waves := 15
var out_path := ""


func mean(a: Array) -> float:
	if a.is_empty():
		return NAN
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func pct(a: Array, q: float) -> float:
	var s := a.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(q * s.size()))] if not s.is_empty() else NAN


## Точки дорог: [route_id, позиция, вес доли, в первых 20%, собственная клетка дороги]
func samples(m: TDMap) -> Array:
	var out: Array = []
	for r in m.routes:
		var w := TDAdvisor.route_share(m, r.id)
		for i in 80:
			var d := (i + 0.5) / 80.0 * r.length
			var p := r.pos_at(d)
			var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
			out.append([r.id, p, w, d < 0.2 * r.length, m.routes_at(c).size() == 1])
	return out


func north_id(m: TDMap) -> int:
	return 0 if TDAdvisor.route_name(m, 0) == "северная" else 1


func score(layout: String, side: int, cell: Vector2, pts: Array, r: float) -> float:
	var v := 0.0
	for s in pts:
		if (s[1] as Vector2).distance_to(cell) > r:
			continue
		match layout:
			"gate":
				v += s[2] if s[3] else 0.0
			"split", "north":
				v += 1.0 if s[4] and s[0] == side else 0.0
			"bot":
				v += s[2]
	return v


func place(g: TDGame, layout: String) -> void:
	var pts := samples(g.map)
	var nid := north_id(g.map)
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var r: float = TDConfig.TOWERS[kind]["range"]
		var side := nid if layout == "north" else (nid if i % 2 == 0 else 1 - nid)
		var best := Vector2i(-1, -1)
		var best_v := -1.0
		for x in TDConfig.COLS:
			for y in TDConfig.ROWS:
				if not g.can_place(kind, x, y):
					continue
				var v := score(layout, side, Vector2(x + 0.5, y + 0.5), pts, r)
				if v > best_v:
					best_v = v
					best = Vector2i(x, y)
		if best.x >= 0:
			g.place_tower(kind, best.x, best.y)


func coverage(g: TDGame) -> Dictionary:
	var out := {}
	for r in g.map.routes:
		var g20 := [0, 0]
		var own := [0, 0]
		for i in 40:
			var d := (i + 0.5) / 40.0 * r.length
			var p := r.pos_at(d)
			var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
			var hit := false
			for t in g.towers:
				if not t.def.has("aura") and t.def["ground"] and p.distance_to(Vector2(t.x + 0.5, t.y + 0.5)) <= g.t_range(t):
					hit = true
					break
			if d < 0.2 * r.length:
				g20[1] += 1
				g20[0] += 1 if hit else 0
			if g.map.routes_at(c).size() == 1:
				own[1] += 1
				own[0] += 1 if hit else 0
		out[r.id] = {"cov20": float(g20[0]) / maxi(1, g20[1]), "own": float(own[0]) / maxi(1, own[1])}
	return out


func run(fam: String, layout: String, seed_v: int) -> Dictionary:
	var m := TDMap.generate(seed_v, fam)
	if m.fork_fallback:
		return {}
	var g := TDGame.new(seed_v, m, {"lives": 100000})
	g.gold = 100000
	place(g, layout)
	var nid := north_id(m)
	var cov := coverage(g)
	var acc := {}
	for r in m.routes:
		acc[r.id] = {"gate": [], "p90": [], "leaks": 0, "n": 0}
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
		var by := {}
		for f in g.finished:
			if float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD:
				continue
			var rid: int = f["route"]
			if not by.has(rid):
				by[rid] = []
			by[rid].append(float(f["fitness"]))
		for rid in by:
			var fs: Array = by[rid]
			var gate := 0
			var lk := 0
			for x in fs:
				gate += 1 if x < 0.2 else 0
				lk += 1 if x >= 1.5 else 0
			acc[rid]["gate"].append(float(gate) / fs.size())
			acc[rid]["p90"].append(pct(fs, 0.9))
			acc[rid]["leaks"] += lk
			acc[rid]["n"] += 1
	# север — «n», юг — «s»
	var res := {}
	for rid in acc:
		var key := "n" if rid == nid else "s"
		res[key] = {"gate20": mean(acc[rid]["gate"]), "p90": mean(acc[rid]["p90"]), "leaks": float(acc[rid]["leaks"]) / maxi(1, acc[rid]["n"]),
			"cov20": cov[rid]["cov20"], "own": cov[rid]["own"]}
	return res


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--waves="):
			waves = int(a.substr(8))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	var report := {"seeds": seeds, "waves": waves, "rows": []}
	print("| Карта | Расстановка | gate20 С / Ю | p90 С / Ю | прорывов на волну С / Ю | cov20 С / Ю | собственных клеток под огнём С / Ю | карт |")
	print("|---|---|---|---|---|---|---|---|")
	for fam in TDMap.FORK_FAMILIES:
		for layout in LAYOUTS:
			var agg := {"n": {}, "s": {}}
			var maps := 0
			for i in seeds:
				var r := run(fam, layout, (i + 1) * 4243)
				if r.is_empty():
					continue
				maps += 1
				for side in ["n", "s"]:
					for k in r[side]:
						if not agg[side].has(k):
							agg[side][k] = []
						if r[side][k] == r[side][k]:
							agg[side][k].append(r[side][k])
			var row := {"family": fam, "layout": layout, "maps": maps}
			for side in ["n", "s"]:
				for k in agg[side]:
					row["%s_%s" % [k, side]] = mean(agg[side][k])
			report["rows"].append(row)
			print("| %s | %s | %.2f / %.2f | %.2f / %.2f | %.2f / %.2f | %.2f / %.2f | %.2f / %.2f | %d |" % [fam, layout,
				row["gate20_n"], row["gate20_s"], row["p90_n"], row["p90_s"], row["leaks_n"], row["leaks_s"],
				row["cov20_n"], row["cov20_s"], row["own_n"], row["own_s"], maps])
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit()
