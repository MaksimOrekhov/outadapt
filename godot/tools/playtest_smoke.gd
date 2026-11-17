extends SceneTree
## PRO-115: смоук журнала плейтеста без окна. Оборона в духе стратегии владельца (лучники, снайперы, лёд, огонь)
## играет N волн на заданном сиде через тот же TDPlaytestLog, что и игра; журнал можно сразу прогнать через
## tests/playtest_summary.py и проверить протокол до живой сессии.
## Godot --headless --path . --script res://tools/playtest_smoke.gd -- --seed=1003 --waves=16 [--off] [--difficulty=hard] --out=<каталог>

const ORDER := ["arrow", "arrow", "frost", "sniper", "arrow", "ember", "sniper", "sniper", "poison", "sniper", "beacon", "arrow", "sniper", "frost", "sniper"]


func _initialize() -> void:
	var seed_v := 1003
	var waves := 16
	var model := TDStrains.MODEL
	var diff := "normal"
	var out := "user://playtest"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		elif a.begins_with("--waves="):
			waves = int(a.substr(8))
		elif a == "--off":
			model = ""
		elif a.begins_with("--difficulty="):
			diff = a.substr(13)
		elif a.begins_with("--out="):
			out = a.substr(6)
	TDPlaytestLog.directory = out
	var meta := {"difficulty": diff, "mode": "standard"}
	if model != "":
		meta["swarm_model"] = model
	var g := TDGame.new(seed_v, null, meta)
	var plog := TDPlaytestLog.new("smoke-%d-%s" % [seed_v, model if model != "" else "off"])
	plog.header(g, {"build": "smoke", "fixed_seed": seed_v, "workshop": false, "window": "headless"})
	var i := 0
	var logged := 0
	while g.wave <= waves and g.phase != "over":
		if g.phase == "build":
			if not g.offer.is_empty():
				g.choose_perk(g.offer[0])
			for _k in 4:
				if i >= ORDER.size():
					for t in g.towers:
						if g.can_upgrade(t):
							g.upgrade_tower(t, "b" if t.kind == "sniper" else "a")
					break
				var kind: String = ORDER[i]
				var placed := false
				# клетки у дороги в средней части пути: там башни бьют дольше всего
				for ci in range(int(g.map.order.size() * 0.25), g.map.order.size()):
					var c: Vector2i = g.map.order[ci]
					for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
						var p: Vector2i = c + d
						if not placed and g.can_place(kind, p.x, p.y):
							placed = g.place_tower(kind, p.x, p.y)
				if placed:
					i += 1
				else:
					break
			g.start_wave()
			plog.wave_started(g)
		g.step(1.0 / 30.0)
		if g.phase != "wave" and not g.reports.is_empty() and int(g.reports[g.reports.size() - 1]["wave"]) > logged:
			logged = int(g.reports[g.reports.size() - 1]["wave"])
			plog.wave_ended(g)
	plog.run_over(g)
	print(ProjectSettings.globalize_path(plog.path))
	quit()
