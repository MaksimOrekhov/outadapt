extends SceneTree
## PRO-214: расстановки «как у человека» в ранних волнах при расписании ввода второй дороги и без него.
##   godot --headless --path godot --script res://tests/fork_ramp_layouts.gd -- --seeds=20 [--seed-from=0] [--arm=a|b_short|b_long|e_short|e_long] --out=…json
## Не бот: одинаковый порядок башен (KINDS), одинаковое число башен к каждой волне (START башен в 1-й, +1 за волну до 10),
## золото не ограничивает, жизней с запасом — смотрим распределение прорывов по дорогам, а не победу.
##   gate  — «лагерь у входа»: клетки, накрывающие первые 20% обеих дорог;
##   split — поровну: башни по очереди у собственных клеток короткой и длинной дороги (начиная с короткой);
##   short — все башни у короткой дороги (у дороги, которую видно сразу, если лидер — короткая);
##   long  — все башни у длинной;
##   bot   — как бот харнесса: длина всех дорог в радиусе с весом установившейся доли врагов.
## Метрики на дорогу (обычные волны 1–9, 10-я боссовая не считается): прорывов на волну всего и в 3–9 (после подключения
## второй дороги), доля врагов на дороге.

const KINDS := ["arrow", "cannon", "frost", "sniper", "arrow", "cannon", "ember", "arrow", "tesla", "frost"]
const LAYOUTS := ["gate", "split", "short", "long", "bot"]
const START := 3
const WAVES := 9

var seeds := 20
var seed_from := 0
var arm := "a"
var out_path := ""


func mean(a: Array) -> float:
	if a.is_empty():
		return NAN
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func samples(m: TDMap) -> Array:
	var out: Array = []
	for r in m.routes:
		var w := m.share_at(r.id)
		for i in 80:
			var d := (i + 0.5) / 80.0 * r.length
			var p := r.pos_at(d)
			var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
			out.append([r.id, p, w, d < 0.2 * r.length, m.routes_at(c).size() == 1])
	return out


func short_id(m: TDMap) -> int:
	return 0 if m.routes[0].length <= m.routes[1].length else 1


func score(layout: String, side: int, cell: Vector2, pts: Array, r: float) -> float:
	var v := 0.0
	for s in pts:
		if (s[1] as Vector2).distance_to(cell) > r:
			continue
		match layout:
			"gate":
				v += s[2] if s[3] else 0.0
			"split", "short", "long":
				v += 1.0 if s[4] and s[0] == side else 0.0
			"bot":
				v += s[2]
	return v


func place_next(g: TDGame, layout: String, i: int, pts: Array) -> void:
	var sid := short_id(g.map)
	var side := sid
	match layout:
		"split":
			side = sid if i % 2 == 0 else 1 - sid
		"long":
			side = 1 - sid
	var kind: String = KINDS[i]
	var r: float = TDConfig.TOWERS[kind]["range"]
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


func run(fam: String, layout: String, seed_v: int) -> Dictionary:
	var m := TDMap.generate(seed_v, fam)
	if m.fork_fallback:
		return {}
	if arm != "a":
		var parts := arm.split("_")
		var nm := "pilot" if parts[0] == "b" else "early"
		m.set_ramp(nm, parts[1])
	var g := TDGame.new(seed_v, m, {"lives": 100000})
	g.gold = 100000
	var pts := samples(m)
	var sid := short_id(m)
	var res := {"leaks_s": [], "leaks_l": [], "n_s": [], "n_l": []}
	var built := 0
	for w in range(1, WAVES + 2):
		while built < mini(KINDS.size(), START + w - 1):
			place_next(g, layout, built, pts)
			built += 1
		if not g.offer.is_empty():
			g.offer = []
		var normal := g.wave % 10 != 0 and g.upcoming_special == ""
		g.start_wave()
		for _i in 20000:
			g.step(0.05)
			if g.phase != "wave":
				break
		if not normal or w > WAVES:
			continue
		var lk := {0: 0, 1: 0}
		var nn := {0: 0, 1: 0}
		for f in g.finished:
			if float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD:
				continue
			var rid: int = f["route"]
			nn[rid] += 1
			lk[rid] += 1 if float(f["fitness"]) >= 1.5 else 0
		res["leaks_s"].append([w, lk[sid]])
		res["leaks_l"].append([w, lk[1 - sid]])
		res["n_s"].append([w, nn[sid]])
		res["n_l"].append([w, nn[1 - sid]])
	return res


func avg_w(rows: Array, lo: int, hi: int) -> float:
	var v := []
	for x in rows:
		if x[0] >= lo and x[0] <= hi:
			v.append(float(x[1]))
	return mean(v)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed-from="):
			seed_from = int(a.substr(12))
		elif a.begins_with("--arm="):
			arm = a.substr(6)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	var report := {"arm": arm, "seeds": seeds, "seed_from": seed_from, "rows": []}
	print("| Плечо | Карта | Расстановка | прорывов на волну 1–9: короткая / длинная | в 3–9: короткая / длинная | врагов на волну 1–2: короткая / длинная | карт |")
	print("|---|---|---|---|---|---|---|")
	for fam in TDMap.FORK_FAMILIES:
		for layout in LAYOUTS:
			var a19s := []
			var a19l := []
			var a39s := []
			var a39l := []
			var n12s := []
			var n12l := []
			var maps := 0
			for i in seeds:
				var r := run(fam, layout, (seed_from + i + 1) * 4243)
				if r.is_empty():
					continue
				maps += 1
				a19s.append(avg_w(r["leaks_s"], 1, 9))
				a19l.append(avg_w(r["leaks_l"], 1, 9))
				a39s.append(avg_w(r["leaks_s"], 3, 9))
				a39l.append(avg_w(r["leaks_l"], 3, 9))
				n12s.append(avg_w(r["n_s"], 1, 2))
				n12l.append(avg_w(r["n_l"], 1, 2))
			var row := {"arm": arm, "family": fam, "layout": layout, "maps": maps, "leaks19_short": mean(a19s), "leaks19_long": mean(a19l),
				"leaks39_short": mean(a39s), "leaks39_long": mean(a39l), "n12_short": mean(n12s), "n12_long": mean(n12l)}
			report["rows"].append(row)
			print("| %s | %s | %s | %.2f / %.2f | %.2f / %.2f | %.1f / %.1f | %d |" % [arm, fam, layout, row["leaks19_short"], row["leaks19_long"],
				row["leaks39_short"], row["leaks39_long"], row["n12_short"], row["n12_long"], maps])
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit()
