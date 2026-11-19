class_name TDAdvisor
extends RefCounted
## Подсказки для игрока: состав волны, советы, оценка башен.

## Сводка по следующей волне: всё, что игроку нужно знать до запуска.
static func wave_info(g: TDGame) -> Dictionary:
	var n: int = maxi(1, g.upcoming.size())
	var phs: Array = []
	var strain_n := {}
	for ge in g.upcoming:
		var ph := TDGenome.phenotype(g.lured_genome(ge), g.wave)
		# PRO-152: враги пакетов (только с флагом эксперимента; без флага ключа "strain" в геномах нет)
		var strain := String(ge.get("strain", ""))
		if strain != "":
			ph = TDStrains.apply_ph(ph, strain)
			strain_n[strain] = int(strain_n.get(strain, 0)) + 1
		phs.append(ph)
	var mean := func(key: String) -> float:
		var s := 0.0
		for p in phs:
			s += p[key]
		return s / n
	var fliers := 0
	var stealth := 0
	var splitters := 0
	var wards := 0
	var tough := 0.0
	for i in phs.size():
		if phs[i]["fly"]:
			fliers += 1
		if phs[i]["stealth"]:
			stealth += 1
		if phs[i].get("split", false):
			splitters += 1
		if phs[i].get("ward", false):
			wards += 1
		tough += g.upcoming[i]["tough"]
	return {
		"n": g.upcoming.size(),
		"fliers": fliers,
		"stealth": stealth,
		"split": splitters,
		"ward": wards,
		"regen": mean.call("regen"),
		"tough": tough / n,
		"boss": TDGenome.phenotype(g.upcoming_boss, g.wave) if not g.upcoming_boss.is_empty() else {},
		"boss_ability": TDConfig.boss_ability(g.wave) if not g.upcoming_boss.is_empty() else "",
		"boss_immune": String(g.upcoming_boss.get("immune_type", "")),
		"special": g.upcoming_special,
		"strains": strain_n,
		"avg": {
			"hp": mean.call("hp"), "speed": mean.call("speed"), "armor": mean.call("armor"),
			"fireRes": mean.call("fireRes"), "frostRes": mean.call("frostRes"), "regen": mean.call("regen"),
			"fly": false, "stealth": false, "size": 0.0,
		},
	}


static func _boss_ability_tip(info: Dictionary) -> String:
	var ab: Dictionary = TDConfig.BOSS_ABILITIES.get(info.get("boss_ability", ""), {})
	if ab.is_empty():
		return ""
	match info["boss_ability"]:
		"shield":
			return " «Панцирь»: у босса щит — пробей его бурстом, пока не подошёл к замку."
		"summon":
			return " «Призыватель»: четыре раза зовёт по трое быстрых — нужен урон по площади."
		"immune":
			return " «Зеркало»: почти не боится урона по %s — переключись на другой тип башен." % TDConfig.TYPE_NAMES.get(info["boss_immune"], info["boss_immune"])
	return ""


static func _chip(icon: String, text: String, color: String, title: String, short: String = "") -> Dictionary:
	return {"icon": icon, "text": text, "color": color, "title": title, "short": short}


## Короткие плашки состава волны: только то, что заметно.
static func wave_chips(info: Dictionary) -> Array:
	var chips: Array = []
	var avg: Dictionary = info["avg"]
	if not info["boss"].is_empty():
		var b: Dictionary = info["boss"]
		var ab: Dictionary = TDConfig.BOSS_ABILITIES.get(info.get("boss_ability", ""), {})
		var ab_text := ""
		if not ab.is_empty():
			ab_text = " Особенность «%s»: %s." % [ab["name"], ab["desc"]]
			if info["boss_ability"] == "immune":
				ab_text = " Особенность «Зеркало»: почти не боится урона по %s." % TDConfig.TYPE_NAMES.get(info["boss_immune"], info["boss_immune"])
		chips.append(_chip("boss", "БОСС · " + ab["name"] if not ab.is_empty() else "БОСС", "#ff6b7a",
			"Копирует твою защиту: броня %.1f, огнестойкость %d%%, морозостойкость %d%%.%s Прорвавшийся босс стоит 5 жизней" % [b["armor"], round(b["fireRes"] * 100), round(b["frostRes"] * 100), ab_text]))
	if info.get("special", "") != "":
		var sp: Dictionary = TDConfig.SPECIAL_WAVES[info["special"]]
		chips.append(_chip("wave", "Особая: " + sp["name"], "#ffb347", sp["desc"] + ". За такую волну бонус золота ×1.5"))
	for p in TDStrains.PACKAGES:
		var sn: int = int(info.get("strains", {}).get(p, 0))
		if sn > 0:
			var pd: Dictionary = TDStrains.PACK[p]
			var body := "%d×%d" % [sn, TDStrains.BROOD_N] if p == "brood" else str(sn)
			var effect: String = String(pd["effect"]) % TDStrains.BROOD_N if p == "brood" else String(pd["effect"])
			var chip := _chip(pd["icon"], "%s %s" % [pd["name"], body], pd["color"],
				"Ответ роя на твою оборону: %s. Чем отвечать: %s" % [effect, pd["answer"]], body)
			# PRO-191: «Следом» подменяет подсказку текстом карточки угрозы с конкретными башнями
			chip["id"] = "strain:" + p
			chips.append(chip)
	if info["fliers"] > 0:
		chips.append(_chip("gene-wings", "%d летит" % info["fliers"], "#9ad7ff", "Летающие идут напрямик, минуя дорогу", str(info["fliers"])))
	if info.get("split", 0) > 0:
		chips.append(_chip("gene-split", "%d делятся" % info["split"], "#e08af0", "Убитые распадаются на двух малышей: нужен урон по площади", str(info["split"])))
	if info.get("ward", 0) > 0:
		chips.append(_chip("gene-ward", "%d со щитом" % info["ward"], "#8fd0ff", "Носитель щита прикрывает соседей: −30% урона по ним. Выбей его первым", str(info["ward"])))
	if info["stealth"] > 0:
		chips.append(_chip("gene-veil", "%d невидимых" % info["stealth"], "#c9a0ff", "Невидимы: башни бьют их, только если враг вплотную (около 1 клетки) или рядом с Маяком", str(info["stealth"])))
	if avg["armor"] >= 1.5:
		chips.append(_chip("gene-plated", "броня %.1f" % avg["armor"], "#b9c2d0", "Гасит физический урон, лучники теряют больше всех. Огонь и яд идут сквозь броню", "%.1f" % avg["armor"]))
	if info["regen"] >= 0.1 * 0.08:
		chips.append(_chip("gene-regen", "лечатся", "#7ddc5a", "Восстанавливают здоровье на ходу; яд это останавливает"))
	if avg["fireRes"] >= 0.2:
		chips.append(_chip("gene-ember", "огнестойкие", "#ef6a3c", "Огонь бьёт слабее"))
	if avg["frostRes"] >= 0.2:
		chips.append(_chip("gene-frost", "морозостойкие", "#62bdf0", "Лёд бьёт и замедляет слабее"))
	if avg["speed"] >= 1.6:
		chips.append(_chip("gene-swift", "быстрые", "#ffd35a", "Быстро пробегают зону обстрела"))
	if info["tough"] >= 0.45:
		chips.append(_chip("gene-tough", "крепкие", "#ff7a8a", "Много здоровья"))
	return chips


## Какая часть дороги обстреливается: {uncovered: Dictionary<Vector2i,bool>, pct: float}
static func road_coverage(g: TDGame) -> Dictionary:
	var shooters: Array = []
	for t in g.towers:
		if not t.def.has("aura"):
			shooters.append([Vector2(t.x + 0.5, t.y + 0.5), g.t_range(t)])
	var uncovered := {}
	var total := 0
	for c in g.map.road_cells():
		total += 1
		var center := Vector2(c.x + 0.5, c.y + 0.5)
		var covered := false
		for s in shooters:
			if s[0].distance_to(center) <= s[1]:
				covered = true
				break
		if not covered:
			uncovered[c] = true
	return {"uncovered": uncovered, "pct": 1.0 - float(uncovered.size()) / total if total > 0 else 1.0}


## PRO-213: покрытие каждой дороги на карте с развилкой — доля её собственных клеток (без общего ствола и участка
## у замка), которые обстреливает хоть одна наземная башня. [{id, name, share, pct}]; на карте с одним путём — [].
static func route_coverage(g: TDGame) -> Array:
	if not g.map.is_multi():
		return []
	var shooters: Array = []
	for t in g.towers:
		if not t.def.has("aura") and t.def["ground"]:
			shooters.append([Vector2(t.x + 0.5, t.y + 0.5), g.t_range(t)])
	var out: Array = []
	for r in g.map.routes:
		var own := 0
		var hit := 0
		for c in r.order:
			if g.map.routes_at(c).size() > 1:
				continue
			own += 1
			var center := Vector2(c.x + 0.5, c.y + 0.5)
			for s in shooters:
				if s[0].distance_to(center) <= s[1]:
					hit += 1
					break
		out.append({"id": r.id, "name": route_name(g.map, r.id), "share": route_share(g.map, r.id), "pct": float(hit) / maxi(1, own)})
	return out


## Название дороги по положению на карте: «северная» / «южная» (по средней строке её собственных клеток).
static func route_name(map: TDMap, rid: int) -> String:
	var ys := []
	for r in map.routes:
		var sum := 0.0
		var n := 0
		for c in r.order:
			if map.routes_at(c).size() == 1:
				sum += c.y
				n += 1
		ys.append(sum / maxi(1, n))
	if map.routes.size() == 2:
		return "северная" if ys[rid] <= ys[1 - rid] else "южная"
	return "дорога %d" % (rid + 1)


## Доля врагов волны на дороге по шаблону карты (фиксирована, от обороны не зависит).
static func route_share(map: TDMap, rid: int) -> float:
	var n := 0
	for k in map.route_plan:
		if k == rid:
			n += 1
	return float(n) / maxi(1, map.route_plan.size())


static func _tip(icon: String, color: String, level: String, towers: Array, title: String, text: String) -> Dictionary:
	return {"icon": icon, "color": color, "level": level, "towers": towers, "title": title, "text": text}


## Что сделать прямо сейчас, по порядку важности (не больше 3).
static func advice(g: TDGame, info: Dictionary) -> Array:
	var out: Array = []
	var avg: Dictionary = info["avg"]
	if not info["boss"].is_empty():
		var b: Dictionary = info["boss"]
		var parts: Array[String] = ["броня %.1f" % b["armor"]]
		if b["fireRes"] >= 0.15:
			parts.append("огнестойкость %d%%" % round(b["fireRes"] * 100))
		if b["frostRes"] >= 0.15:
			parts.append("морозостойкость %d%%" % round(b["frostRes"] * 100))
		out.append(_tip("boss", "#ff6b7a", "danger", ["poison", "sniper", "cannon"], "Босс — зеркало твоей защиты",
			"Копирует то, чем ты бил: %s. Яд и Снайпер идут сквозь сопротивления. Прорвётся — минус 5 жизней.%s" % [", ".join(parts), _boss_ability_tip(info)]))
	# PRO-152/191: пакет роя в ближайшей волне или объявленный — те же слова и башни, что в отчёте о волне (TDThreats)
	if TDStrains.enabled(g.meta):
		for c in TDThreats.cards(g, info):
			if c.has("strain") and String(c["status"]) in ["next", "dated", "active"]:
				out.append(_tip(c["icon"], c["color"], "danger" if int(c["count"]) > 0 else "tip", c["towers"],
					c["title"], "%s. %s" % [c["when"], c["effect"]]))
	var anti := 0
	for k in ["arrow", "ember", "frost", "sniper", "poison", "flak", "tesla"]:
		anti += g.count_of(k)

	# PRO-213: на карте с развилкой — две дороги; доля врагов на каждой фиксирована (рой направление не выбирает)
	var rc := route_coverage(g)
	if not rc.is_empty():
		var weak: Dictionary = rc[0]
		var strong: Dictionary = rc[0]
		for x in rc:
			if x["pct"] < weak["pct"]:
				weak = x
			if x["pct"] > strong["pct"]:
				strong = x
		var split_text := "Враги идут по двум дорогам по очереди: %d%% — по северной, %d%% — по южной." % [
			round(100.0 * float(rc[0]["share"] if rc[0]["name"] == "северная" else rc[1]["share"])),
			round(100.0 * float(rc[0]["share"] if rc[0]["name"] == "южная" else rc[1]["share"]))]
		if g.towers.size() >= 2 and weak["pct"] < 0.35 and strong["pct"] - weak["pct"] >= 0.3:
			out.append(_tip("target", "#ff8d8d", "danger", ["arrow", "sniper"], "Открыта %s дорога" % weak["name"],
				"%s %s обстреливается лишь на %d%% — строй и у неё." % [split_text, String(weak["name"]).capitalize(), round(100.0 * float(weak["pct"]))]))
		elif g.wave <= 3:
			out.append(_tip("info", "#9fb4d4", "tip", ["arrow", "sniper"], "Две дороги", split_text + " Башня у развилки достаёт обе."))
	var cov := road_coverage(g)
	if g.towers.size() >= 3 and cov["pct"] < 0.65:
		out.append(_tip("target", "#ff8d8d", "danger", ["arrow", "sniper"], "Дыры в обороне",
			"%d%% дороги никто не обстреливает (красные клетки). Враги пройдут их безнаказанно: строй у красных участков или бери Снайпера." % round((1.0 - cov["pct"]) * 100)))

	if info["stealth"] > 0 and g.count_of("beacon") == 0:
		out.append(_tip("gene-veil", "#c9a0ff", "danger", ["beacon"], "Невидимки",
			"%d врагов не видны башням: бьют их только те, что стоят вплотную к дороге. Поставь Маяк у дороги." % info["stealth"]))
	if info["fliers"] > 0:
		var lvl := "danger" if anti == 0 or (g.count_of("flak") == 0 and info["fliers"] >= 4) else "tip"
		out.append(_tip("gene-wings", "#9ad7ff", lvl, ["flak", "arrow", "sniper"], "Летающие",
			"%d летят напрямик через карту. Пушки по ним не бьют." % info["fliers"]))
	if info.get("ward", 0) > 0:
		out.append(_tip("gene-ward", "#8fd0ff", "tip", ["sniper", "tesla"], "Щитоносцы",
			"%d врагов прикрывают соседей щитом (−30%% урона). Снайпер и Тесла достают носителя первым." % info["ward"]))
	if info.get("split", 0) > 0:
		out.append(_tip("gene-split", "#e08af0", "tip", ["cannon", "tesla", "flak"], "Деление",
			"%d врагов при смерти распадаются на двоих. Урон по площади и цепная молния чистят малышей." % info["split"]))
	if avg["armor"] >= 2.0:
		out.append(_tip("gene-plated", "#b9c2d0", "tip", ["cannon", "sniper", "ember"], "Броня",
			"Слабые удары почти не проходят. Нужен тяжёлый урон или огонь, который плавит броню."))
	if info["regen"] * 100.0 >= 0.8:
		out.append(_tip("gene-regen", "#7ddc5a", "tip", ["poison"], "Лечение", "Враги восстанавливаются. Яд останавливает лечение."))
	if avg["fireRes"] >= 0.25:
		out.append(_tip("gene-ember", "#ef6a3c", "tip", ["arrow", "frost", "cannon"], "Огнестойкие", "Огонь слабеет. Лучше лёд и физический урон."))
	if avg["frostRes"] >= 0.25:
		out.append(_tip("gene-frost", "#62bdf0", "tip", ["ember", "arrow", "cannon"], "Морозостойкие", "Лёд почти не замедляет. Лучше огонь и физический урон."))
	if avg["speed"] >= 1.7:
		out.append(_tip("gene-swift", "#ffd35a", "tip", ["frost", "sniper"], "Быстрые", "Пробегают зону обстрела за пару секунд. Замедляй их льдом."))
	if out.is_empty():
		var has: bool = g.towers.size() > 0
		out.append(_tip("info", "#9fb4d4", "tip", ["arrow", "frost", "ember"],
			"Рой пока без особенностей" if has else "Начни с простого",
			"Смешивай башни: лёд и огонь усиливают лучников." if has else "Лучники, лёд и огонь — хорошее начало. Лёд и огонь усиливают физический урон."))
	return out.slice(0, 3)


## Ближайшая новая угроза, о которой пора знать заранее ({} — нет).
static func next_threat(g: TDGame) -> Dictionary:
	var labels := {"regen": "лечение", "wings": "летающие", "veil": "невидимки"}
	var best := {}
	for gene in TDGenome.UNLOCK_WAVE:
		var in_waves: int = int(TDGenome.UNLOCK_WAVE[gene]) - g.wave
		if in_waves > 0 and in_waves <= 3 and (best.is_empty() or in_waves < best["inWaves"]):
			best = {"icon": "gene-%s" % gene, "inWaves": in_waves, "label": labels.get(gene, gene)}
	# босс считаем самым важным при равном сроке
	var to_boss: int = int(ceil(float(g.wave) / TDConfig.BOSS_EVERY)) * TDConfig.BOSS_EVERY - g.wave
	if to_boss > 0 and to_boss <= 3 and (best.is_empty() or to_boss <= best["inWaves"]):
		best = {"icon": "boss", "inWaves": to_boss, "label": "БОСС"}
	return best


## Оценка 0–5 звёзд: насколько башня полезна именно против следующей волны на каждую монету.
## Возвращает {kind: {stars, note}}.
static func rate_towers(g: TDGame, info: Dictionary) -> Dictionary:
	var m := g.mods()
	var n: int = info["n"]
	var fl_frac: float = float(info["fliers"]) / n if n > 0 else 0.0
	var st_frac: float = float(info["stealth"]) / n if n > 0 else 0.0
	var has_beacon: bool = g.count_of("beacon") > 0
	# связки: лёд и огонь ценны настолько, сколько физических башен они усиливают,
	# и тем меньше, чем больше таких же уже стоит
	var phys := 0
	for k in ["arrow", "cannon", "sniper", "flak"]:
		phys += g.count_of(k)
	var armor: float = info["avg"]["armor"]
	var frost_util: float = minf(3.0, 1.0 + 0.5 * phys / (g.count_of("frost") + 1.0))
	var ember_util: float = minf(3.0, 1.0 + (0.3 + 0.25 * armor) * phys / (g.count_of("ember") + 1.0))
	# физическим башням нужны лёд и огонь рядом: без них они теряют часть ценности
	var support: float = float(g.count_of("frost") + g.count_of("ember"))
	var phys_util: float = 0.75 + 0.25 * minf(1.0, support / maxf(1.0, phys / 3.0))
	var util := {
		"arrow": phys_util, "cannon": 2.0 * phys_util, "ember": ember_util, "frost": frost_util,
		"sniper": 1.5 * phys_util, "poison": 1.0 + info["regen"] * 40.0, "flak": 2.0 * phys_util, "beacon": 0.0,
		"tesla": 1.8 + 0.5 * minf(1.0, float(g.count_of("frost")) / 2.0),
	}

	var scores := {}
	var best := 0.0
	for kind in TDConfig.TOWER_KINDS:
		var def: Dictionary = TDConfig.TOWERS[kind]
		if def.has("aura"):
			continue
		var dmg := g.damage_of(kind)
		var cd := g.cooldown_of(kind)
		var reach: float = (1.0 - fl_frac if def["ground"] else 0.0) + (fl_frac if def["air"] else 0.0)
		reach *= 1.0 - st_frac * (0.0 if has_beacon else 0.6)
		var per: float
		if def["type"] == "poison":
			per = def["damage"] + TDConfig.POISON_DPS * (dmg / def["damage"]) * minf(TDConfig.POISON_DURATION, cd)
		else:
			per = TDGame.effective_damage(dmg, def["type"], info["avg"], {}, m, def.get("pierce", 0.0))
		var pct: float = 1.0 if def["type"] == "poison" else per / dmg
		var score: float = (reach * float(util.get(kind, 1.0)) * (per / cd)) / g.tower_cost(kind)
		scores[kind] = {"score": score, "reach": reach, "pct": pct}
		best = maxf(best, score)

	var out := {}
	for kind in TDConfig.TOWER_KINDS:
		var def: Dictionary = TDConfig.TOWERS[kind]
		if def.has("aura"):
			if info["stealth"] > 0:
				out[kind] = {"stars": 5, "note": "нужен: есть невидимки"}
			else:
				out[kind] = {"stars": 2, "note": "+25% скорость соседям"}
			continue
		var s: Dictionary = scores[kind]
		if s["reach"] < 0.05:
			out[kind] = {"stars": 0, "note": "летающих нет" if def["air"] and not def["ground"] else "все враги летят"}
			continue
		var stars: int = maxi(1, mini(5, int(round(5.0 * s["score"] / (best if best > 0.0 else 1.0)))))
		var note := ""
		if s["pct"] < 0.65:
			note = "сопротивления съедают %d%% урона" % round((1.0 - s["pct"]) * 100)
		elif kind == "poison" and info["regen"] * 100.0 >= 0.8:
			note = "остановит лечение"
		out[kind] = {"stars": stars, "note": note}
	return out


# ── Адаптация роя: что изменилось, почему и чем ответить ──────────

## Какой урон толкает рой к какому гену (`TDGenome.TYPE_GENE`), словами для игрока.
const ADAPT_WHY := {"plated": "физический урон", "ember": "огонь", "frost": "лёд", "tough": "яд и молния"}
## Сдвиг среднего значения гена, начиная с которого говорим «вырос/упал».
const SHIFT_MIN := 0.03
## Доля урона данного типа, начиная с которой говорим «ты бил этим».
const PRESSURE_MIN := 0.25


## Башни, на которые ген не действует (урон проходит ≥ 80%), лучшие по урону в секунду на монету.
## Считается по формулам урона, а не списком вручную, поэтому подсказка не расходится с боевой моделью.
## Для здоровья ответа по типу урона нет (пусто).
static func counters(gene: String, limit: int = 3) -> Array:
	if not gene in ["plated", "ember", "frost"]:
		return []
	var g_hi := {}
	var g_lo := {}
	for k in TDGenome.GENES:
		g_hi[k] = 1.0 if k == gene else 0.0
		g_lo[k] = 0.0
	var hi := TDGenome.phenotype(g_hi, 1)
	var lo := TDGenome.phenotype(g_lo, 1)
	var scored: Array = []
	for kind in TDConfig.TOWER_KINDS:
		var def: Dictionary = TDConfig.TOWERS[kind]
		if def.has("aura") or def.get("net", false) or not def["ground"] or float(def["damage"]) <= 0.0:
			continue
		var base := TDGame.effective_damage(float(def["damage"]), def["type"], lo, {}, {}, float(def.get("pierce", 0.0)))
		var against := TDGame.effective_damage(float(def["damage"]), def["type"], hi, {}, {}, float(def.get("pierce", 0.0)))
		if def["type"] == "poison":
			against = base
		var pct: float = against / base if base > 0.0 else 0.0
		if pct >= 0.8:
			scored.append([kind, base * pct / float(def["cooldown"]) / float(def["cost"])])
	scored.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array = []
	for x in scored.slice(0, limit):
		out.append(x[0])
	return out


## Объяснение последнего шага эволюции: по каждому гену, который заметно изменился или на который давили.
## verdict: new — новый признак по расписанию; pressure — ты бил этим типом и ген вырос; drift — вырос без давления
## (отбор и мутации); resisted — давил, но ген не вырос (отбор и лимит роя сильнее); fading — ген ослаб, этим типом почти не били;
## vaccine — рост сдержан вакциной.
static func adaptation(g: TDGame) -> Array:
	if g.reports.is_empty():
		return []
	var r: Dictionary = g.reports[g.reports.size() - 1]
	var mult: float = float(TDConfig.difficulty(g.meta)["adapt"])
	var out: Array = []
	for k in TDGenome.GENES:
		var d: float = float(r["nextAvg"][k]) - float(r["avg"][k])
		var share: float = float(r["pressure"].get(k, 0.0))
		var verdict := ""
		if g.vaccine.get("gene", "") == k and d < SHIFT_MIN:
			verdict = "vaccine"
		elif int(TDGenome.UNLOCK_WAVE.get(k, -1)) == int(r["wave"]) + 1 and d >= SHIFT_MIN:
			verdict = "new"
		elif d >= SHIFT_MIN:
			verdict = "pressure" if share >= PRESSURE_MIN else "drift"
		elif share >= PRESSURE_MIN:
			verdict = "resisted"
		elif d <= -2.0 * SHIFT_MIN and ADAPT_WHY.has(k) and share < 0.1:
			verdict = "fading"
		if verdict == "":
			continue
		out.append({"gene": k, "delta": d, "share": share, "push": TDGenome.ADAPT * share * mult, "verdict": verdict,
			"why": ADAPT_WHY.get(k, ""), "counters": counters(k) if verdict in ["pressure", "resisted", "drift"] else []})
	var order := {"pressure": 0, "new": 1, "resisted": 2, "drift": 3, "vaccine": 4, "fading": 5}
	out.sort_custom(func(a, b):
		if order[a["verdict"]] != order[b["verdict"]]:
			return order[a["verdict"]] < order[b["verdict"]]
		return absf(a["delta"]) > absf(b["delta"]))
	return out


## Одна строка про запись из `adaptation()`: без обещаний, которых нет в данных.
static func adaptation_line(e: Dictionary) -> String:
	var label: String = TDGenome.GENE_LABELS[e["gene"]]
	var pct := roundi(absf(e["delta"]) * 100.0)
	var share := roundi(e["share"] * 100.0)
	match e["verdict"]:
		"pressure":
			return "▲ %s +%d%% — ты бил: %s, %d%% урона" % [label, pct, e["why"], share]
		"new":
			return "▲ %s +%d%% — новый признак по расписанию" % [label, pct]
		"drift":
			return "▲ %s +%d%% — отбор и мутации, давления нет" % [label, pct]
		"resisted":
			return "▬ %s без роста, хотя ты бил: %s, %d%% урона — рост сдержали отбор и лимит роя" % [label, e["why"], share] if e["delta"] > -SHIFT_MIN else "▼ %s −%d%%, хотя ты бил: %s, %d%% урона — отбор и лимит роя сильнее давления" % [label, pct, e["why"], share]
		"fading":
			return "▼ %s −%d%% — этим типом ты почти не бил" % [label, pct]
		"vaccine":
			return "▬ %s: рост блокирует вакцина" % label
	return ""
