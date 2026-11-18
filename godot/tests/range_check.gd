extends SceneTree
## PRO-212: абляции и кандидаты ограничения дальности. godot --headless --path godot --script res://tests/range_check.gd
## Без варианта — прежние числа; каждая абляция снимает ровно свою часть и не трогает остальное.

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


func defs() -> Dictionary:
	var out := {}
	for kind in TDConfig.TOWERS:
		for lvl in [1, 2, 3]:
			for br in (["a", "b"] if lvl == 3 else [""]):
				out["%s%d%s" % [kind, lvl, br]] = TDConfig.tower_def(kind, lvl, br)
	return out


func same_except(a: Dictionary, b: Dictionary, keys: Array) -> Array:
	var bad := []
	for id in a:
		for k in a[id]:
			if k in keys:
				continue
			if str(a[id][k]) != str(b[id].get(k)):
				bad.append("%s.%s" % [id, k])
	return bad


func _initialize() -> void:
	check("по умолчанию вариант дальности выключен", TDConfig.range_variant == "" and not TDConfig.track_zones)
	var base := defs()
	check("прежние числа: Снайпер «Дальнобой» 7.5, «Мортира» 4.3, Лучник L2 3.5",
		is_equal_approx(base["sniper3b"]["range"], 7.5) and is_equal_approx(base["cannon3a"]["range"], 4.3) and is_equal_approx(base["arrow2"]["range"], 3.5))
	check("прежний перк: +0.4 за уровень, максимум 2", TDConfig.perk_range_step() == 0.4 and TDConfig.perk_max(TDConfig.perk_def("range")) == 2)

	TDConfig.range_variant = "abl_norange"
	var d := defs()
	var rng_bad := []
	for id in d:
		if not is_equal_approx(d[id]["range"], TDConfig.TOWERS[d[id]["kind"]]["range"]):
			rng_bad.append(id)
	check("A · без прибавок дальности: у всех уровней и веток базовая дальность", rng_bad.is_empty(), ", ".join(rng_bad.slice(0, 4)))
	check("A · урон, перезарядка и прочее как без варианта", same_except(base, d, ["range"]).is_empty(), ", ".join(same_except(base, d, ["range"]).slice(0, 4)))
	check("A · перк дальности ничего не даёт", TDConfig.perk_range_step() == 0.0)

	TDConfig.range_variant = "abl_nodmg"
	d = defs()
	check("B · дальность как без варианта", same_except(base, d, ["damage", "cooldown"]).is_empty(), ", ".join(same_except(base, d, ["damage", "cooldown"]).slice(0, 4)))
	var up := []
	for id in d:
		var k: String = d[id]["kind"]
		if d[id]["damage"] > TDConfig.TOWERS[k]["damage"] + 1e-6 or d[id]["cooldown"] < TDConfig.TOWERS[k]["cooldown"] - 1e-6:
			up.append(id)
	check("B · улучшения не прибавляют урон и скорострельность", up.is_empty(), ", ".join(up.slice(0, 4)))
	check("B · снижения остаются («Залп» −25% урона за стрелу)", is_equal_approx(d["arrow3a"]["damage"], TDConfig.TOWERS["arrow"]["damage"] * 0.75))
	check("B · перк дальности как без варианта", TDConfig.perk_range_step() == 0.4)

	TDConfig.range_variant = "abl_noperk"
	d = defs()
	check("C · уровни и ветки как без варианта", same_except(base, d, []).is_empty())
	check("C · перк дальности ничего не даёт", TDConfig.perk_range_step() == 0.0 and TDConfig.perk_max(TDConfig.perk_def("range")) == 2)

	TDConfig.range_variant = "abl_nobranch"
	d = defs()
	check("D · «Дальнобой» 5.5 и «Мортира» 2.9 (без прибавки ветки, L2 остаётся)",
		is_equal_approx(d["sniper3b"]["range"], 5.5) and is_equal_approx(d["cannon3a"]["range"], 2.9))
	check("D · остальное как без варианта", same_except(base, d, ["range"]).is_empty() and is_equal_approx(d["arrow2"]["range"], 3.5))
	check("D · перк как без варианта", TDConfig.perk_range_step() == 0.4)

	for v in TDConfig.RANGE_VARIANTS:
		TDConfig.range_variant = v
		var rv: Dictionary = TDConfig.RANGE_VARIANTS[v]
		d = defs()
		check("%s · «Дальнобой» %.1f, «Мортира» %.1f" % [v, 5.5 + rv["sniper"], 2.9 + rv["cannon"]],
			is_equal_approx(d["sniper3b"]["range"], 5.5 + rv["sniper"]) and is_equal_approx(d["cannon3a"]["range"], 2.9 + rv["cannon"]))
		check("%s · всё остальное как без варианта" % v, same_except(base, d, []).filter(func(x): return not (x in ["sniper3b.range", "cannon3a.range"])).is_empty())
		check("%s · перк «Дальний прицел» до %d уровня" % [v, rv["perk_max"]], TDConfig.perk_max(TDConfig.perk_def("range")) == int(rv["perk_max"]))
		# в предложении перков «Дальний прицел» не появляется сверх максимума
		var g := TDGame.new(4243)
		g.perks["range"] = int(rv["perk_max"])
		var seen := false
		for i in 200:
			if "range" in g._draw_offer():
				seen = true
		check("%s · перк сверх максимума не предлагается" % v, not seen)
	TDConfig.range_variant = ""
	check("после проверок вариант снова выключен", same_except(base, defs(), []).is_empty())

	print("\nFAIL: %d" % failures if failures > 0 else "\nВсе проверки PRO-212 прошли")
	quit(1 if failures > 0 else 0)
