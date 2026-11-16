class_name TDStrains
extends RefCounted
## PRO-152, эксперимент «Сигнатура обороны + инкубация контрмер». Включается только флагом забега
## meta["swarm_model"] (см. TDGame.strains_on); без флага бой ни разу не вызывает этот модуль,
## поэтому поток rng, сохранения, состав волн и интерфейс остаются прежними.
##
## Цикл: удары по обычным врагам волны → сигнатура обороны (EMA) → инкубация контрмеры по одному
## триггеру на пакет → анонс за LEAD волн → пакет меняет состав волны (доля врагов, не средний ген) →
## если триггер ослаб, инкубация тает и доля пакета снижается шагами. Модель и обоснование:
## docs/balance/experiment-signature-incubation.md.

## Рабочая модель: контрмеры меняют состав волн.
const MODEL := "signature"
## Плацебо-плечо для A/B и калибровки: сигнатура и инкубация считаются и показываются в отчёте харнесса,
## но состав волн не меняется.
const OBSERVE := "observe"

# ── Сигнатура ─────────────────────────────────────────────────────
## Распределения урона: в каждом классы взаимоисключающие, каждое событие урона попадает ровно в один класс.
## Способ доставки определяется механикой башни, а не плотностью врагов (иначе ответ роя менял бы собственный сигнал):
## burst — одиночный удар не меньше HEAVY_HIT от полного здоровья цели; rapid — одиночный удар слабее (каждая стрела «Залпа» тоже);
## area — удар башни с радиусом взрыва; chain — любой удар цепной башни; dot — тик яда.
const DEL: Array[String] = ["burst", "rapid", "area", "chain", "dot"]
const EL: Array[String] = ["physical", "fire", "frost", "poison", "shock"]
const RANGE_CLS: Array[String] = ["near", "mid", "far"]
const TGT: Array[String] = ["ground", "air"]
const HEAVY_HIT := 0.25
const NEAR := 2.5
const FAR := 4.0
## Сглаживание сигнатуры: новая волна весит EMA, полупериод памяти ≈ 1,6 волны.
const EMA := 0.35
const AIR_SAMPLES := 40

# ── Пакеты контрмер ───────────────────────────────────────────────
const PACKAGES: Array[String] = ["brood", "hulk", "flock"]
## trigger — ключ скаляра сигнатуры; threshold — ниже него инкубация не растёт, а тает.
const PACK := {
	"brood": {"name": "Выводок", "icon": "gene-split", "color": "#d7e36a", "trigger": "burst", "threshold": 0.35, "min_wave": 6,
		"noticed": "%d%% урона — тяжёлые одиночные выстрелы",
		"effect": "часть врагов приходит кладками по %d малыша в скорлупе: тяжёлые одиночные выстрелы (снайпер, гарпун, «Стужа») их не ранят",
		"answer": "частый огонь, площадь, цепь или яд",
		"answers": ["arrow", "cannon", "tesla", "poison", "frost"]},
	"hulk": {"name": "Панцирники", "icon": "gene-plated", "color": "#e3a35a", "trigger": "rapid", "threshold": 0.60, "min_wave": 10,
		"noticed": "%d%% урона — лёгкие одиночные удары",
		"effect": "часть врагов в панцире: лёгкие одиночные удары (стрелы, «Залп», огонь) их не ранят, но яд, лёд и ожог ложатся",
		"answer": "тяжёлые выстрелы, площадь, цепь или яд",
		"answers": ["sniper", "cannon", "tesla", "poison"]},
	"flock": {"name": "Стая", "icon": "gene-wings", "color": "#ffb0dc", "trigger": "air_gap", "threshold": 0.45, "min_wave": 6,
		"noticed": "%d%% прямой полёта не простреливают башни, бьющие по воздуху",
		"effect": "часть наземных врагов летит напрямик над картой",
		"answer": "зенитка, сеть, лучники или снайпер у прямой полёта",
		"answers": ["flak", "net", "arrow", "sniper"]},
}
## Инкубация: +RATE × превышение порога × множитель сложности за волну; ниже порога ×DECAY.
## Превышение = (триггер − порог) / SPAN, не больше 1: полная скорость на SPAN выше порога.
const RATE := 0.6
const SPAN := 0.3
## Первые волны сигнатура копится, но инкубация не идёт: стартовая оборона ещё не выбор, а нехватка золота.
const WARMUP_WAVE := 4
const DECAY := 0.6
const INC_CAP := 1.5
## Порог анонса и порог удержания (гистерезис: пакет отступает, только когда инкубация < HOLD).
const ANNOUNCE := 1.0
const HOLD := 0.5
## Анонс в отчёте волны w, появление в волне w + LEAD: у игрока LEAD фаз строительства на ответ.
const LEAD := 2
## Раньше этой волны пакеты не появляются (сигнатура ещё молодая, полёт открывается с 6-й); у пакета может быть свой
## минимум min_wave: «Панцирники» — с 10-й, чтобы не наказывать раннюю оборону из дешёвых лучников, на которую просто нет денег.
const MIN_WAVE := 6
const SHARE_START := 0.15
const SHARE_STEP := 0.10
const SHARE_CAP := {"easy": 0.2, "normal": 0.3, "hard": 0.4}
## Не больше этой доли волны и не больше MAX_LIVE пакетов в анонсе/бою одновременно.
const TOTAL_CAP := 0.4
const MAX_LIVE := 2

# ── Бюджет угрозы пакетов ─────────────────────────────────────────
## Панцирь (Enemy.shell > 0) гасит урон ударов одного класса доставки (deflects) — правило, а не броня: его не снимают
## пробитие снайпера, огонь, лёд и перки. Эффекты удара (замедление, яд, ожог) ложатся. Панцирь не разбивается.
## Выводок: один геном → BROOD_N малышей по BROOD_HP здоровья (суммарно 0,9 исходного), панцирь против burst —
## одиночного удара не меньше HEAVY_HIT здоровья малыша. Лёгкие удары, площадь, цепь и яд проходят.
## Золото: носитель даёт награду за убийство минус (BROOD_N−1) × SPLIT_REWARD, малыши — SPLIT_REWARD; итог как у одного врага.
const BROOD_N := 3
const BROOD_HP := 0.30
const BROOD_SIZE := 0.6
const BROOD_SPEED := 1.1
## Панцирники: панцирь против rapid — одиночного удара слабее HEAVY_HIT здоровья; тяжёлые выстрелы, площадь, цепь и яд проходят.
## Оплачено здоровьем и скоростью.
const HULK_HP := 0.9
const HULK_SPEED := 0.9
const HULK_SIZE := 1.15
## Какой класс удара гасит панцирь пакета.
const DEFLECT := {"brood": "burst", "hulk": "rapid"}
## Стая: полёт с обычными множителями летающих (TDConfig.FLYER_HP, FLYER_SPEED).


## Только для лаборатории (tests/balance_audit.gd --lab-strain=...): начиная с волны lab_from все размеченные доли
## заменяются на lab_share выбранного пакета, чтобы измерить его силу против конкретной обороны. В игре всегда пусто.
static var lab_strain := ""
static var lab_share := 1.0
static var lab_from := 0


static func deflects(strain: String, cls: String) -> bool:
	return DEFLECT.get(strain, "") == cls


static func enabled(meta: Dictionary) -> bool:
	return String(meta.get("swarm_model", "")) in [MODEL, OBSERVE]


static func acts(meta: Dictionary) -> bool:
	return String(meta.get("swarm_model", "")) == MODEL


static func _zeros(keys: Array) -> Dictionary:
	var d := {}
	for k in keys:
		d[k] = 0.0
	return d


## Накопитель событий одной волны.
static func new_acc() -> Dictionary:
	return {"del": _zeros(DEL), "el": _zeros(EL), "rng": _zeros(RANGE_CLS), "tgt": _zeros(TGT),
		"total": 0.0, "chill": 0.0, "life_t": 0.0, "slow_t": 0.0, "kind_burst": {}, "kind_rapid": {}, "kind": {}}


static func new_state() -> Dictionary:
	var pk := {}
	for p in PACKAGES:
		pk[p] = {"inc": 0.0, "share": 0.0, "phase": "quiet", "appear": 0, "since": 0}
	return {"sig": {}, "n": 0, "pk": pk, "last": {}}


## В сигнатуру идут только удары по обычным врагам волны: не боссы (их HP — отдельная механика), не малыши деления/призыва
## и не враги пакетов (иначе ответ роя менял бы собственный сигнал).
static func eligible(e) -> bool:
	return not e.boss and not e.child and e.strain == ""


static func del_class(def: Dictionary, raw: float, max_hp: float) -> String:
	if float(def.get("splash", 0.0)) > 0.0:
		return "area"
	if int(def.get("chain", 1)) > 1:
		return "chain"
	return "burst" if raw >= HEAVY_HIT * maxf(1.0, max_hp) else "rapid"


static func range_class(d: float) -> String:
	return "near" if d < NEAR else ("far" if d > FAR else "mid")


static func _add(acc: Dictionary, cls: String, el: String, dist: float, fly: bool, chilled: bool, kind: String, dealt: float) -> void:
	if dealt <= 0.0:
		return
	acc["del"][cls] += dealt
	acc["el"][el] = float(acc["el"].get(el, 0.0)) + dealt
	acc["rng"][range_class(dist)] += dealt
	acc["tgt"]["air" if fly else "ground"] += dealt
	acc["total"] += dealt
	acc["kind"][kind] = float(acc["kind"].get(kind, 0.0)) + dealt
	if cls in ["burst", "rapid"]:
		acc["kind_" + cls][kind] = float(acc["kind_" + cls].get(kind, 0.0)) + dealt
	if chilled:
		acc["chill"] += dealt


## Удар башни (_hit). raw — номинальный урон удара до брони и сопротивлений.
static func record_hit(acc: Dictionary, def: Dictionary, kind: String, tower_pos: Vector2, target_pos: Vector2, fly: bool, max_hp: float, raw: float, dealt: float, chilled: bool) -> void:
	_add(acc, del_class(def, raw, max_hp), String(def["type"]), tower_pos.distance_to(target_pos), fly, chilled, kind, dealt)


## Тик яда: доставка dot, стихия poison, дистанция — от башни-источника.
static func record_dot(acc: Dictionary, tower_pos: Vector2, target_pos: Vector2, fly: bool, dealt: float, chilled: bool) -> void:
	_add(acc, "dot", "poison", tower_pos.distance_to(target_pos), fly, chilled, "poison", dealt)


static func record_time(acc: Dictionary, slowed: bool, dt: float) -> void:
	acc["life_t"] += dt
	if slowed:
		acc["slow_t"] += dt


## Доля прямой полёта, которую не простреливает ни одна башня, бьющая по воздуху (0 — всё покрыто, 1 — ничего).
## Считается по позициям башен, поэтому определена и без летающих, и при нулевом уроне.
static func air_gap(g) -> float:
	var shooters: Array = []
	for t in g.towers:
		if t.def.has("aura") or not t.def["air"]:
			continue
		shooters.append([Vector2(t.x + 0.5, t.y + 0.5), g.t_range(t)])
	if shooters.is_empty():
		return 1.0
	var miss := 0
	for s in AIR_SAMPLES:
		var p: Vector2 = g.map.fly_pos_at((s + 0.5) / AIR_SAMPLES * g.map.fly_length)
		var hit := false
		for sh in shooters:
			if p.distance_to(sh[0]) <= sh[1]:
				hit = true
				break
		if not hit:
			miss += 1
	return float(miss) / AIR_SAMPLES


static func normalize(d: Dictionary, keys: Array) -> Dictionary:
	var total := 0.0
	for k in keys:
		total += float(d.get(k, 0.0))
	if total <= 0.0:
		return {}
	var out := {}
	for k in keys:
		out[k] = float(d.get(k, 0.0)) / total
	return out


## Нормированный индекс Херфиндаля: 0 — урон поровну по всем классам, 1 — весь в одном. Пустое распределение — 0.
static func hhi(p: Dictionary, keys: Array) -> float:
	if p.is_empty() or keys.size() < 2:
		return 0.0
	var s := 0.0
	for k in keys:
		s += pow(float(p.get(k, 0.0)), 2)
	var n := float(keys.size())
	return clampf((s - 1.0 / n) / (1.0 - 1.0 / n), 0.0, 1.0)


## Специализация обороны: среднее H* по доставке, стихии и дистанции (каждое распределение входит один раз).
## Цель (земля/воздух) не входит: она зависит от состава роя, а не от выбора игрока.
static func concentration(sig: Dictionary) -> float:
	if sig.is_empty():
		return 0.0
	return (hhi(sig.get("del", {}), DEL) + hhi(sig.get("el", {}), EL) + hhi(sig.get("rng", {}), RANGE_CLS)) / 3.0


## Срез одной волны из накопителя ({} — урона по обычным врагам не было).
static func sample(acc: Dictionary) -> Dictionary:
	if float(acc.get("total", 0.0)) <= 0.0:
		return {}
	var d := normalize(acc["del"], DEL)
	return {"del": d, "el": normalize(acc["el"], EL), "rng": normalize(acc["rng"], RANGE_CLS), "tgt": normalize(acc["tgt"], TGT),
		"burst": float(d["burst"]), "rapid": float(d["rapid"]), "chill": float(acc["chill"]) / float(acc["total"]),
		"control": float(acc["slow_t"]) / float(acc["life_t"]) if float(acc["life_t"]) > 0.0 else 0.0}


static func _blend(old: Dictionary, new: Dictionary, keys: Array) -> Dictionary:
	if old.is_empty():
		return new.duplicate()
	var out := {}
	for k in keys:
		out[k] = (1.0 - EMA) * float(old.get(k, 0.0)) + EMA * float(new.get(k, 0.0))
	return out


## EMA сигнатуры. Без урона по обычным врагам распределения не меняются (нет данных — нет вывода);
## покрытие воздуха считается по башням и обновляется всегда.
static func blend(sig: Dictionary, s: Dictionary, gap: float) -> Dictionary:
	var out := sig.duplicate(true)
	if not s.is_empty():
		var first := sig.is_empty() or not sig.has("del")
		out["del"] = _blend({} if first else sig["del"], s["del"], DEL)
		out["el"] = _blend({} if first else sig["el"], s["el"], EL)
		out["rng"] = _blend({} if first else sig["rng"], s["rng"], RANGE_CLS)
		out["tgt"] = _blend({} if first else sig["tgt"], s["tgt"], TGT)
		for k in ["chill", "control"]:
			out[k] = s[k] if first else (1.0 - EMA) * float(sig[k]) + EMA * float(s[k])
		out["burst"] = float(out["del"]["burst"])
		out["rapid"] = float(out["del"]["rapid"])
	out["air_gap"] = gap if not sig.has("air_gap") else (1.0 - EMA) * float(sig["air_gap"]) + EMA * gap
	return out


static func trigger_value(sig: Dictionary, p: String) -> float:
	return float(sig.get(PACK[p]["trigger"], 0.0))


## Превышение порога, нормированное к 0..1.
static func excess(sig: Dictionary, p: String) -> float:
	if not sig.has("del") and p != "flock":
		return 0.0
	var thr: float = PACK[p]["threshold"]
	return clampf((trigger_value(sig, p) - thr) / SPAN, 0.0, 1.0)


static func share_cap(meta: Dictionary) -> float:
	return float(SHARE_CAP.get(String(meta.get("difficulty", "normal")), SHARE_CAP["normal"]))


## Конец волны w: обновить сигнатуру, инкубацию и фазы пакетов, разметить врагов следующей волны (только в MODEL).
## Возвращает запись для отчёта волны. Не трогает rng.
static func end_wave(g, w: int) -> Dictionary:
	var st: Dictionary = g.strains if not g.strains.is_empty() else new_state()
	var acc: Dictionary = g.strain_acc if not g.strain_acc.is_empty() else new_acc()
	var s := sample(acc)
	var gap := air_gap(g)
	st["sig"] = blend(st["sig"], s, gap)
	if not s.is_empty():
		st["n"] = int(st["n"]) + 1
	var sig: Dictionary = st["sig"]
	var mult: float = float(TDConfig.difficulty(g.meta)["adapt"])
	var next_wave := w + 1
	var cap := share_cap(g.meta)
	var live := 0
	for p in PACKAGES:
		if String(st["pk"][p]["phase"]) in ["announced", "active", "fading"]:
			live += 1
	for p in PACKAGES:
		var k: Dictionary = st["pk"][p]
		var ex := excess(sig, p) if w >= WARMUP_WAVE else 0.0
		if ex > 0.0:
			k["inc"] = minf(INC_CAP, float(k["inc"]) + RATE * ex * mult)
		else:
			k["inc"] = float(k["inc"]) * DECAY
		match String(k["phase"]):
			"announced":
				if int(k["appear"]) <= next_wave:
					k["phase"] = "active"
					k["share"] = SHARE_START
					k["since"] = next_wave
			"active", "fading":
				if float(k["inc"]) >= HOLD:
					k["phase"] = "active"
					k["share"] = minf(cap, float(k["share"]) + SHARE_STEP)
				else:
					k["phase"] = "fading"
					k["share"] = maxf(0.0, float(k["share"]) - SHARE_STEP)
					if float(k["share"]) <= 0.001:
						k["share"] = 0.0
						k["phase"] = "quiet"
						live -= 1
			_:
				if float(k["inc"]) >= ANNOUNCE and live < MAX_LIVE and next_wave + LEAD - 1 >= maxi(MIN_WAVE, int(PACK[p]["min_wave"])):
					k["phase"] = "announced"
					k["appear"] = next_wave + LEAD - 1
					live += 1
				else:
					k["phase"] = "incubating" if float(k["inc"]) >= 0.1 else "quiet"
	# суммарная доля пакетов не выше TOTAL_CAP
	var total := 0.0
	for p in PACKAGES:
		total += float(st["pk"][p]["share"])
	if total > TOTAL_CAP:
		for p in PACKAGES:
			st["pk"][p]["share"] = float(st["pk"][p]["share"]) * TOTAL_CAP / total
	st["last"] = {"wave": w, "kind_burst": acc["kind_burst"].duplicate(), "kind_rapid": acc["kind_rapid"].duplicate(),
		"kind": acc["kind"].duplicate(), "had_damage": not s.is_empty()}
	g.strains = st
	g.strain_acc = new_acc()
	if acts(g.meta):
		if lab_strain != "" and next_wave >= lab_from:
			var forced := {"pk": {}}
			for p in PACKAGES:
				forced["pk"][p] = {"phase": "active" if p == lab_strain else "quiet", "share": lab_share if p == lab_strain else 0.0}
			g.upcoming = assign(g.upcoming, forced, next_wave)
		else:
			g.upcoming = assign(g.upcoming, st, next_wave)
	return report(st)


## Компактная запись для отчёта волны и логов харнесса.
static func report(st: Dictionary) -> Dictionary:
	var pk := {}
	for p in PACKAGES:
		var k: Dictionary = st["pk"][p]
		pk[p] = {"inc": float(k["inc"]), "share": float(k["share"]), "phase": String(k["phase"]), "appear": int(k["appear"])}
	var sig: Dictionary = st["sig"]
	return {"sig": sig.duplicate(true), "C": concentration(sig), "pk": pk}


## Разметить врагов следующей волны: доля каждого активного пакета, равномерно по волне. rng не используется.
static func assign(list: Array, st: Dictionary, wave: int) -> Array:
	var out: Array = []
	for ge in list:
		var c: Dictionary = ge.duplicate()
		c.erase("strain")
		out.append(c)
	var n := out.size()
	if n == 0:
		return out
	for p in PACKAGES:
		var k: Dictionary = st["pk"][p]
		if String(k["phase"]) not in ["active", "fading"] or float(k["share"]) <= 0.0:
			continue
		var free: Array = []
		for i in n:
			if out[i].has("strain"):
				continue
			if p == "flock" and TDGenome.phenotype(out[i], wave)["fly"]:
				continue
			free.append(i)
		var m: int = mini(free.size(), int(round(float(k["share"]) * n)))
		for j in m:
			var idx: int = free[int(floor((j + 0.5) * free.size() / m))]
			out[idx]["strain"] = p
	return out


## Фенотип с учётом пакета (только для обычных врагов волны в MODEL).
static func apply_ph(ph: Dictionary, strain: String) -> Dictionary:
	if strain == "":
		return ph
	var out := ph.duplicate()
	match strain:
		"brood":
			out["hp"] = ph["hp"] * BROOD_HP
			out["size"] = ph["size"] * BROOD_SIZE
			out["speed"] = ph["speed"] * BROOD_SPEED
		"hulk":
			out["hp"] = ph["hp"] * HULK_HP
			out["speed"] = ph["speed"] * HULK_SPEED
			out["size"] = ph["size"] * HULK_SIZE
		"flock":
			if not ph["fly"]:
				out["fly"] = true
				out["hp"] = ph["hp"] * TDConfig.FLYER_HP
				out["speed"] = ph["speed"] * TDConfig.FLYER_SPEED
	return out


# ── Текст для игрока: «рой заметил X → готовит Y → ответ Z» ──────

## Башни-ответы, которые игроку сейчас доступны.
static func answers(g, p: String) -> Array:
	var out: Array = []
	for k in PACK[p]["answers"]:
		if not g.is_locked(k):
			out.append(k)
	return out


## Кто дал сигнал: башни с наибольшим вкладом в триггер прошлой волны.
static func culprits(st: Dictionary, p: String, limit: int = 2) -> Array:
	if p == "flock":
		return []
	var src: Dictionary = st.get("last", {}).get("kind_" + String(PACK[p]["trigger"]), {})
	var arr: Array = []
	for k in src:
		arr.append([k, float(src[k])])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array = []
	for x in arr.slice(0, limit):
		out.append(x[0])
	return out


## Записи для панели «Рой», отчёта волны и плашек. Только пакеты, о которых есть что сказать.
static func forecast(g) -> Array:
	if not enabled(g.meta) or g.strains.is_empty():
		return []
	var st: Dictionary = g.strains
	var sig: Dictionary = st["sig"]
	var out: Array = []
	for p in PACKAGES:
		var k: Dictionary = st["pk"][p]
		var phase := String(k["phase"])
		if phase == "quiet":
			continue
		var d: Dictionary = PACK[p]
		var trig := trigger_value(sig, p)
		var who: Array = []
		for c in culprits(st, p):
			who.append(TDConfig.TOWERS[c]["name"])
		var noticed: String = String(d["noticed"]) % roundi(trig * 100.0)
		if not who.is_empty():
			noticed += " (%s)" % ", ".join(who)
		var effect: String = String(d["effect"]) % BROOD_N if p == "brood" else String(d["effect"])
		var count := 0
		for ge in g.upcoming:
			if String(ge.get("strain", "")) == p:
				count += 1
		out.append({"id": p, "name": d["name"], "icon": d["icon"], "color": d["color"], "phase": phase,
			"inc": float(k["inc"]), "share": float(k["share"]), "appear": int(k["appear"]), "next_count": count,
			"trigger": trig, "threshold": float(d["threshold"]), "noticed": noticed, "effect": effect,
			"answer": d["answer"], "towers": answers(g, p)})
	return out


## Одна строка «заметил → готовит → ответ» с честным статусом.
static func line(e: Dictionary) -> String:
	var status := ""
	match String(e["phase"]):
		"incubating":
			status = "изучает (%d%%)" % roundi(minf(1.0, e["inc"]) * 100.0)
		"announced":
			status = "готовит «%s»: появится в волне %d" % [e["name"], e["appear"]]
		"active":
			status = "«%s» в волне: %d%% врагов" % [e["name"], roundi(e["share"] * 100.0)]
		"fading":
			status = "«%s» отступает: %d%% врагов" % [e["name"], roundi(e["share"] * 100.0)]
	return "Рой заметил: %s → %s → ответ: %s" % [e["noticed"], status, e["answer"]]
