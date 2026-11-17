class_name TDThreats
extends RefCounted
## PRO-191: единый источник того, что игрок видит об эволюции роя: «что угрожает → когда → почему → что построить».
## Отчёт о волне, панель «Рой», советы, плашки «Следом», карточка врага и экран поражения берут текст отсюда,
## поэтому названия, сроки и башни-ответы везде совпадают. Только чтение состояния: бой, rng и сохранения не трогает.
##
## Карточка угрозы — словарь:
##   id      — "strain:hulk", "boss", "stealth", "unlock:veil", "trait:plated" и т.п.;
##   status  — next (в следующей волне), dated (известна волна появления), active (уже в бою), maybe (может появиться,
##             даты нет), fading (уходит), info (держится, но ты уже ответил — только в панели);
##   urgency — чем больше, тем выше в списке; главная зона отчёта берёт карточки с urgency ≥ MAIN_MIN;
##   title, when, why, effect — готовые фразы; пустая строка — не показывать;
##   towers  — 1–3 доступные башни-ответа; build — подпись перед ними; notes — уточнения к ответу;
##   count   — сколько таких врагов в следующей волне (по составу волны, не по доле).
## Тексты — цельные фразы с подстановкой чисел и списков имён: их можно перевести без сборки из кусков (PRO-122).

## Ниже этого порога карточка показывается только в панели «Рой», не в отчёте о волне.
const MAIN_MIN := 35
## В главной зоне отчёта не больше двух карточек: первая полная, вторая короткая.
const MAIN_MAX := 2
## Инкубация, начиная с которой «может появиться» попадает в отчёт (ниже — только в панели).
const MAYBE_MIN := 0.5

const STATUS_TEXT := {
	"next": "Следующая волна", "dated": "Скоро", "active": "Уже в бою", "maybe": "Может появиться",
	"fading": "Уходит", "info": "Без изменений",
}
const STATUS_ICON := {
	"next": "play", "dated": "wave", "active": "target", "maybe": "info", "fading": "info", "info": "info",
}

# ── Тексты пакетов роя (PRO-152) ─────────────────────────────────
const STRAIN_TEXT := {
	"brood": {
		"maybe": "Рой готовит защиту от тяжёлых выстрелов",
		"dated": "Скоро придёт Выводок",
		"next": "В следующей волне — Выводок",
		"active": "Выводок в бою",
		"fading": "Выводок отступает",
		"cause": "Больше всего урона у тебя наносят: %s",
		"cause_generic": "Твоя оборона держится на тяжёлых одиночных выстрелах",
		"cause_fading": "Ты меньше опираешься на тяжёлые выстрелы",
		"hurts_not": "Малышей в скорлупе не ранят: %s",
		"hurts_not_maybe": "Если появится Выводок, малышей в скорлупе не ранят: %s",
		"hurts_generic": "тяжёлые одиночные выстрелы (Снайпер, «Гарпун», «Стужа»)",
		"what": "Враги приходят кладками по %d малыша.",
	},
	"hulk": {
		"maybe": "Рой готовит защиту от лёгких ударов",
		"dated": "Скоро придут Панцирники",
		"next": "В следующей волне — Панцирники",
		"active": "Панцирники в бою",
		"fading": "Панцирники отступают",
		"cause": "Больше всего урона у тебя наносят: %s",
		"cause_generic": "Твоя оборона держится на лёгких одиночных ударах",
		"cause_fading": "Ты меньше опираешься на лёгкие удары",
		"hurts_not": "Их панцирь не пробивают: %s",
		"hurts_not_maybe": "Если появятся Панцирники, их панцирь не пробьют: %s",
		"hurts_generic": "лёгкие одиночные удары (стрелы, одиночный огонь)",
		"what": "Яд ранит сквозь панцирь, лёд всё равно замедляет.",
	},
	"flock": {
		"maybe": "Небо плохо защищено",
		"dated": "Скоро прилетит Стая",
		"next": "В следующей волне — Стая",
		"active": "Стая в бою",
		"fading": "Стая отступает",
		"cause": "",
		"cause_generic": "Путь полёта почти не прикрыт башнями, которые бьют по воздуху",
		"cause_fading": "Ты прикрыл путь полёта",
		"hurts_not": "",
		"hurts_not_maybe": "Если рой этим воспользуется, часть врагов полетит напрямик, мимо дороги",
		"hurts_generic": "",
		"what": "Часть врагов летит напрямик над картой, мимо дороги. Пушки по ним не бьют.",
	},
}


## Русское множественное число: plural(3, "враг", "врага", "врагов") → "врага".
static func plural(n: int, one: String, few: String, many: String) -> String:
	var a: int = absi(n) % 100
	if a >= 11 and a <= 14:
		return many
	match a % 10:
		1:
			return one
		2, 3, 4:
			return few
	return many


static func tower_name(kind: String) -> String:
	return String(TDConfig.TOWERS[kind]["name"])


static func names(kinds: Array) -> String:
	var out: Array[String] = []
	for k in kinds:
		out.append(tower_name(k) if TDConfig.TOWERS.has(k) else String(k))
	return ", ".join(out)


static func _card(id: String, status: String, urgency: int, icon: String, color: String, title: String) -> Dictionary:
	return {"id": id, "status": status, "urgency": urgency, "icon": icon, "color": color, "title": title,
		"when": "", "why": "", "effect": "", "towers": [], "build": "", "notes": [], "count": 0, "costs": {}}


## Башни из списка, которые не закрыты Мастерской, не больше limit; порядок списка сохраняется.
static func available(g: TDGame, kinds: Array, limit: int = 3) -> Array:
	var out: Array = []
	for k in kinds:
		if out.size() >= limit:
			break
		if TDConfig.TOWERS.has(k) and not g.is_locked(k) and not out.has(k):
			out.append(k)
	return out


# ── Пакеты роя ───────────────────────────────────────────────────

## Ранит ли удар этой башни врага пакета p: класс удара — по уровню и ветке (PRO-184); у яда тик идёт сквозь панцирь.
static func hurts(def: Dictionary, p: String) -> bool:
	if String(def.get("type", "")) == "poison":
		return true
	return not TDStrains.deflects(p, TDStrains.del_class(def))


## Твои башни, удары которых пакет гасит (имя, а для 3-го уровня — ещё и ветка).
static func blocked_towers(g: TDGame, p: String) -> Array[String]:
	var out: Array[String] = []
	if not TDStrains.DEFLECT.has(p):
		return out
	for t in g.towers:
		if t.def.has("aura") or float(t.def.get("damage", 0.0)) <= 0.0 or hurts(t.def, p):
			continue
		var label := tower_name(t.kind)
		if t.branch != "":
			label += " «%s»" % TDConfig.branch_def(t.kind, t.branch)["name"]
		if not out.has(label):
			out.append(label)
	return out


## Уточнения к ответу: какие ветки рекомендованной башни пакет всё же гасит («Лёд: кроме ветки «Стужа»»).
static func answer_notes(kinds: Array, p: String) -> Array[String]:
	var out: Array[String] = []
	for k in kinds:
		var bad: Array[String] = []
		for b in TDConfig.BRANCHES.get(k, []):
			if not hurts(TDConfig.tower_def(k, 3, b["id"]), p):
				bad.append("«%s»" % b["name"])
		if not bad.is_empty():
			out.append("%s: кроме ветки %s" % [tower_name(k), ", ".join(bad)])
	return out


## Самая ранняя волна, в которой пакет может появиться, если анонс случится в конце следующей волны.
static func earliest_wave(g: TDGame, p: String) -> int:
	return maxi(g.wave + TDStrains.LEAD, maxi(TDStrains.MIN_WAVE, int(TDStrains.PACK[p]["min_wave"])))


static func strain_count_text(p: String, n: int) -> String:
	match p:
		"brood":
			return "%d %s → %d %s" % [n, plural(n, "кладка", "кладки", "кладок"), n * TDStrains.BROOD_N, plural(n * TDStrains.BROOD_N, "малыш", "малыша", "малышей")]
		"hulk":
			return "%d %s" % [n, plural(n, "панцирник", "панцирника", "панцирников")]
		"flock":
			return "%d %s напрямик" % [n, plural(n, "враг летит", "врага летят", "врагов летят")]
	return str(n)


## Карточка по записи TDStrains.forecast(). Дата — только из состояния пакета: у «может появиться» её нет.
static func strain_card(g: TDGame, e: Dictionary) -> Dictionary:
	var p: String = e["id"]
	var tx: Dictionary = STRAIN_TEXT[p]
	var phase: String = e["phase"]
	var n: int = int(e["next_count"])
	var status := ""
	var urgency := 0
	match phase:
		"incubating":
			status = "maybe"
			urgency = 50 + roundi(10.0 * minf(1.0, float(e["inc"]))) if float(e["inc"]) >= MAYBE_MIN else 20
		"announced":
			status = "dated"
			urgency = 85
		"active":
			# впервые в следующей волне — самое срочное; дальше пакет уже знаком игроку
			var first: bool = int(g.strains["pk"][p].get("since", 0)) == g.wave
			status = "next" if first and n > 0 else ("active" if n > 0 else "info")
			urgency = 100 if status == "next" else (70 if n > 0 else 15)
		"fading":
			status = "fading"
			urgency = 45 if n > 0 else 15
	var c := _card("strain:" + p, status, urgency, e["icon"], e["color"], tx[status if status != "info" else "active"])
	c["strain"] = p
	c["count"] = n
	match status:
		"maybe":
			c["when"] = "Даты пока нет · не раньше волны %d" % earliest_wave(g, p)
		"dated":
			c["when"] = "Волна %d — после следующей" % int(e["appear"]) if int(e["appear"]) == g.wave + 1 else "Волна %d" % int(e["appear"])
		"next":
			c["when"] = strain_count_text(p, n)
		"active":
			c["when"] = "В следующей волне: %s" % strain_count_text(p, n)
		"fading":
			c["when"] = "В следующей волне: %s" % strain_count_text(p, n) if n > 0 else "В следующей волне их нет"
		"info":
			c["when"] = "В следующей волне их нет"
	# почему
	if status == "fading":
		c["why"] = tx["cause_fading"]
	else:
		var who: Array = TDStrains.culprits(g.strains, p)
		c["why"] = tx["cause"] % names(who) if not who.is_empty() and tx["cause"] != "" else tx["cause_generic"]
	# чем грозит
	if p == "flock":
		c["effect"] = tx["hurts_not_maybe"] if status == "maybe" else tx["what"]
	else:
		var mine := blocked_towers(g, p)
		var list: String = ", ".join(mine) if not mine.is_empty() else String(tx["hurts_generic"])
		var hurt: String = (tx["hurts_not_maybe"] if status == "maybe" else tx["hurts_not"]) % list
		c["effect"] = hurt + "." if status == "maybe" or p == "hulk" else (tx["what"] % TDStrains.BROOD_N) + " " + hurt + "."
		if p == "hulk" and status != "maybe":
			c["effect"] += " " + String(tx["what"])
	# что построить
	if status != "info" and not (status == "fading" and n == 0):
		c["towers"] = available(g, TDStrains.PACK[p]["answers"])
		c["notes"] = answer_notes(c["towers"], p)
		match status:
			"maybe":
				c["build"] = "Поставь у пути полёта:" if p == "flock" else "Подготовь:"
			"fading":
				c["build"] = "Пока они есть, помогут:"
			"dated":
				c["build"] = "Успей до волны %d:" % int(e["appear"])
			_:
				c["build"] = "Построй:"
	return c


# ── Прочие угрозы следующих волн ─────────────────────────────────

const UNLOCK_TEXT := {
	"regen": {"title": "Скоро враги начнут лечиться", "effect": "Раненые враги будут восстанавливать здоровье на ходу.", "towers": ["poison"]},
	"wings": {"title": "Скоро появятся летающие", "effect": "Летающие идут напрямик над картой. Пушки по ним не бьют.", "towers": ["flak", "arrow", "sniper"]},
	"veil": {"title": "Скоро появятся невидимки", "effect": "Башни видят невидимок только вплотную или рядом с Маяком.", "towers": ["beacon"]},
	"split": {"title": "Скоро появятся делящиеся", "effect": "Убитый враг распадается на двух малышей.", "towers": ["cannon", "tesla", "flak"]},
	"ward": {"title": "Скоро появятся щитоносцы", "effect": "Носитель щита прикрывает соседей: по ним проходит меньше урона.", "towers": ["sniper", "tesla"]},
}

## Признаки, которые заметно ослабляют часть башен: порог среднего фенотипа и ответ.
const TRAITS := {
	"plated": {"key": "armor", "min": 1.5, "title": "Враги обросли бронёй", "effect": "Лёгкие физические удары почти не проходят: Лучники теряют больше всех.", "type": "physical"},
	"ember": {"key": "fireRes", "min": 0.2, "title": "Враги стали огнестойкими", "effect": "Огонь бьёт заметно слабее.", "type": "fire"},
	"frost": {"key": "frostRes", "min": 0.2, "title": "Враги стали морозостойкими", "effect": "Лёд бьёт и замедляет слабее.", "type": "frost"},
	"swift": {"key": "speed", "min": 1.6, "title": "Враги стали быстрыми", "effect": "Быстро пробегают зону обстрела.", "type": ""},
}
const TRAIT_TOWERS := {"swift": ["frost", "sniper"]}


static func _boss_card(g: TDGame, in_waves: int) -> Dictionary:
	var wave_n: int = g.wave + in_waves
	var ab: Dictionary = TDConfig.BOSS_ABILITIES.get(TDConfig.boss_ability(wave_n), {})
	var nm: String = ("Босс «%s»" % ab["name"]) if not ab.is_empty() else "Босс"
	var towers: Array = ["poison", "sniper", "cannon"]
	var c: Dictionary
	if in_waves == 0:
		c = _card("boss", "next", 95, "boss", "#ff6b7a", "В следующей волне — %s" % nm)
		var immune := String(g.upcoming_boss.get("immune_type", "")) if TDConfig.boss_ability(wave_n) == "immune" else ""
		if immune != "":
			var keep: Array = []
			for k in towers + ["ember", "frost", "tesla", "arrow"]:
				if String(TDConfig.TOWERS[k]["type"]) != immune and not keep.has(k):
					keep.append(k)
			towers = keep
	else:
		c = _card("boss", "dated", 48, "boss", "#ff6b7a", ("Скоро придёт босс «%s»" % ab["name"]) if not ab.is_empty() else "Скоро придёт босс")
		c["when"] = "Волна %d" % wave_n
	c["why"] = "Босс копирует защиту, которую рой набрал против твоих башен."
	c["effect"] = ("%s. " % String(ab["desc"]) if not ab.is_empty() else "") + "Прорыв босса стоит %d жизней." % TDConfig.BOSS_LEAK
	c["towers"] = available(g, towers)
	c["build"] = "Построй:" if in_waves == 0 else "Успей до волны %d:" % wave_n
	return c


## Летающих в следующей волне без учёта «Стаи» (у неё своя карточка).
static func _fliers(g: TDGame, info: Dictionary) -> int:
	return int(info.get("fliers", 0)) - int(info.get("strains", {}).get("flock", 0))


static func _air_towers(g: TDGame) -> int:
	var n := 0
	for t in g.towers:
		if not t.def.has("aura") and bool(t.def["air"]) and float(t.def.get("damage", 0.0)) > 0.0:
			n += 1
	return n


## Все карточки, от самой срочной. info — TDAdvisor.wave_info(g) (пусто — посчитать).
static func cards(g: TDGame, info: Dictionary = {}) -> Array:
	if info.is_empty():
		info = TDAdvisor.wave_info(g)
	var out: Array = []
	if g.phase == "over":
		return out
	# пакеты роя (эксперимент PRO-152)
	for e in TDStrains.forecast(g):
		var sc := strain_card(g, e)
		if sc["status"] != "":
			out.append(sc)
	# босс
	if not g.upcoming_boss.is_empty():
		out.append(_boss_card(g, 0))
	else:
		var to_boss: int = int(ceil(float(g.wave) / TDConfig.BOSS_EVERY)) * TDConfig.BOSS_EVERY - g.wave
		if to_boss >= 1 and to_boss <= 2:
			out.append(_boss_card(g, to_boss))
	# особая волна
	if g.upcoming_special != "":
		var sp: Dictionary = TDConfig.SPECIAL_WAVES[g.upcoming_special]
		var c := _card("special", "next", 42, "wave", "#ffb347", "Следующая волна особая: %s" % sp["name"])
		c["effect"] = String(sp["desc"]) + "."
		out.append(c)
	# невидимки
	var st: int = int(info.get("stealth", 0))
	if st > 0:
		var has_beacon: bool = g.count_of("beacon") > 0
		var c2 := _card("stealth", "next" if not has_beacon else "info", 90 if not has_beacon else 25, "gene-veil", "#c9a0ff",
			"В следующей волне — невидимки")
		c2["count"] = st
		c2["when"] = "%d %s" % [st, plural(st, "невидимка", "невидимки", "невидимок")]
		c2["effect"] = "Башни видят их только вплотную или рядом с Маяком."
		if not has_beacon:
			c2["towers"] = available(g, ["beacon"])
			c2["build"] = "Поставь у дороги:"
		out.append(c2)
	# летающие
	var fl := _fliers(g, info)
	if fl > 0:
		var air := _air_towers(g)
		var weak: bool = air == 0 or (g.count_of("flak") == 0 and fl >= 4)
		var c3 := _card("fliers", "next" if weak else "info", 88 if weak else 25, "gene-wings", "#9ad7ff", "В следующей волне — летающие")
		c3["count"] = fl
		c3["when"] = "%d %s" % [fl, plural(fl, "враг летит", "врага летят", "врагов летят")]
		c3["why"] = "Ни одна твоя башня не бьёт по воздуху." if air == 0 else ""
		c3["effect"] = "Летят напрямик над картой. Пушки по ним не бьют."
		if weak:
			c3["towers"] = available(g, ["flak", "arrow", "sniper"])
			c3["build"] = "Построй:"
		out.append(c3)
	# делящиеся и щитоносцы: впервые в волне — заметно, дальше — только в панели
	for pair in [["split", "split"], ["ward", "ward"]]:
		var n: int = int(info.get(pair[1], 0))
		if n <= 0:
			continue
		var u: Dictionary = UNLOCK_TEXT[pair[0]]
		var first: bool = int(TDGenome.UNLOCK_WAVE[pair[0]]) == g.wave
		var c4 := _card("trait:" + pair[0], "next" if first else "info", 65 if first else 20, "gene-" + pair[0], "#e08af0" if pair[0] == "split" else "#8fd0ff",
			"В следующей волне — делящиеся" if pair[0] == "split" else "В следующей волне — щитоносцы")
		c4["count"] = n
		c4["when"] = "%d %s" % [n, plural(n, "враг делится", "врага делятся", "врагов делятся") if pair[0] == "split" else plural(n, "щитоносец", "щитоносца", "щитоносцев")]
		c4["effect"] = u["effect"]
		c4["towers"] = available(g, u["towers"])
		c4["build"] = "Помогут:"
		out.append(c4)
	# новые признаки по расписанию (дата известна точно)
	for gene in TDGenome.UNLOCK_WAVE:
		if not UNLOCK_TEXT.has(gene):
			continue
		var in_waves: int = int(TDGenome.UNLOCK_WAVE[gene]) - g.wave
		if in_waves < 1 or in_waves > 2:
			continue
		var u2: Dictionary = UNLOCK_TEXT[gene]
		var c5 := _card("unlock:" + gene, "dated", 46, "gene-" + gene, "#ffb347", u2["title"])
		c5["when"] = "Волна %d" % int(TDGenome.UNLOCK_WAVE[gene])
		c5["effect"] = u2["effect"]
		c5["towers"] = available(g, u2["towers"])
		c5["build"] = "Успей до волны %d:" % int(TDGenome.UNLOCK_WAVE[gene])
		out.append(c5)
	# признаки, которые только что перешли порог (что изменилось после этой волны)
	var r: Dictionary = g.reports[g.reports.size() - 1] if not g.reports.is_empty() else {}
	var prev_ph: Dictionary = TDGenome.phenotype(_full(r.get("avg", {})), int(r.get("wave", g.wave))) if not r.is_empty() else {}
	var avg: Dictionary = info.get("avg", {})
	for gene in TRAITS:
		var t: Dictionary = TRAITS[gene]
		var now: float = float(avg.get(t["key"], 0.0))
		if now < float(t["min"]):
			continue
		var was: float = float(prev_ph.get(t["key"], 0.0))
		# в отчёт — только если признак новый и задевает твои башни (их тип урона давал ≥ 15% урона прошлой волны)
		var fresh: bool = (prev_ph.is_empty() or was < float(t["min"])) and _type_share(r, String(t["type"])) >= 0.15
		var c6 := _card("trait:" + gene, "next" if fresh else "info", 44 if fresh else 20, "gene-" + gene, "#b9c2d0", t["title"])
		c6["when"] = "" if fresh else "Держится"
		c6["effect"] = t["effect"]
		var hit := _type_towers(g, r, String(t["type"]))
		if not hit.is_empty() and float(r.get("pressure", {}).get(gene, 0.0)) >= TDAdvisor.PRESSURE_MIN:
			c6["why"] = "Рой привыкает к твоему главному урону: %s" % names(hit)
		c6["towers"] = available(g, TRAIT_TOWERS.get(gene, TDAdvisor.counters(gene)))
		c6["build"] = "Помогут:"
		out.append(c6)
	out.sort_custom(func(a, b): return int(a["urgency"]) > int(b["urgency"]))
	for c in out:
		var costs := {}
		for k in c["towers"]:
			costs[k] = g.tower_cost(k)
		c["costs"] = costs
	return out


static func _full(avg: Dictionary) -> Dictionary:
	var out := {}
	for k in TDGenome.GENES:
		out[k] = float(avg.get(k, 0.0))
	return out


## Доля урона прошлой волны от башен данного типа ("" — признак задевает всех: 1).
static func _type_share(r: Dictionary, type: String) -> float:
	if type == "":
		return 1.0
	var by: Dictionary = r.get("damageBy", {})
	var total := 0.0
	var part := 0.0
	for k in by:
		total += float(by[k])
		if TDConfig.TOWERS.has(k) and String(TDConfig.TOWERS[k]["type"]) == type:
			part += float(by[k])
	return part / total if total > 0.0 else 0.0


## Башни данного типа урона, которые больше всех били в прошлой волне (для «почему»).
static func _type_towers(g: TDGame, r: Dictionary, type: String, limit: int = 2) -> Array:
	if type == "" or r.is_empty():
		return []
	var arr: Array = []
	var by: Dictionary = r.get("damageBy", {})
	for k in by:
		if TDConfig.TOWERS.has(k) and String(TDConfig.TOWERS[k]["type"]) == type and float(by[k]) > 0.0:
			arr.append([k, float(by[k])])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array = []
	for x in arr.slice(0, limit):
		out.append(x[0])
	return out


## Главная зона отчёта о волне: не больше MAIN_MAX карточек с urgency ≥ MAIN_MIN.
static func headline(all: Array) -> Array:
	var out: Array = []
	for c in all:
		if int(c["urgency"]) >= MAIN_MIN and out.size() < MAIN_MAX:
			out.append(c)
	return out


## Спокойное состояние, когда в главной зоне пусто.
static func calm_text(g: TDGame) -> String:
	return "Рой пока не готовит ответ на твою оборону." if TDStrains.enabled(g.meta) else "Следующая волна без новых особенностей."


## Короткая строка для подсказки (плашки «Следом», бейджи): заголовок, срок и ответ.
static func tip_text(c: Dictionary) -> String:
	var parts: Array[String] = [String(c["title"])]
	for k in ["when", "effect", "why"]:
		if String(c[k]) != "":
			parts.append(String(c[k]))
	if not c["towers"].is_empty():
		parts.append("%s %s" % [String(c["build"]) if String(c["build"]) != "" else "Ответ:", names(c["towers"])])
	return "\n".join(parts)


# ── Враг пакета в бою ────────────────────────────────────────────

## Короткая метка для карточки врага: «Панцирь: не пробивают Лучники, Огонь».
static func enemy_label(g: TDGame, strain: String) -> String:
	match strain:
		"flock":
			return "Стая: летит напрямик"
		"brood", "hulk":
			var mine := blocked_towers(g, strain)
			var head := "Выводок" if strain == "brood" else "Панцирь"
			if mine.is_empty():
				return head + (": тяжёлые выстрелы не ранят" if strain == "brood" else ": лёгкие удары не ранят")
			return "%s: не ранят %s" % [head, ", ".join(mine)]
	return ""


## Какие доступные башни ранят врага пакета (для карточки врага).
static func enemy_answer(g: TDGame, strain: String) -> String:
	if not TDStrains.PACK.has(strain):
		return ""
	var ok := available(g, TDStrains.PACK[strain]["answers"], 4)
	return "Ранят: %s" % names(ok) if strain != "flock" else "Бьют по воздуху: %s" % names(ok)


# ── Экран поражения ──────────────────────────────────────────────

static func new_leaks() -> Dictionary:
	return {"total": 0, "lives": 0, "boss": 0, "boss_lives": 0, "normal": 0, "child": 0, "fly": 0, "stealth": 0, "strain": {}}


## Учёт одного прорыва (TDGame.note_leak). Каждый враг попадает ровно в одну группу.
static func add_leak(d: Dictionary, boss: bool, child: bool, strain: String, fly: bool, stealth: bool, lives: int) -> void:
	d["total"] = int(d["total"]) + 1
	d["lives"] = int(d["lives"]) + lives
	if boss:
		d["boss"] = int(d["boss"]) + 1
		d["boss_lives"] = int(d["boss_lives"]) + lives
	elif strain != "":
		d["strain"][strain] = int(d["strain"].get(strain, 0)) + 1
	elif stealth:
		d["stealth"] = int(d["stealth"]) + 1
	elif fly:
		d["fly"] = int(d["fly"]) + 1
	elif child:
		d["child"] = int(d["child"]) + 1
	else:
		d["normal"] = int(d["normal"]) + 1


## «Что тебя погубило»: только по фактическим прорывам последней волны. Причина называется, только если одна группа
## отняла не меньше половины жизней; иначе — нейтральная сводка без совета.
## {known, wave, lives, rows: [{icon, color, text, lives}], cause: {title, towers, build} | {}}
static func defeat(g: TDGame) -> Dictionary:
	var d: Dictionary = g.wave_leaks
	var out := {"known": g.leak_known and not d.is_empty() and int(d.get("total", 0)) > 0, "wave": g.wave, "lives": int(d.get("lives", 0)), "rows": [], "cause": {}}
	if not out["known"]:
		return out
	var groups: Array = []
	if int(d["boss"]) > 0:
		groups.append({"id": "boss", "icon": "boss", "color": "#ff6b7a", "lives": int(d["boss_lives"]),
			"text": "Босс прорвался: −%d %s" % [int(d["boss_lives"]), plural(int(d["boss_lives"]), "жизнь", "жизни", "жизней")]})
	for p in TDStrains.PACKAGES:
		var n: int = int(d["strain"].get(p, 0))
		if n > 0:
			var pd: Dictionary = TDStrains.PACK[p]
			groups.append({"id": "strain:" + p, "strain": p, "icon": pd["icon"], "color": pd["color"], "lives": n,
				"text": "%s: прорвалось %d" % [pd["name"], n]})
	for row in [["stealth", "gene-veil", "#c9a0ff", "Невидимки: прорвалось %d"], ["fly", "gene-wings", "#9ad7ff", "Летающие: прорвалось %d"],
			["child", "gene-split", "#e08af0", "Малыши деления и призыва: прорвалось %d"], ["normal", "castle", "#b5c4be", "Обычные враги: прорвалось %d"]]:
		var n2: int = int(d[row[0]])
		if n2 > 0:
			groups.append({"id": row[0], "icon": row[1], "color": row[2], "lives": n2, "text": String(row[3]) % n2})
	groups.sort_custom(func(a, b): return int(a["lives"]) > int(b["lives"]))
	out["rows"] = groups
	var top: Dictionary = groups[0] if not groups.is_empty() else {}
	if not top.is_empty() and float(top["lives"]) >= 0.5 * float(maxi(1, int(d["lives"]))):
		var towers: Array = []
		var title := ""
		match String(top["id"]):
			"boss":
				title = "Главная потеря — босс. Против него:"
				towers = available(g, ["poison", "sniper", "cannon"])
			"stealth":
				title = "Главная потеря — невидимки. Их показывает:"
				towers = available(g, ["beacon"])
			"fly":
				title = "Главная потеря — летающие. По воздуху бьют:"
				towers = available(g, ["flak", "arrow", "sniper"])
			_:
				if top.has("strain"):
					title = "Главная потеря — %s. Против них:" % TDStrains.PACK[top["strain"]]["name"]
					towers = available(g, TDStrains.PACK[top["strain"]]["answers"])
		if title != "":
			out["cause"] = {"title": title, "towers": towers, "icon": top["icon"], "color": top["color"]}
	return out
