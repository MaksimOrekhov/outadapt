class_name TDGenome
extends RefCounted
## Гены роя, фенотип, эволюция. Геном — Dictionary {ген: float}.

const GENES: Array[String] = ["tough", "swift", "plated", "ember", "frost", "wings", "veil", "regen", "split", "ward"]
## Редкие признаки: стартуют почти с нуля, включаются выше TRAIT_THRESHOLD, их доля ограничена.
const SPECIAL: Array[String] = ["wings", "veil", "regen", "split", "ward"]
const CAPPED: Array[String] = ["wings", "veil", "split", "ward"]

const GENE_LABELS := {
	"tough": "Здоровье", "swift": "Скорость", "plated": "Броня", "ember": "Огнестойкость",
	"frost": "Морозостойкость", "wings": "Полёт", "veil": "Невидимость", "regen": "Лечение",
	"split": "Деление", "ward": "Щит",
}

const GENE_HELP := {
	"tough": "Больше здоровья",
	"swift": "Быстрее бегут",
	"plated": "Броня гасит физический урон, особенно слабые удары лучников. Огонь и яд её игнорируют",
	"ember": "Огонь бьёт слабее",
	"frost": "Лёд бьёт и замедляет слабее",
	"wings": "Выше 50% — враг летит напрямик, минуя дорогу",
	"veil": "Выше 50% — враг невидим, пока рядом нет Маяка",
	"regen": "Враг лечится на ходу; яд это останавливает",
	"split": "Выше 50% — убитый враг распадается на двух малышей. Против них хорош урон по площади",
	"ward": "Выше 50% — враг прикрывает соседей: они получают на 30% меньше урона. Выбивай носителя первым",
}

const TRAIT_THRESHOLD := 0.5
## С какой волны рой может обзавестись признаком.
const UNLOCK_WAVE := {"regen": 4, "wings": 6, "veil": 9, "split": 12, "ward": 15}
const MAX_TRAIT_SHARE := 0.4
const SCOUT_SHARE := 0.15
## Доля лучших, из которых рождается следующая волна.
const ELITE_SHARE := 0.3
## Направленная адаптация: на сколько ген защиты растёт за 100% урона своего типа.
const ADAPT := 0.1
## Какой ген защищает от какого типа урона.
const TYPE_GENE := {"physical": "plated", "fire": "ember", "frost": "frost", "poison": "tough", "shock": "tough"}

## Только для диагностики баланса (tests/balance_audit.gd --swarm=...): отключает части эволюции,
## чтобы измерить их вклад. "" — обычная игра; "no_press" — без направленной адаптации по типу урона;
## "no_select" — родители выбираются без учёта fitness; "drift" — и то и другое.
## В игре всегда "", поток rng и поведение по умолчанию не меняются.
static var diag_evolution := ""


## Давление на рой: доля урона каждого типа -> ген, который от него защищает.
## Возвращает {ген: доля 0..1}.
static func pressure(damage_by: Dictionary) -> Dictionary:
	var total := 0.0
	for k in damage_by:
		total += damage_by[k]
	var out := {}
	if total <= 0.0:
		return out
	for k in damage_by:
		if not TDConfig.TOWERS.has(k):
			continue
		var gene: String = TYPE_GENE.get(TDConfig.TOWERS[k]["type"], "")
		if gene != "":
			out[gene] = float(out.get(gene, 0.0)) + damage_by[k] / total
	return out


static func budget(wave: int) -> float:
	return minf(3.4, 1.5 + 0.13 * wave)


static func _clamp01(v: float) -> float:
	return maxf(0.0, minf(1.0, v))


static func fit_to_budget(g: Dictionary, wave: int) -> Dictionary:
	var out := {}
	var s := 0.0
	for k in GENES:
		out[k] = 0.0 if wave < int(UNLOCK_WAVE.get(k, 0)) else _clamp01(float(g.get(k, 0.0)))
		s += out[k]
	var b := budget(wave)
	if s > b:
		for k in GENES:
			out[k] *= b / s
	return out


static func phenotype(g: Dictionary, wave: int) -> Dictionary:
	var fly: bool = g["wings"] > TRAIT_THRESHOLD
	var late: float = maxf(0.0, wave - 15.0)
	return {
		"hp": 22.0 * (1.0 + 2.6 * g["tough"]) * (1.0 + 0.32 * (wave - 1) + 0.02 * late * late) * (TDConfig.FLYER_HP if fly else 1.0),
		"speed": (0.9 + 1.1 * g["swift"]) * (TDConfig.FLYER_SPEED if fly else 1.0),
		"armor": 5.5 * g["plated"],
		"fireRes": 0.75 * g["ember"],
		"frostRes": 0.75 * g["frost"],
		"regen": 0.08 * g["regen"],
		"fly": fly,
		"stealth": g["veil"] > TRAIT_THRESHOLD,
		"split": g.get("split", 0.0) > TRAIT_THRESHOLD,
		"ward": g.get("ward", 0.0) > TRAIT_THRESHOLD,
		"size": 0.2 + 0.18 * g["tough"],
	}


static func random_genome(rng: TDRng, wave: int) -> Dictionary:
	var g := {}
	for k in GENES:
		var special: bool = k in SPECIAL
		g[k] = rng.next() * 0.06 if special else 0.08 + rng.next() * 0.22
	return fit_to_budget(g, wave)


## parents: Array из {genome, fitness}. Отбор + скрещивание + мутация.
## press: {ген: доля урона}, см. pressure(): рой целенаправленно наращивает защиту от того, чем его били.
## caps: {ген: потолок} — вакцина; применяется последним и не расходует rng, поэтому поток случайных чисел
## эволюции одинаков с вакциной и без неё.
static func evolve(parents: Array, size: int, wave: int, rng: TDRng, press: Dictionary = {}, caps: Dictionary = {}) -> Array:
	# стабильная сортировка по убыванию fitness (как Array.sort в JS)
	var indexed: Array = []
	for i in parents.size():
		indexed.append([parents[i], i])
	indexed.sort_custom(func(a, b):
		if a[0]["fitness"] != b[0]["fitness"]:
			return a[0]["fitness"] > b[0]["fitness"]
		return a[1] < b[1])
	if diag_evolution in ["no_press", "drift"]:
		press = {}
	var pool: Array = []
	var pool_n: int = maxi(2, int(ceil(indexed.size() * ELITE_SHARE)))
	if diag_evolution in ["no_select", "drift"]:
		pool_n = indexed.size()
	for i in mini(pool_n, indexed.size()):
		pool.append(indexed[i][0])
	var out: Array = []
	for _i in size:
		var a: Dictionary = pool[int(floor(rng.next() * pool.size()))]["genome"]
		var b: Dictionary = pool[int(floor(rng.next() * pool.size()))]["genome"]
		var child := {}
		for k in GENES:
			var v: float = a[k] if rng.next() < 0.5 else b[k]
			v += rng.gauss() * 0.1
			if rng.next() < 0.12:
				v += rng.gauss() * 0.3
			v += ADAPT * float(press.get(k, 0.0))
			child[k] = v
		out.append(fit_to_budget(child, wave))
	# потолок на полёт и невидимость
	for k in CAPPED:
		var idx: Array = []
		for i in out.size():
			if out[i][k] > TRAIT_THRESHOLD:
				idx.append(i)
		var limit: int = int(floor(out.size() * MAX_TRAIT_SHARE))
		var n: int = idx.size()
		while n > limit:
			var pick_at: int = int(floor(rng.next() * idx.size()))
			var i: int = idx[pick_at]
			idx.remove_at(pick_at)
			var copy: Dictionary = out[i].duplicate()
			copy[k] = 0.3
			out[i] = copy
			n -= 1
	# новая угроза появляется заметной группой в строго известную волну
	for k in GENES:
		if int(UNLOCK_WAVE.get(k, -1)) != wave:
			continue
		var scouts: int = maxi(2, int(round(size * SCOUT_SHARE)))
		for _i in scouts:
			var idx2: int = int(floor(rng.next() * out.size()))
			var copy2: Dictionary = out[idx2].duplicate()
			copy2[k] = 0.6
			out[idx2] = fit_to_budget(copy2, wave)
	return apply_caps(out, caps)


## Не даёт генам из caps превысить потолок. Возвращает новый массив; rng не трогает.
static func apply_caps(list: Array, caps: Dictionary) -> Array:
	if caps.is_empty():
		return list
	var out: Array = []
	for g in list:
		var copy: Dictionary = g.duplicate()
		for k in caps:
			copy[k] = minf(float(copy.get(k, 0.0)), float(caps[k]))
		out.append(copy)
	return out


static func average_genome(list: Array) -> Dictionary:
	var avg := {}
	for k in GENES:
		var s := 0.0
		for g in list:
			s += float(g.get(k, 0.0))
		avg[k] = s / list.size() if list.size() > 0 else 0.0
	return avg
