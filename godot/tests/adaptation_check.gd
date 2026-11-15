extends SceneTree
## Проверка объяснений адаптации: godot --headless --path godot --script res://tests/adaptation_check.gd
## 1) Ответные башни действительно не страдают от гена (по формулам урона).
## 2) Сообщения не противоречат данным: «вырос» только при росте, «давил» только при заметной доле урона.
## 3) Статистика: как часто старый текст («рой наращивает броню» при ≥30% физического) был бы неверен.

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		failures += 1
		print("FAIL  " + label + ("" if detail == "" else "  (" + detail + ")"))


## Конец волны без боя с заданным давлением; damage_by задаёт, чем «бил» игрок.
func finish_wave(g: TDGame, dmg: Dictionary) -> void:
	g.start_wave()
	g.finished = []
	for i in g.wave_genomes.size():
		g.finished.append({"genome": g.wave_genomes[i], "fitness": float(g.wave_genomes.size() - i)})
	g.pending = []
	g.enemies.clear()
	g.killed = g.wave_genomes.size()
	g.damage_by = TDGame._zero_damage()
	for k in dmg:
		g.damage_by[k] = dmg[k]
	g._end_wave()


func _initialize() -> void:
	# 1. ответные башни
	for gene in ["plated", "ember", "frost"]:
		var list := TDAdvisor.counters(gene)
		check("%s: есть ответные башни" % gene, list.size() > 0)
		for kind in list:
			var def: Dictionary = TDConfig.TOWERS[kind]
			var hi := {}
			var lo := {}
			for k in TDGenome.GENES:
				hi[k] = 1.0 if k == gene else 0.0
				lo[k] = 0.0
			var against := TDGame.effective_damage(def["damage"], def["type"], TDGenome.phenotype(hi, 1), {}, {}, float(def.get("pierce", 0.0)))
			var base := TDGame.effective_damage(def["damage"], def["type"], TDGenome.phenotype(lo, 1), {}, {}, float(def.get("pierce", 0.0)))
			check("%s: %s почти не страдает от гена" % [gene, kind], def["type"] == "poison" or against / base >= 0.8, "%.2f" % (against / base))
			check("%s: %s бьёт по земле" % [gene, kind], def["ground"])
	check("для здоровья ответа по типу урона нет", TDAdvisor.counters("tough").is_empty())
	var plated := TDAdvisor.counters("plated")
	check("против брони не предлагаются лучники", not plated.has("arrow"), str(plated))
	check("против огнестойкости не предлагается Огонь", not TDAdvisor.counters("ember").has("ember"))
	check("против морозостойкости не предлагается Лёд", not TDAdvisor.counters("frost").has("frost"))

	# 2. непротиворечивость сообщений на разных стратегиях
	var strategies := {
		"только физический": {"arrow": 70.0, "cannon": 30.0},
		"только огонь": {"ember": 100.0},
		"смесь": {"arrow": 30.0, "ember": 25.0, "frost": 25.0, "poison": 20.0},
		"лёд и молния": {"frost": 60.0, "tesla": 40.0},
	}
	var old_claims := 0
	var old_wrong := 0
	var total_lines := 0
	for strat in strategies:
		for s in 12:
			var g := TDGame.new(s * 31 + 5)
			for _w in 18:
				finish_wave(g, strategies[strat])
				var r: Dictionary = g.reports[g.reports.size() - 1]
				var entries := TDAdvisor.adaptation(g)
				for e in entries:
					total_lines += 1
					var d: float = e["delta"]
					var line := TDAdvisor.adaptation_line(e)
					check("%s: строка не пустая" % strat, line != "")
					match e["verdict"]:
						"pressure":
							check("pressure: ген вырос", d >= TDAdvisor.SHIFT_MIN, "%s %.3f" % [e["gene"], d])
							check("pressure: давление заметно", e["share"] >= TDAdvisor.PRESSURE_MIN)
							check("pressure: строка содержит ▲", line.begins_with("▲"))
						"new":
							check("new: ген вырос и есть в расписании", d >= TDAdvisor.SHIFT_MIN and TDGenome.UNLOCK_WAVE.has(e["gene"]))
						"drift":
							check("drift: давления нет", e["share"] < TDAdvisor.PRESSURE_MIN)
						"resisted":
							check("resisted: давление было", e["share"] >= TDAdvisor.PRESSURE_MIN)
							check("resisted: ген не вырос", d < TDAdvisor.SHIFT_MIN)
							check("resisted: строка не обещает рост", not line.begins_with("▲"))
						"fading":
							check("fading: ген упал", d <= -2.0 * TDAdvisor.SHIFT_MIN)
					if e["verdict"] in ["pressure", "drift", "new"]:
						check("рост и ответ: %s" % e["gene"], d > 0.0)
				# старый текст: «рой наращивает X» при доле давления ≥ 30%
				for gene in r["pressure"]:
					if r["pressure"][gene] >= 0.3 and gene in ["plated", "ember", "frost", "tough"]:
						old_claims += 1
						if float(r["nextAvg"][gene]) - float(r["avg"][gene]) < TDAdvisor.SHIFT_MIN:
							old_wrong += 1
	print("Строк объяснений проверено: %d" % total_lines)
	print("Старый текст «рой наращивает …» при давлении ≥30%%: %d случаев, из них ген не вырос (< +3%%): %d (%.0f%%)" % [old_claims, old_wrong, 100.0 * old_wrong / maxf(1.0, old_claims)])
	check("есть что проверять", total_lines > 100)

	# 3. вакцина отражается в объяснении
	var gv := TDGame.new(77)
	gv.gold = 1000
	for _w in 5:
		finish_wave(gv, {"arrow": 100.0})
	gv.buy_vaccine("plated")
	finish_wave(gv, {"arrow": 100.0})
	var kinds := {}
	for e in TDAdvisor.adaptation(gv):
		kinds[e["gene"]] = e["verdict"]
	check("под вакциной броня не помечена как выросшая", kinds.get("plated", "") != "pressure")
	print("Adaptation checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
