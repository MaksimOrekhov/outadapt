extends SceneTree
## Full mid-wave round trip, deterministic continuation and interrupted-write recovery.

var failures := 0

func check(label: String, condition: bool) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		failures += 1

func clean_snapshot(game: TDGame) -> Dictionary:
	var data := TDSave.snapshot(game)
	data.erase("timestamp")
	data.erase("saved_at")
	return data

func _initialize() -> void:
	TDSave.directory = "res://tests/.tmp_saves"
	var game := TDGame.new(7)
	game.gold = 10000
	var placed := 0
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if placed < TDConfig.TOWER_KINDS.size() and game.can_place(TDConfig.TOWER_KINDS[placed], x, y):
				game.place_tower(TDConfig.TOWER_KINDS[placed], x, y)
				placed += 1
	for tower in game.towers:
		game.upgrade_tower(tower)
		game.upgrade_tower(tower, "a")
	game.start_wave()
	for step in 80:
		game.step(1.0 / 60.0)
	check("wave has active enemies", not game.enemies.is_empty())
	var victim: TDGame.Enemy = game.enemies[0]
	victim.slow_t = 2.4
	victim.slow_factor = 0.4
	victim.scorch_t = 1.6
	victim.scorch_extra = 0.2
	victim.poison_t = 3.0
	victim.poison_dps = 0.7
	victim.hp += 50
	var poisoner: TDGame.Tower
	for tower in game.towers:
		if tower.kind == "poison":
			poisoner = tower
	victim.poison_by = poisoner
	var session := {"speed": 2, "acc": 0.004, "_run_id": "regression-run", "_run_points": 3}
	check("save writes to disk", TDSave.write(0, game, session) == OK)
	var data := TDSave.read(0)
	var restored := TDSave.restore(data)
	check("snapshot loads", restored != null)
	if restored == null:
		quit(1)
		return
	check("all simulation fields round trip", clean_snapshot(game) == clean_snapshot(restored))
	check("session state preserved", data["session"] == session)
	check("poison ownership reconnects to live tower", restored.enemies[0].poison_by == restored.tower_at(poisoner.x, poisoner.y))
	for step in 600:
		game.step(1.0 / 60.0)
		restored.step(1.0 / 60.0)
	check("continuation remains deterministic for 600 steps", clean_snapshot(game) == clean_snapshot(restored))
	var detached := TDGame.new(4)
	detached.gold = 1000
	var tower := TDGame.Tower.new()
	tower.id = 99
	tower.kind = "poison"
	tower.level = 3
	tower.branch = "a"
	tower.def = TDConfig.tower_def("poison", 3, "a")
	var enemy := TDGame.Enemy.new()
	enemy.id = 100
	enemy.genome = TDGenome.random_genome(detached.rng, 1)
	enemy.ph = TDGenome.phenotype(enemy.genome, 1)
	enemy.hp = enemy.ph["hp"]
	enemy.poison_by = tower
	enemy.poison_t = 2
	enemy.poison_dps = 1
	detached.enemies.append(enemy)
	var detached_copy := TDSave.restore(TDSave.snapshot(detached))
	check("poison from a sold tower retains ownership", detached_copy.enemies[0].poison_by != null and detached_copy.enemies[0].poison_by.id == 99 and detached_copy.towers.is_empty())
	check("unknown save version rejected", TDSave.restore({"version": 999}) == null)
	var choice := TDGame.new(42)
	choice.offer = ["shatter", "rapid", "bounty"]
	check("perk choice between waves is preserved", TDSave.restore(TDSave.snapshot(choice)).offer == choice.offer)
	var invalid_type := TDSave.snapshot(game)
	invalid_type["state"]["wave"] = "invalid"
	check("malformed field types rejected safely", not TDSave.valid(invalid_type))
	var malformed := TDSave.snapshot(game)
	malformed["waypoints"] = [Vector2i(0, 0), Vector2i(2, 3)]
	check("invalid diagonal route rejected before rasterizing", not TDSave.valid(malformed))
	game.gold += 1
	check("replacement keeps backup", TDSave.write(0, game, session) == OK and FileAccess.file_exists(TDSave.path_for(0) + ".bak"))
	var broken := FileAccess.open(TDSave.path_for(0), FileAccess.WRITE)
	broken.store_var({"version": -1})
	broken.close()
	check("previous complete snapshot recovered", not TDSave.read(0).is_empty() and TDSave.read(0)["state"]["gold"] != game.gold)
	TDMeta.credited_runs.clear()
	TDMeta.points = 0
	TDMeta.runs = 0
	TDMeta.wins = 0
	var first := TDMeta.claim_run("test-claim", 7, 10, 1, true, true)
	var second := TDMeta.claim_run("test-claim", 7, 10, 1, true, true)
	check("loading old save cannot duplicate meta rewards", first["total"] > 0 and second["total"] == 0 and TDMeta.runs == 1 and TDMeta.wins == 1)
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(TDSave.path_for(0) + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TDSave.directory))
	print("Save checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
