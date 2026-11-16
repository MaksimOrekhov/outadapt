extends SceneTree
## PRO-115: сиды для живых плейтестов — по одному-два на семейство карты, только в изначально открытых биомах
## (лес, осень), чтобы карта не выдавала прогресс Мастерской. Печатает таблицу для протокола.
## Запуск из папки godot: Godot --headless --path . --script res://tools/playtest_seeds.gd


func _initialize() -> void:
	var want := {"snake": [], "vsnake": [], "stairs": [], "hooks": []}
	var s := 1000
	while s < 200000:
		s += 1
		if not TDEnv.biome_of_seed(s) in ["forest", "autumn"]:
			continue
		var fam := TDMap.family_for(s)
		if want.has(fam) and want[fam].size() < 2:
			var m := TDMap.generate(s)
			if m.family == fam:
				want[fam].append([s, TDEnv.biome_name(s), m.map_name, snappedf(m.length, 0.1), snappedf(m.fly_length, 0.1)])
		var done := true
		for k in want:
			done = done and want[k].size() >= 2
		if done:
			break
	print("| семейство | сид | биом | карта | длина дороги | прямая полёта |")
	print("|---|---|---|---|---|---|")
	for k in want:
		for r in want[k]:
			print("| %s | %d | %s | %s | %s | %s |" % [k, r[0], r[1], r[2], r[3], r[4]])
	quit()
