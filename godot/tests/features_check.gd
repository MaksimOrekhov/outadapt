extends SceneTree
## Проверка новых механик: особые волны, способности боссов, сложность, режимы, сохранение.

var bad := 0

func check(name: String, ok: bool, extra := "") -> void:
	print("%s %s %s" % ["OK  " if ok else "FAIL", name, extra])
	if not ok:
		bad += 1


func _boss_game(wave: int, meta := {}) -> TDGame:
	var g := TDGame.new(5, null, meta)
	g.wave = wave
	g.gold = 5000
	g.upcoming_boss = g._make_boss(TDGame._zero_damage())
	g.upcoming = [TDGenome.random_genome(g.rng, wave), TDGenome.random_genome(g.rng, wave)]
	g.start_wave()
	for i in 600:
		g.step(0.05)
		if not g.enemies.is_empty() and g.enemies.any(func(e): return e.boss):
			break
	return g


func _finished(g: TDGame, wave: int) -> Array:
	var out := []
	for i in 6:
		out.append({"genome": TDGenome.random_genome(g.rng, wave), "fitness": 0.5})
	return out


func _initialize() -> void:
	check("особые волны", TDConfig.special_for(5) == "swarm" and TDConfig.special_for(15) == "rush" and TDConfig.special_for(25) == "heavy" and TDConfig.special_for(10) == "" and TDConfig.special_for(20) == "" and TDConfig.special_for(4) == "")
	check("способности боссов", TDConfig.boss_ability(10) == "shield" and TDConfig.boss_ability(20) == "summon" and TDConfig.boss_ability(30) == "immune" and TDConfig.boss_ability(40) == "shield")

	var hard := TDGame.new(1, null, {"difficulty": "hard"})
	var easy := TDGame.new(1, null, {"difficulty": "easy"})
	var norm := TDGame.new(1)
	check("сложность: жизни и золото", hard.lives == norm.lives - 8 and easy.lives == norm.lives + 8 and hard.gold == norm.gold - 30 and easy.gold == norm.gold + 40, "%d/%d/%d" % [hard.lives, norm.lives, easy.lives])

	var locked := TDGame.new(1, null, {"locked": ["tesla"]})
	locked.gold = 999
	check("закрытая башня не строится", not locked.can_place("tesla", 0, 0) and locked.place_problem("tesla", 0, 0) != "" and locked.can_place("arrow", 0, 0) == (not locked.map.is_path(0, 0) and not locked.map.is_blocked(0, 0)))

	# щит
	var g := _boss_game(10)
	var b: TDGame.Enemy = g.enemies.filter(func(e): return e.boss)[0]
	check("босс 10: щит", b.ability == "shield" and b.shield > 0.0 and absf(b.shield - b.ph["hp"] * TDConfig.SHIELD_SHARE) < 1.0, "щит %.0f / hp %.0f" % [b.shield, b.hp])
	g.place_tower("arrow", 0, 0) if g.can_place("arrow", 0, 0) else null
	var tw := TDGame.Tower.new()
	tw.kind = "arrow"
	tw.def = TDConfig.tower_def("arrow", 1, "")
	tw.id = 99
	var hp0 := b.hp
	var sh0 := b.shield
	g._hit(b, tw, g.mods())
	check("щит гасит урон", b.shield < sh0 and absf(b.hp - hp0) < 0.001, "щит %.1f→%.1f" % [sh0, b.shield])
	b.shield = 0.0
	g._hit(b, tw, g.mods())
	check("без щита урон проходит", b.hp < hp0)

	# призыв
	var g2 := _boss_game(20)
	var b2: TDGame.Enemy = g2.enemies.filter(func(e): return e.boss)[0]
	var n0 := g2.enemies.size()
	for i in 200:
		g2.step(0.05)
	var minions: int = g2.enemies.filter(func(e): return e.child).size()
	check("босс 20: призывает", b2.ability == "summon" and minions >= TDConfig.SUMMON_COUNT, "прислужников %d" % minions)

	# невосприимчивость
	var g3 := _boss_game(30)
	var b3: TDGame.Enemy = g3.enemies.filter(func(e): return e.boss)[0]
	check("босс 30: зеркало", b3.ability == "immune" and b3.immune_type == "physical", b3.immune_type)
	var hp_a := b3.hp
	g3._hit(b3, tw, g3.mods())
	var lost_phys := hp_a - b3.hp
	b3.hp = hp_a
	var ember := TDGame.Tower.new()
	ember.kind = "ember"
	ember.def = TDConfig.tower_def("ember", 1, "")
	ember.id = 98
	g3._hit(b3, ember, g3.mods())
	check("иммунитет режет урон нужного типа", lost_phys > 0.0 and lost_phys < tw.def["damage"] * 0.5, "физ. потеря %.2f" % lost_phys)

	# особая волна: нашествие
	var g4 := TDGame.new(3)
	g4.wave = 4
	g4.upcoming = []
	for i in 14:
		g4.upcoming.append(TDGenome.random_genome(g4.rng, 4))
	g4.finished = _finished(g4, 4)
	g4.phase = "wave"
	g4._end_wave()
	check("волна 5 — нашествие больше обычной", g4.upcoming_special == "swarm" and g4.upcoming.size() > TDConfig.wave_size(5), "врагов %d (обычно %d)" % [g4.upcoming.size(), TDConfig.wave_size(5)])

	# бесконечный режим: победа не наступает
	var g5 := TDGame.new(3, null, {"mode": "endless"})
	g5.wave = TDConfig.VICTORY_WAVE
	g5.upcoming = [TDGenome.random_genome(g5.rng, 30)]
	g5.finished = _finished(g5, 30)
	g5.phase = "wave"
	g5._end_wave()
	var g6 := TDGame.new(3)
	g6.wave = TDConfig.VICTORY_WAVE
	g6.upcoming = [TDGenome.random_genome(g6.rng, 30)]
	g6.finished = _finished(g6, 30)
	g6.phase = "wave"
	g6._end_wave()
	check("бесконечный режим без победы", not g5.victory and g6.victory)

	# сохранение с новыми полями
	var snap := TDSave.snapshot(g, {})
	var restored := TDSave.restore(snap)
	check("сохранение с боссом-щитоносцем", restored != null and restored.enemies.any(func(e): return e.ability == "shield"))
	var old := snap.duplicate(true)
	old["state"].erase("cur_special")
	old["state"].erase("upcoming_special")
	for e in old["enemies"]:
		for k in TDSave.OPTIONAL_ENEMY_FIELDS:
			e.erase(k)
	check("старое сохранение без новых полей грузится", TDSave.restore(old) != null)

	print("ГОТОВО: %d проблем" % bad)
	quit(1 if bad > 0 else 0)
