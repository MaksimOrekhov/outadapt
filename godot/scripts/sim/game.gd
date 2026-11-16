class_name TDGame
extends RefCounted
## Ядро игры: башни, враги, волны, перки.
## Весь расчёт без обращений к узлам Godot, поэтому его можно гонять в headless.

class Enemy:
	extends RefCounted
	var id: int
	var genome: Dictionary
	var ph: Dictionary
	var hp: float
	var dist: float = 0.0
	var slow_t: float = 0.0
	var slow_factor: float = 0.0
	var scorch_t: float = 0.0
	## Доп. срез брони от «Плавильни».
	var scorch_extra: float = 0.0
	var poison_t: float = 0.0
	var poison_dps: float = 0.0
	var poison_by: Tower = null
	var boss: bool = false
	## Малыш, родившийся при делении: не делится и не участвует в эволюции.
	var child: bool = false
	## Рядом носитель щита: урон по врагу снижен.
	var warded: bool = false
	## Косметика: вспышка при попадании и последний бивший тип башни.
	var hit_flash: float = 0.0
	var last_kind: String = ""
	## Способность босса (см. TDConfig.BOSS_ABILITIES) и её состояние.
	var ability: String = ""
	var shield: float = 0.0
	var shield_max: float = 0.0
	var summon_t: float = 0.0
	var immune_type: String = ""
	var summon_left: int = 0
	## Враг волны с приманкой: какой ген усилен ("" — обычный). Геном для отбора не меняется.
	var lured_gene: String = ""
	## PRO-152 (только с флагом эксперимента): пакет контрмер роя ("" — обычный враг) и панцирь пакета
	## (1 — урон ударов класса TDStrains.DEFLECT[strain] гасится целиком).
	var strain: String = ""
	var shell: int = 0


class Tower:
	extends RefCounted
	var id: int
	var kind: String
	var x: int
	var y: int
	var cd: float = 0.0
	## 1..TDConfig.MAX_LEVEL; на 3-м уровне выбрана ветка "a" или "b".
	var level: int = 1
	var branch: String = ""
	## Итоговые параметры с учётом уровня и ветки (без перков).
	var def: Dictionary = {}
	## Сколько золота вложено: от этого считается цена продажи.
	var spent: int = 0
	## "first" | "strong" | "fresh"
	var mode: String = "first"
	## Убийства за всё время.
	var kills: int = 0
	## Урон за текущую волну.
	var dealt: float = 0.0
	## Удары за волну и сколько из них усилены связками.
	var hits: int = 0
	var boosted: int = 0
	## Косметика: отдача, возраст (анимация постройки), направление прицела.
	var recoil: float = 0.0
	var age: float = 0.0
	var aim: Vector2 = Vector2.RIGHT
	## Косметика: сколько секунд прошло с последнего улучшения (анимация перестройки).
	var upgraded_t: float = 99.0


var seed_value: int
var map: TDMap
var rng: TDRng
## Отдельный генератор для перков: выбор игрока не сдвигает эволюцию роя.
var perk_rng: TDRng
var gold: int = TDConfig.START_GOLD
var lives: int = TDConfig.START_LIVES
var wave: int = 1
## "build" | "wave" | "over"
var phase: String = "build"
var towers: Array[Tower] = []
var enemies: Array[Enemy] = []
## Эффекты: {x1,y1,x2,y2,color,t,life,ring,text}
var fx: Array[Dictionary] = []
var upcoming: Array = []
var pending: Array = []
var wave_genomes: Array = []
## Босс следующей волны ({} — нет).
var upcoming_boss: Dictionary = {}
var pending_boss: Dictionary = {}
var boss_killed: bool = false
var spawn_t: float = 0.0
var finished: Array = []
var killed: int = 0
var leaked: int = 0
var damage_by: Dictionary = {}
var reports: Array[Dictionary] = []
var perks: Dictionary = {}
## Предложенные перки; пока не выбран один, следующую волну начать нельзя.
var offer: Array = []
var next_id: int = 1
## Бонусы мета-прогрессии (TDMeta.bonuses()); пустой словарь — без бонусов.
var meta: Dictionary = {}
## Статистика всего забега.
var run_kills: int = 0
var run_leaked: int = 0
var bosses_killed: int = 0
var run_damage: Dictionary = {}
## Пройдена ли волна TDConfig.VICTORY_WAVE (дальше — бесконечный режим).
var victory: bool = false
## Особая волна: следующая и идущая сейчас (""/swarm/rush/heavy).
var upcoming_special: String = ""
var cur_special: String = ""
## Вакцина: {} или {gene, left, cap}; пауза до следующей покупки и число покупок за забег.
var vaccine: Dictionary = {}
var vaccine_cd: int = 0
var vaccine_uses: int = 0
## Приманка: {} или {gene, boost, wave}; пауза до следующей и число покупок за забег.
var lure: Dictionary = {}
var lure_cd: int = 0
var lure_uses: int = 0
## Визуальные события для эффектов (включает поле; на баланс не влияют).
var emit_events: bool = false
var events: Array[Dictionary] = []
## PRO-152, эксперимент «сигнатура + инкубация» (TDStrains): состояние роя и накопитель ударов текущей волны.
## Пустые и не используются, если флаг забега meta["swarm_model"] не задан.
var strains: Dictionary = {}
var strain_acc: Dictionary = {}


func _init(seed_v: int, map_: TDMap = null, meta_: Dictionary = {}) -> void:
	seed_value = seed_v
	map = map_ if map_ != null else TDMap.generate(seed_v)
	rng = TDRng.new(seed_v)
	perk_rng = TDRng.new(seed_v ^ 0x9e3779b9)
	damage_by = _zero_damage()
	run_damage = _zero_damage()
	meta = meta_
	var diff := TDConfig.difficulty(meta)
	gold += int(meta.get("gold", 0)) + int(diff["gold"])
	lives += int(meta.get("lives", 0)) + int(diff["lives"])
	for _i in TDConfig.wave_size(1):
		upcoming.append(TDGenome.random_genome(rng, 1))
	if meta.get("start_perk", false):
		offer = _draw_offer()


## Включён ли эксперимент PRO-152 в этом забеге (флаг хранится в meta и сохраняется вместе с ним).
func strains_on() -> bool:
	return TDStrains.enabled(meta)


func _ev(d: Dictionary) -> void:
	if emit_events and events.size() < 400:
		events.append(d)


static func _zero_damage() -> Dictionary:
	var d := {}
	for k in TDConfig.TOWER_KINDS:
		d[k] = 0.0
	return d


# ── Позиции и видимость ───────────────────────────────────────

func pos_of(e: Enemy) -> Vector2:
	return map.fly_pos_at(e.dist) if e.ph["fly"] else map.pos_at(e.dist)


func path_len_of(e: Enemy) -> float:
	return map.fly_length if e.ph["fly"] else map.length


func progress_of(e: Enemy) -> float:
	return e.dist / path_len_of(e)


## Невидимый враг виден рядом с Маяком.
func is_revealed(e: Enemy) -> bool:
	if not e.ph["stealth"]:
		return true
	var p := pos_of(e)
	for t in towers:
		var aura = t.def.get("aura")
		if aura != null and p.distance_to(Vector2(t.x + 0.5, t.y + 0.5)) <= aura["radius"]:
			return true
	return false


## Видит ли конкретная башня этого врага: невидимку — только вплотную или через Маяк.
func _visible_to(e: Enemy, c: Vector2) -> bool:
	if not e.ph["stealth"]:
		return true
	return pos_of(e).distance_to(c) <= TDConfig.SELF_DETECT or is_revealed(e)


static func can_hit(def: Dictionary, e: Enemy) -> bool:
	return def["air"] if e.ph["fly"] else def["ground"]


# ── Перки ─────────────────────────────────────────────────────

func perk_level(id: String) -> int:
	return int(perks.get(id, 0))


func mods() -> Dictionary:
	return {
		"pierce": float(perk_level("pierce")),
		"shatter": TDConfig.SHATTER_BONUS + 0.2 * perk_level("shatter"),
		"scorch": minf(0.9, TDConfig.SCORCH_ARMOR_CUT + 0.2 * perk_level("scorch")),
	}


static func base_mods() -> Dictionary:
	return {"pierce": 0.0, "shatter": TDConfig.SHATTER_BONUS, "scorch": TDConfig.SCORCH_ARMOR_CUT}


func kinds_owned() -> int:
	var s := {}
	for t in towers:
		s[t.kind] = true
	return s.size()


func _variety_mult() -> float:
	return 1.0 + 0.04 * perk_level("variety") * kinds_owned()


## Урон / дальность / перезарядка типа башни 1-го уровня (для магазина и советов).
func damage_of(kind: String) -> float:
	return TDConfig.TOWERS[kind]["damage"] * _variety_mult()


func range_of(kind: String) -> float:
	return _range_with_perks(TDConfig.TOWERS[kind]["range"])


func _range_with_perks(r: float) -> float:
	return r + 0.4 * perk_level("range") if r > 0.0 else 0.0


func cooldown_of(kind: String) -> float:
	return TDConfig.TOWERS[kind]["cooldown"] * pow(0.9, perk_level("rapid"))


## То же для конкретной башни: с уровнем, веткой и соседними Маяками.
func t_damage(t: Tower) -> float:
	return t.def["damage"] * _variety_mult()


func t_range(t: Tower) -> float:
	return _range_with_perks(t.def["range"])


func t_cooldown(t: Tower) -> float:
	return t.def["cooldown"] * pow(0.9, perk_level("rapid")) / beacon_buff(t.x, t.y)


## Ускорение от Маяков на клетке: суммируются BEACON_STACK самых сильных.
func beacon_buff(x: float, y: float) -> float:
	var rates: Array[float] = []
	for b in towers:
		var aura = b.def.get("aura")
		if aura != null and Vector2(b.x, b.y).distance_to(Vector2(x, y)) <= aura["radius"]:
			rates.append(aura["fireRate"])
	rates.sort()
	rates.reverse()
	var s := 0.0
	for i in mini(rates.size(), TDConfig.BEACON_STACK):
		s += rates[i]
	return 1.0 + s


func beacons_near(x: float, y: float) -> int:
	var n := 0
	for b in towers:
		var aura = b.def.get("aura")
		if aura != null and Vector2(b.x, b.y).distance_to(Vector2(x, y)) <= aura["radius"]:
			n += 1
	return mini(n, TDConfig.BEACON_STACK)


func choose_perk(id: String) -> bool:
	if offer.is_empty() or not offer.has(id):
		return false
	perks[id] = perk_level(id) + 1
	if id == "lives":
		lives += 3
	offer = []
	return true


func _draw_offer() -> Array:
	var pool: Array = []
	for p in TDConfig.PERKS:
		if perk_level(p["id"]) < int(p["max"]):
			pool.append(p["id"])
	if pool.is_empty():
		return []
	for i in range(pool.size() - 1, 0, -1):
		var j: int = int(floor(perk_rng.next() * (i + 1)))
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, TDConfig.PERK_CHOICES + int(meta.get("perk_choices", 0)))


# ── Вакцина ───────────────────────────────────────────────────

## Причина, по которой вакцину против гена купить нельзя; "" — можно.
func vaccine_problem(gene: String) -> String:
	if not TDGenome.GENES.has(gene):
		return "Неизвестный ген"
	if phase != "build":
		return "Только между волнами"
	if not vaccine.is_empty():
		return "Уже действует вакцина"
	if lure.get("gene", "") == gene:
		return "На этот ген действует приманка"
	if vaccine_cd > 0:
		return "Перезарядка: %d" % vaccine_cd
	if TDGenome.UNLOCK_WAVE.has(gene) and wave < int(TDGenome.UNLOCK_WAVE[gene]) + TDConfig.VACCINE_TRAIT_DELAY:
		return "Признак ещё не изучен: доступно с волны %d" % (int(TDGenome.UNLOCK_WAVE[gene]) + TDConfig.VACCINE_TRAIT_DELAY)
	if gold < TDConfig.vaccine_cost(wave):
		return "Не хватает золота"
	return ""


## Потолок для гена: среднее по последней сыгранной волне (до первой волны — по ближайшей).
func vaccine_cap(gene: String) -> float:
	var src: Dictionary = reports[reports.size() - 1]["avg"] if not reports.is_empty() else TDGenome.average_genome(upcoming)
	return minf(float(src.get(gene, 0.0)), float(TDGenome.average_genome(upcoming).get(gene, 0.0)))


func buy_vaccine(gene: String) -> bool:
	if vaccine_problem(gene) != "":
		return false
	gold -= TDConfig.vaccine_cost(wave)
	vaccine = {"gene": gene, "left": TDConfig.VACCINE_WAVES, "cap": vaccine_cap(gene)}
	vaccine_uses += 1
	upcoming = TDGenome.apply_caps(upcoming, {gene: vaccine["cap"]})
	return true


# ── Приманка ──────────────────────────────────────────────────

## Доля обороны, которую затрагивает ген (0..1). Здоровье и скорость врагов влияют на любой урон; броня, огне- и морозостойкость
## ослабляют только свои типы урона (`TDGenome.TYPE_GENE`). Оценка по номинальному урону в секунду стоящих башен.
func lure_exposure_estimate(gene: String) -> float:
	var total := 0.0
	var hit := 0.0
	for t in towers:
		if t.def.has("aura"):
			continue
		var dps: float = t_damage(t) / maxf(0.05, t_cooldown(t))
		total += dps
		if TDGenome.TYPE_GENE.get(t.def["type"], "") == gene:
			hit += dps
	if total <= 0.0:
		return 0.0
	return 1.0 if gene in ["tough", "swift"] else hit / total


## То же по фактически нанесённому за волну урону (damage_by по типам башен).
static func lure_exposure_actual(gene: String, dmg_by: Dictionary, any_damage: bool) -> float:
	if gene in ["tough", "swift"]:
		return 1.0 if any_damage else 0.0
	return float(TDGenome.pressure(dmg_by).get(gene, 0.0))


## Насколько прибавка реально усилит ген: 1.0 — полностью, 0.0 — ген уже на потолке.
static func lure_saturation(gene: String, boost: float, list: Array) -> float:
	if list.is_empty() or boost <= 0.0:
		return 0.0
	var applied := 0.0
	for g in list:
		var v: float = float(g.get(gene, 0.0))
		applied += minf(1.0, v + boost) - v
	return clampf(applied / (boost * list.size()), 0.0, 1.0)


## Доход волны для награды: убитые × награда за убийство + бонус за волну.
func _lure_income(kills: int, w: int) -> int:
	var bounty: int = TDConfig.KILL_REWARD + perk_level("bounty")
	return kills * bounty + TDConfig.wave_bonus(w)


## Оценка награды за приманку на ген (по числу врагов ближайшей волны, текущей обороне и усилению генов).
func lure_estimate(gene: String = "") -> int:
	if gene == "":
		gene = String(lure.get("gene", ""))
	if gene == "":
		return 0
	var boost := TDConfig.lure_boost(gene)
	var exposure := lure_exposure_estimate(gene)
	if exposure < TDConfig.LURE_MIN_EXPOSURE:
		return 0
	return int(round(TDConfig.LURE_SHARE * _lure_income(upcoming.size(), wave) * exposure * lure_saturation(gene, boost, upcoming)))


## Что изменится для игрока: во сколько раз усилятся враги и какая доля обороны под ударом.
## effect — человекочитаемо; risk — доля обороны (0..1); reward — ожидаемая награда.
func lure_preview(gene: String) -> Dictionary:
	var boost := TDConfig.lure_boost(gene)
	var base := {"hp": 0.0, "speed": 0.0, "armor": 0.0, "fireRes": 0.0, "frostRes": 0.0}
	var lured := base.duplicate()
	for ge in upcoming:
		var p0 := TDGenome.phenotype(ge, wave)
		var lg: Dictionary = ge.duplicate()
		lg[gene] = minf(1.0, float(lg.get(gene, 0.0)) + boost)
		var p1 := TDGenome.phenotype(lg, wave)
		for k in base:
			base[k] += p0[k]
			lured[k] += p1[k]
	var n: float = maxf(1.0, float(upcoming.size()))
	for k in base:
		base[k] /= n
		lured[k] /= n
	var effect := ""
	match gene:
		"tough":
			effect = "здоровье врагов +%d%%" % roundi((lured["hp"] / maxf(1e-6, base["hp"]) - 1.0) * 100.0)
		"swift":
			effect = "скорость врагов +%d%%" % roundi((lured["speed"] / maxf(1e-6, base["speed"]) - 1.0) * 100.0)
		"plated":
			effect = "броня врагов %.1f → %.1f" % [base["armor"], lured["armor"]]
		"ember":
			effect = "огнестойкость врагов %d%% → %d%%" % [roundi(base["fireRes"] * 100.0), roundi(lured["fireRes"] * 100.0)]
		"frost":
			effect = "морозостойкость врагов %d%% → %d%%" % [roundi(base["frostRes"] * 100.0), roundi(lured["frostRes"] * 100.0)]
	return {"gene": gene, "boost": boost, "effect": effect, "risk": lure_exposure_estimate(gene),
		"saturation": lure_saturation(gene, boost, upcoming), "reward": lure_estimate(gene)}


## Причина, по которой приманку на ген нельзя взять; "" — можно.
func lure_problem(gene: String) -> String:
	if not TDConfig.LURE_GENES.has(gene):
		return "Приманка только на базовые гены"
	if phase != "build":
		return "Только между волнами"
	if not lure.is_empty():
		return "Приманка уже выбрана"
	if lure_cd > 0:
		return "Перезарядка: %d" % lure_cd
	if wave < TDConfig.LURE_MIN_WAVE:
		return "Доступна с волны %d" % TDConfig.LURE_MIN_WAVE
	if not upcoming_boss.is_empty() or upcoming_special != "":
		return "Не на боссовых и особых волнах"
	if vaccine.get("gene", "") == gene:
		return "На этот ген действует вакцина"
	if lure_exposure_estimate(gene) < TDConfig.LURE_MIN_EXPOSURE:
		if towers.is_empty() or gene in ["tough", "swift"]:
			return "Нужны башни: без обороны нет ни риска, ни награды"
		return "Твоя оборона почти не зависит от этого гена: риска нет, награды не будет"
	if lure_saturation(gene, TDConfig.lure_boost(gene), upcoming) < TDConfig.LURE_MIN_SATURATION:
		return "Ген врагов уже почти максимален: приманка почти ничего не усилит"
	return ""


## Геном с учётом приманки: усиливает ген только в копии, для фенотипа ближайшей волны.
## Геномы напрямую не меняются и прибавка не наследуется; итог боя может косвенно изменить отбор через fitness. RNG не сдвигается.
func lured_genome(ge: Dictionary) -> Dictionary:
	if lure.is_empty():
		return ge
	var copy: Dictionary = ge.duplicate()
	var gene: String = lure["gene"]
	copy[gene] = minf(1.0, float(copy.get(gene, 0.0)) + float(lure["boost"]))
	return copy


func buy_lure(gene: String) -> bool:
	if lure_problem(gene) != "":
		return false
	lure = {"gene": gene, "boost": TDConfig.lure_boost(gene), "wave": wave}
	lure_uses += 1
	return true


# ── Башни ─────────────────────────────────────────────────────

func tower_at(x: int, y: int) -> Tower:
	for t in towers:
		if t.x == x and t.y == y:
			return t
	return null


func count_of(kind: String) -> int:
	var n := 0
	for t in towers:
		if t.kind == kind:
			n += 1
	return n


## Цена следующей башни этого типа: растёт с числом уже стоящих.
func tower_cost(kind: String, owned: int = -1) -> int:
	if owned < 0:
		owned = count_of(kind)
	return int(ceil(TDConfig.TOWERS[kind]["cost"] * (1.0 + _growth() * owned)))


## Насколько дорожает каждый следующий дубль: перк «Оптовик» и «Поставки» из Мастерской.
func _growth() -> float:
	return TDConfig.COST_GROWTH * pow(0.5, perk_level("bulk")) * (1.0 - float(meta.get("growth_cut", 0.0)))


## Башня закрыта достижением, которое игрок ещё не получил (список лежит в meta забега).
func is_locked(kind: String) -> bool:
	return meta.get("locked", []).has(kind)


func difficulty_id() -> String:
	return String(meta.get("difficulty", "normal"))


func mode_id() -> String:
	return String(meta.get("mode", "standard"))


func can_place(kind: String, x: int, y: int) -> bool:
	if phase == "over":
		return false
	if x < 0 or y < 0 or x >= TDConfig.COLS or y >= TDConfig.ROWS:
		return false
	if is_locked(kind) or map.is_path(x, y) or map.is_blocked(x, y) or tower_at(x, y) != null:
		return false
	return gold >= tower_cost(kind)


## Почему нельзя построить в клетке: для подсказки игроку ("" — можно).
func place_problem(kind: String, x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= TDConfig.COLS or y >= TDConfig.ROWS:
		return ""
	if is_locked(kind):
		return "Башня ещё закрыта"
	if map.is_path(x, y):
		return "На дороге строить нельзя"
	if map.is_blocked(x, y):
		return "Здесь скала"
	if tower_at(x, y) != null:
		return "Клетка занята"
	if gold < tower_cost(kind):
		return "Не хватает золота"
	return ""


func place_tower(kind: String, x: int, y: int) -> bool:
	if not can_place(kind, x, y):
		return false
	var cost := tower_cost(kind)
	gold -= cost
	var t := Tower.new()
	t.id = next_id
	next_id += 1
	t.kind = kind
	t.x = x
	t.y = y
	t.spent = cost
	t.def = TDConfig.tower_def(kind, 1, "")
	t.mode = TDConfig.TOWERS[kind].get("mode", "first")
	towers.append(t)
	_ev({"type": "place", "pos": Vector2(x + 0.5, y + 0.5), "kind": kind})
	return true


## Цена следующего улучшения (-1 — улучшать некуда).
func upgrade_cost(t: Tower) -> int:
	# как и постройка, улучшение дорожает с числом башен этого типа
	var base: float = TDConfig.TOWERS[t.kind]["cost"] * (1.0 + _growth() * (count_of(t.kind) - 1)) * (1.0 - float(meta.get("upgrade_disc", 0.0)))
	if t.level == 1:
		return int(ceil(base * TDConfig.UPGRADE_COST))
	if t.level == 2:
		return int(ceil(base * TDConfig.BRANCH_COST))
	return -1


func can_upgrade(t: Tower) -> bool:
	var c := upgrade_cost(t)
	return phase != "over" and c > 0 and gold >= c


## Улучшить башню. На 2→3 нужна ветка "a" или "b".
func upgrade_tower(t: Tower, branch: String = "") -> bool:
	if not can_upgrade(t):
		return false
	if t.level == 2 and TDConfig.branch_def(t.kind, branch).is_empty():
		return false
	var c := upgrade_cost(t)
	gold -= c
	t.spent += c
	t.level += 1
	if t.level == 3:
		t.branch = branch
	t.def = TDConfig.tower_def(t.kind, t.level, t.branch)
	t.upgraded_t = 0.0
	_ev({"type": "upgrade", "pos": Vector2(t.x + 0.5, t.y + 0.5), "kind": t.kind, "level": t.level, "id": t.id,
		"branch_name": String(TDConfig.branch_def(t.kind, t.branch).get("name", ""))})
	return true


func set_mode(t: Tower, mode: String) -> void:
	if mode == "fresh" and not TDConfig.has_status_effect(t.def):
		return
	t.mode = mode


func sell_value(t: Tower) -> int:
	return int(floor(t.spent * TDConfig.SELL_RATIO))


func sell_tower(x: int, y: int) -> bool:
	if phase == "over":
		return false
	var t := tower_at(x, y)
	if t == null:
		return false
	var gain := sell_value(t)
	gold += gain
	_ev({"type": "sell", "pos": Vector2(x + 0.5, y + 0.5), "kind": t.kind, "level": t.level, "branch": t.branch, "gain": gain})
	towers.erase(t)
	return true


func start_wave() -> bool:
	if phase != "build" or not offer.is_empty():
		return false
	phase = "wave"
	pending = upcoming.duplicate()
	wave_genomes = upcoming.duplicate()
	pending_boss = upcoming_boss
	upcoming_boss = {}
	cur_special = upcoming_special
	upcoming_special = ""
	boss_killed = false
	spawn_t = 0.0
	finished = []
	killed = 0
	leaked = 0
	damage_by = _zero_damage()
	for t in towers:
		t.dealt = 0.0
		t.hits = 0
		t.boosted = 0
	if strains_on():
		strain_acc = TDStrains.new_acc()
	return true


# ── Урон ──────────────────────────────────────────────────────

static func status_of(e: Enemy) -> Dictionary:
	return {"chilled": e.slow_t > 0.0, "scorched": e.scorch_t > 0.0, "poisoned": e.poison_t > 0.0,
		"scorch_extra": e.scorch_extra if e.scorch_t > 0.0 else 0.0}


## Физ. урон: обожжённые теряют долю брони, замороженные получают бонус. Яд идёт сквозь всё.
static func effective_damage(dmg: float, type: String, ph: Dictionary, st: Dictionary = {}, mods_: Dictionary = {}, pierce: float = 0.0) -> float:
	if mods_.is_empty():
		mods_ = base_mods()
	if type == "physical":
		var scorched: bool = st.get("scorched", false)
		var chilled: bool = st.get("chilled", false)
		var a: float = ph["armor"]
		if scorched:
			var cut: float = minf(0.95, mods_["scorch"] + float(st.get("scorch_extra", 0.0)))
			a *= 1.0 - cut * (1.0 - ph["fireRes"])
		var armor: float = maxf(0.0, a * (1.0 - pierce) - mods_["pierce"])
		var d: float = maxf(1.0, dmg - armor)
		return d * (1.0 + mods_["shatter"] * (1.0 - ph["frostRes"])) if chilled else d
	if type == "fire":
		return dmg * (1.0 - ph["fireRes"])
	if type == "frost":
		return dmg * (1.0 - ph["frostRes"])
	if type == "shock":
		return dmg * (1.0 + TDConfig.SHOCK_CHILL_BONUS) if st.get("chilled", false) else dmg
	return dmg


func _chill(e: Enemy, strength: float, resisted := true) -> void:
	e.slow_t = TDConfig.SLOW_DURATION
	e.slow_factor = maxf(e.slow_factor, strength * ((1.0 - e.ph["frostRes"]) if resisted else 1.0))


func _hit(e: Enemy, t: Tower, m: Dictionary, mult: float = 1.0) -> void:
	var def: Dictionary = t.def
	var dmg := t_damage(t) * mult
	var pierce: float = def.get("pierce", 0.0)
	var chilled_before: bool = e.slow_t > 0.0
	var base := effective_damage(dmg, def["type"], e.ph, {}, m, pierce)
	var full := effective_damage(dmg, def["type"], e.ph, status_of(e), m, pierce)
	# PRO-152: панцирь пакета гасит урон своего класса ударов (выводок — тяжёлые одиночные, панцирники — лёгкие одиночные);
	# эффекты удара (замедление, яд, ожог) ложатся. Класс — TDStrains.del_class, тот же, что в сигнатуре.
	if e.shell > 0 and TDStrains.deflects(e.strain, TDStrains.del_class(def, dmg, e.ph["hp"])):
		base = 0.0
		full = 0.0
		_ev({"type": "shell", "pos": pos_of(e), "strain": e.strain})
	if e.warded:
		base *= 1.0 - TDConfig.WARD_CUT
		full *= 1.0 - TDConfig.WARD_CUT
	if e.boss and e.ability == "immune" and def["type"] == e.immune_type:
		base *= TDConfig.IMMUNE_MULT
		full *= TDConfig.IMMUNE_MULT
	var through := _absorb(e, full)
	# щит босса тоже считается нанесённым уроном, иначе рой «не заметит» давления
	var dealt: float = minf(e.hp, through) + (full - through)
	e.hp -= minf(e.hp, through)
	# «Палач»: добивает ослабленных
	var ex: float = def.get("execute", 0.0)
	if ex > 0.0 and not e.boss and e.hp > 0.0 and e.hp < ex * e.ph["hp"]:
		dealt += e.hp
		e.hp = 0.0
	if e.hp <= 0.0:
		t.kills += 1
	e.hit_flash = 1.0
	e.last_kind = t.kind
	_ev({"type": "hit", "pos": pos_of(e), "kind": t.kind, "dmg": full, "boosted": full > base * 1.02, "dtype": def["type"]})
	damage_by[t.kind] += dealt
	t.dealt += dealt
	t.hits += 1
	if not strain_acc.is_empty() and TDStrains.eligible(e):
		TDStrains.record_hit(strain_acc, def, t.kind, Vector2(t.x + 0.5, t.y + 0.5), pos_of(e), e.ph["fly"], e.ph["hp"], dmg, dealt, chilled_before)
	if full > base * 1.02:
		t.boosted += 1
		if fx.size() < 120:
			var p := pos_of(e)
			fx.append({"x1": p.x, "y1": p.y - 0.3, "x2": p.x, "y2": p.y, "color": Color("#ffd35a"), "t": 0.6, "life": 0.6, "ring": 0.0, "text": "✦%d" % int(round(full))})
	if def.get("slow", 0.0) > 0.0:
		_chill(e, def["slow"], not def.get("net", false))
	if t.kind == "cannon" and perk_level("coldshell") > 0:
		_chill(e, 0.3)
	if def["type"] == "poison":
		_poison(e, TDConfig.POISON_DPS * (dmg / TDConfig.TOWERS[t.kind]["damage"]) * def.get("poison_mult", 1.0), t)
	if def["type"] == "fire":
		if e.scorch_t <= 0.0:
			e.scorch_extra = 0.0
		e.scorch_t = TDConfig.SCORCH_DURATION
		e.scorch_extra = maxf(e.scorch_extra, def.get("scorch_bonus", 0.0))
		var sparks := perk_level("wildfire")
		if sparks > 0:
			var p2 := pos_of(e)
			for o in enemies:
				if o == e or o.hp <= 0.0:
					continue
				if pos_of(o).distance_to(p2) <= 0.4 + 0.4 * sparks:
					o.scorch_t = TDConfig.SCORCH_DURATION


## Щит босса гасит урон первым; возвращает, сколько прошло дальше.
func _absorb(e: Enemy, dmg: float) -> float:
	if e.shield <= 0.0:
		return dmg
	var a := minf(e.shield, dmg)
	e.shield -= a
	return dmg - a


## Яд не складывается: сильный заменяет слабый, слабый лишь продлевает.
func _poison(e: Enemy, dps: float, by: Tower) -> void:
	e.poison_t = TDConfig.POISON_DURATION
	if dps >= e.poison_dps or e.poison_by == null:
		e.poison_dps = dps
		e.poison_by = by


## Какой статус накладывает башня (для режима «Без эффекта»).
static func _has_status_of(e: Enemy, def: Dictionary) -> bool:
	match def["type"]:
		"poison":
			return e.poison_t > 0.0
		"fire":
			return e.scorch_t > 0.0
		"frost":
			return e.slow_t > 0.0
	if def.get("slow", 0.0) > 0.0:
		return e.slow_t > 0.0
	return false


## Цели башни по её режиму, лучшие первыми (не больше n).
func _pick_targets(t: Tower, c: Vector2, n: int) -> Array[Enemy]:
	var def: Dictionary = t.def
	var r := t_range(t)
	var cand: Array = []
	for e in enemies:
		if e.hp <= 0.0 or not can_hit(def, e) or not _visible_to(e, c):
			continue
		if pos_of(e).distance_to(c) > r:
			continue
		var key := progress_of(e)
		match t.mode:
			"strong":
				key = e.hp + key * 0.001
			"fresh":
				if not _has_status_of(e, def):
					key += 10.0
		cand.append([key, e])
	if n == 1:
		var best = null
		for x in cand:
			if best == null or x[0] > best[0]:
				best = x
		var one: Array[Enemy] = []
		if best != null:
			one.append(best[1])
		return one
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array[Enemy] = []
	for i in mini(n, cand.size()):
		out.append(cand[i][1])
	return out


func step(dt: float) -> void:
	# эффекты живут и в паузе между волнами
	for f in fx:
		f["t"] -= dt
	fx = fx.filter(func(f): return f["t"] > 0.0)
	for tw in towers:
		tw.recoil = maxf(0.0, tw.recoil - dt * 5.0)
		tw.age += dt
		tw.upgraded_t += dt
	for en in enemies:
		en.hit_flash = maxf(0.0, en.hit_flash - dt * 6.0)
	if phase != "wave":
		return

	# спавн; босс выходит, когда прошла половина волны
	spawn_t -= dt
	var half: int = wave_genomes.size() / 2
	while (not pending.is_empty() or not pending_boss.is_empty()) and spawn_t <= 0.0:
		var is_boss: bool = not pending_boss.is_empty() and pending.size() <= half
		var genome: Dictionary = pending_boss if is_boss else pending.pop_front()
		# приманка усиливает фенотип врагов обычной волны; сам геном (для отбора) остаётся прежним
		var ph: Dictionary = TDGenome.phenotype(lured_genome(genome) if not is_boss else genome, wave)
		var sp: Dictionary = TDConfig.SPECIAL_WAVES.get(cur_special, {})
		var hp_mult: float = float(TDConfig.difficulty(meta)["hp"])
		if is_boss:
			var wavehp := 0.0
			for ge in wave_genomes:
				wavehp += TDGenome.phenotype(ge, wave)["hp"]
			ph = ph.duplicate()
			ph["hp"] = wavehp * TDConfig.boss_hp_share(wave)
			ph["speed"] = ph["speed"] * TDConfig.BOSS_SPEED
			ph["size"] = 0.5
			ph["fly"] = false
			ph["stealth"] = false
			ph["regen"] = 0.0
			pending_boss = {}
		elif not sp.is_empty():
			ph = ph.duplicate()
			ph["hp"] = ph["hp"] * sp["hp"]
			ph["speed"] = ph["speed"] * sp["speed"]
		if hp_mult != 1.0:
			ph = ph.duplicate()
			ph["hp"] = ph["hp"] * hp_mult
		var strain: String = "" if is_boss else String(genome.get("strain", ""))
		if strain != "":
			ph = TDStrains.apply_ph(ph, strain)
		var e := Enemy.new()
		e.id = next_id
		next_id += 1
		e.genome = genome
		e.ph = ph
		e.hp = ph["hp"]
		e.boss = is_boss
		if not is_boss and not lure.is_empty():
			e.lured_gene = String(lure["gene"])
		if is_boss:
			e.ability = TDConfig.boss_ability(wave)
			e.immune_type = String(genome.get("immune_type", "physical"))
			e.summon_t = 3.0
			e.summon_left = TDConfig.SUMMON_BATCHES
			if e.ability == "shield":
				e.shield_max = ph["hp"] * TDConfig.SHIELD_SHARE
				e.shield = e.shield_max
		enemies.append(e)
		if strain != "":
			_spawn_strain(e, strain)
		spawn_t += TDConfig.SPAWN_INTERVAL

	# движение, лечение, яд
	var summoned: Array[Enemy] = []
	for e in enemies:
		if e.boss and e.ability == "summon" and e.hp > 0.0 and e.summon_left > 0:
			e.summon_t -= dt
			if e.summon_t <= 0.0 and enemies.size() < 90:
				e.summon_t = TDConfig.SUMMON_EVERY
				e.summon_left -= 1
				summoned.append_array(_summon(e))
		if e.slow_t > 0.0:
			e.slow_t -= dt
		if e.scorch_t > 0.0:
			e.scorch_t -= dt
		if e.poison_t > 0.0:
			e.poison_t -= dt
			e.last_kind = "poison"
			var raw: float = e.poison_dps * dt * (1.0 - TDConfig.WARD_CUT if e.warded else 1.0)
			if e.boss and e.ability == "immune" and e.immune_type == "poison":
				raw *= TDConfig.IMMUNE_MULT
			var through := _absorb(e, raw)
			var d: float = minf(e.hp, through)
			e.hp -= d
			damage_by["poison"] += d + (raw - through)
			if not strain_acc.is_empty() and TDStrains.eligible(e) and e.poison_by != null:
				TDStrains.record_dot(strain_acc, Vector2(e.poison_by.x + 0.5, e.poison_by.y + 0.5), pos_of(e), e.ph["fly"], d, e.slow_t > 0.0)
			if e.poison_by != null:
				e.poison_by.dealt += d
				if e.hp <= 0.0 and d > 0.0:
					e.poison_by.kills += 1
		elif e.ph["regen"] > 0.0 and e.hp > 0.0:
			e.hp = minf(e.ph["hp"], e.hp + e.ph["regen"] * e.ph["hp"] * dt)
		var k: float = 1.0 - e.slow_factor if e.slow_t > 0.0 else 1.0
		e.dist += e.ph["speed"] * k * dt
		if not strain_acc.is_empty() and e.hp > 0.0 and TDStrains.eligible(e):
			TDStrains.record_time(strain_acc, e.slow_t > 0.0 and e.slow_factor > 0.0, dt)
	for e in enemies:
		if e.dist >= path_len_of(e) and e.hp > 0.0:
			lives -= TDConfig.BOSS_LEAK if e.boss else 1
			leaked += 1
			run_leaked += 1
			_ev({"type": "leak", "pos": map.points[map.points.size() - 1], "boss": e.boss})
			if not e.boss and not e.child:
				finished.append({"genome": e.genome, "fitness": 1.5})
			e.hp = 0.0
			e.dist = -1.0 # помечаем как прорвавшегося

	enemies.append_array(summoned)

	# щит: враги рядом с носителем получают меньше урона (сам носитель — нет)
	var wards: Array[Vector2] = []
	for e in enemies:
		if e.hp > 0.0 and e.ph.get("ward", false):
			wards.append(pos_of(e))
	for e in enemies:
		e.warded = false
		if wards.is_empty() or e.ph.get("ward", false):
			continue
		var pe := pos_of(e)
		for w in wards:
			if pe.distance_to(w) <= TDConfig.WARD_RADIUS:
				e.warded = true
				break

	# башни
	var m := mods()
	for t in towers:
		var def: Dictionary = t.def
		if def.has("aura"):
			continue
		t.cd -= dt
		if t.cd > 0.0:
			continue
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		var targets := _pick_targets(t, c, int(def.get("multishot", 1)))
		if targets.is_empty():
			continue
		t.cd = t_cooldown(t)
		var col := Color(def["color"])
		var splash: float = def.get("splash", 0.0)
		t.recoil = 1.0
		for target in targets:
			var tp := pos_of(target)
			fx.append({"x1": c.x, "y1": c.y, "x2": tp.x, "y2": tp.y, "color": col, "t": 0.12, "life": 0.12, "ring": 0.0, "text": "", "kind": t.kind})
			t.aim = (tp - c).normalized()
			_ev({"type": "shot", "kind": t.kind, "tower_id": t.id, "from": c, "to": tp, "color": col, "splash": splash, "level": t.level})
			if splash > 0.0:
				fx.append({"x1": tp.x, "y1": tp.y, "x2": tp.x, "y2": tp.y, "color": col, "t": 0.2, "life": 0.2, "ring": splash, "text": ""})
				for e in enemies:
					if e.hp <= 0.0 or not can_hit(def, e) or not _visible_to(e, c):
						continue
					if pos_of(e).distance_to(tp) <= splash:
						_hit(e, t, m)
			elif target.hp > 0.0:
				_hit(target, t, m)
			# цепная молния: перескакивает на ближайших ещё не задетых
			var chain: int = int(def.get("chain", 1))
			if chain > 1:
				var hit_set := {target: true}
				var cur := target
				var mult := 1.0
				for j in chain - 1:
					var from_p := pos_of(cur)
					var nxt: Enemy = null
					var nd: float = def.get("chain_range", 1.5)
					for e in enemies:
						if e.hp <= 0.0 or hit_set.has(e) or not can_hit(def, e) or not is_revealed(e):
							continue
						var dd := pos_of(e).distance_to(from_p)
						if dd <= nd:
							nd = dd
							nxt = e
					if nxt == null:
						break
					mult *= TDConfig.CHAIN_FALLOFF
					hit_set[nxt] = true
					_ev({"type": "shot", "kind": t.kind, "tower_id": t.id, "from": from_p, "to": pos_of(nxt), "color": col, "splash": 0.0, "level": t.level, "hop": true})
					_hit(nxt, t, m, mult)
					cur = nxt

	# смерти и утечки
	var bounty: int = TDConfig.KILL_REWARD + perk_level("bounty")
	var alive: Array[Enemy] = []
	var born: Array[Enemy] = []
	for e in enemies:
		if e.hp > 0.0:
			alive.append(e)
		elif e.dist >= 0.0 and e.child:
			# малыши дают меньше золота и не считаются в итогах волны
			gold += TDConfig.SPLIT_REWARD
			_ev({"type": "death", "pos": pos_of(e), "heading": map.heading_at(e.dist, e.ph["fly"]), "genome": e.genome, "boss": false, "size": e.ph["size"], "fly": e.ph["fly"], "kind": e.last_kind, "gold": TDConfig.SPLIT_REWARD})
		elif e.dist >= 0.0:
			killed += 1
			if e.ph.get("split", false) and not e.boss:
				born.append_array(_split(e))
			# «Чума»: яд перекидывается на соседей
			if e.poison_t > 0.0 and e.poison_by != null and e.poison_by.def.get("plague", 0.0) > 0.0:
				var pp := pos_of(e)
				var pr: float = e.poison_by.def["plague"]
				for o in enemies:
					if o != e and o.hp > 0.0 and pos_of(o).distance_to(pp) <= pr:
						_poison(o, e.poison_dps, e.poison_by)
				fx.append({"x1": pp.x, "y1": pp.y, "x2": pp.x, "y2": pp.y, "color": Color("#7ddc5a"), "t": 0.35, "life": 0.35, "ring": pr, "text": ""})
			_ev({"type": "death", "pos": pos_of(e), "heading": map.heading_at(e.dist, e.ph["fly"]), "genome": e.genome, "boss": e.boss, "size": e.ph["size"], "fly": e.ph["fly"], "kind": e.last_kind, "gold": TDConfig.boss_bonus(wave) if e.boss else bounty})
			run_kills += 1
			if e.boss:
				boss_killed = true
				bosses_killed += 1
				gold += TDConfig.boss_bonus(wave)
				var bp := pos_of(e)
				fx.append({"x1": bp.x, "y1": bp.y - 0.4, "x2": bp.x, "y2": bp.y, "color": Color("#ffd35a"), "t": 1.2, "life": 1.2, "ring": 0.0, "text": "+%d" % TDConfig.boss_bonus(wave)})
			else:
				# носитель кладки выводка: награда за кладку целиком равна награде за одного врага
				gold += bounty if e.strain != "brood" else maxi(0, bounty - (TDStrains.BROOD_N - 1) * TDConfig.SPLIT_REWARD)
				finished.append({"genome": e.genome, "fitness": minf(1.0, progress_of(e))})
	alive.append_array(born)
	enemies = alive

	if lives <= 0:
		lives = 0
		phase = "over"
		return
	if pending.is_empty() and pending_boss.is_empty() and enemies.is_empty():
		_end_wave()


## PRO-152: враг пакета. Выводок — носитель и малыши кладки (малыши как дети деления: без отбора, награда SPLIT_REWARD);
## у малышей и панцирников есть панцирь (shell = 1).
func _spawn_strain(e: Enemy, strain: String) -> void:
	e.strain = strain
	if TDStrains.DEFLECT.has(strain):
		e.shell = 1
	if strain != "brood":
		return
	for i in TDStrains.BROOD_N - 1:
		var c := Enemy.new()
		c.id = next_id
		next_id += 1
		c.genome = e.genome
		c.ph = e.ph.duplicate()
		# чуть разная скорость: кладка идёт плотной кучкой и не сливается в одну точку
		c.ph["speed"] = e.ph["speed"] * (1.0 - 0.06 * (i + 1))
		c.hp = c.ph["hp"]
		c.child = true
		c.strain = strain
		c.shell = 1
		c.lured_gene = e.lured_gene
		enemies.append(c)


## Особая волна меняет число врагов: нашествие добавляет копии, бронеколонна оставляет часть.
func _apply_special(id: String) -> void:
	var sp: Dictionary = TDConfig.SPECIAL_WAVES.get(id, {})
	if sp.is_empty():
		return
	var n: int = upcoming.size()
	var target: int = maxi(4, int(round(n * float(sp["count"]))))
	if target < n:
		upcoming = upcoming.slice(0, target)
	else:
		var i := 0
		while upcoming.size() < target:
			upcoming.append(upcoming[i % n].duplicate())
			i += 1


## Деление: двое малышей с частью здоровья родителя, чуть разбегаются по дороге.
func _split(e: Enemy) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var g: Dictionary = e.genome.duplicate()
	g["split"] = 0.0
	g["ward"] = 0.0
	for i in TDConfig.SPLIT_COUNT:
		var c := Enemy.new()
		c.id = next_id
		next_id += 1
		c.genome = g
		c.ph = e.ph.duplicate()
		c.ph["hp"] = e.ph["hp"] * TDConfig.SPLIT_HP
		c.ph["size"] = e.ph["size"] * 0.7
		c.ph["split"] = false
		c.ph["ward"] = false
		c.ph["speed"] = e.ph["speed"] * 1.15
		c.hp = c.ph["hp"]
		c.dist = maxf(0.0, e.dist - 0.25 * i)
		c.child = true
		c.lured_gene = e.lured_gene
		out.append(c)
	_ev({"type": "split", "pos": pos_of(e)})
	return out


## Босс-призыватель: быстрые прислужники (как малыши деления — без золота и опыта для роя).
func _summon(b: Enemy) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for i in TDConfig.SUMMON_COUNT:
		var c := Enemy.new()
		c.id = next_id
		next_id += 1
		c.genome = b.genome
		c.ph = b.ph.duplicate()
		c.ph["hp"] = b.ph["hp"] * TDConfig.SUMMON_HP
		c.ph["size"] = 0.22
		c.ph["speed"] = TDConfig.SUMMON_SPEED
		c.ph["armor"] = 0.0
		c.ph["regen"] = 0.0
		c.ph["split"] = false
		c.ph["ward"] = false
		c.hp = c.ph["hp"]
		c.dist = maxf(0.0, b.dist - 0.3 * i)
		c.child = true
		out.append(c)
	_ev({"type": "split", "pos": pos_of(b)})
	return out


## Босс-зеркало: перенимает черты, против которых ты чаще всего бил.
func _make_boss(dmg_by: Dictionary) -> Dictionary:
	var phys := 0.0
	var fire := 0.0
	var frost := 0.0
	var total := 0.0
	var by_type := {}
	for k in TDConfig.TOWER_KINDS:
		var d: float = dmg_by[k]
		total += d
		var type: String = TDConfig.TOWERS[k]["type"]
		by_type[type] = float(by_type.get(type, 0.0)) + d
		if type == "physical":
			phys += d
		elif type == "fire":
			fire += d
		elif type == "frost":
			frost += d
	if total == 0.0:
		total = 1.0
	var top := "physical"
	var top_v := -1.0
	for type in by_type:
		if by_type[type] > top_v:
			top_v = by_type[type]
			top = type
	return {
		"immune_type": top,
		"tough": 1.0, "swift": 0.1,
		"plated": _cap(phys / total * 1.1), "ember": _cap(fire / total * 2.5), "frost": _cap(frost / total * 2.5),
		"wings": 0.0, "veil": 0.0, "regen": 0.0, "split": 0.0, "ward": 0.0,
	}


static func _cap(v: float) -> float:
	return maxf(0.0, minf(0.9, v))


func _end_wave() -> void:
	var w := wave
	var prev: Dictionary = reports[reports.size() - 1]["avg"] if not reports.is_empty() else {}
	var next_wave := w + 1
	var press := TDGenome.pressure(damage_by)
	var adapt := {}
	var adapt_mult: float = float(TDConfig.difficulty(meta)["adapt"])
	for k in press:
		adapt[k] = press[k] * adapt_mult
	var caps := {}
	if not vaccine.is_empty():
		vaccine["left"] = int(vaccine["left"]) - 1
		if int(vaccine["left"]) > 0:
			caps[vaccine["gene"]] = vaccine["cap"]
		else:
			vaccine = {}
			vaccine_cd = TDConfig.VACCINE_COOLDOWN
	elif vaccine_cd > 0:
		vaccine_cd -= 1
	upcoming = TDGenome.evolve(finished, TDConfig.wave_size(next_wave), next_wave, rng, adapt, caps)
	upcoming_special = TDConfig.special_for(next_wave)
	_apply_special(upcoming_special)
	reports.append({
		"pressure": press,
		"wave": w,
		"size": wave_genomes.size(),
		"killed": killed,
		"leaked": leaked,
		"avg": TDGenome.average_genome(wave_genomes),
		"prevAvg": prev,
		"nextAvg": TDGenome.average_genome(upcoming),
		"damageBy": damage_by.duplicate(),
		"interest": 0,
		"bonus": TDConfig.wave_bonus(w),
	})
	if strains_on():
		reports[reports.size() - 1]["strains"] = TDStrains.end_wave(self, w)
	# проценты считаются с того, что накоплено к концу волны (до бонуса)
	var lure_bonus := 0
	if not lure.is_empty() and int(lure["wave"]) == w:
		var lgene: String = lure["gene"]
		var income := _lure_income(killed, w)
		var exposure := lure_exposure_actual(lgene, damage_by, killed > 0)
		var saturation := lure_saturation(lgene, float(lure["boost"]), wave_genomes)
		if exposure >= TDConfig.LURE_MIN_EXPOSURE:
			lure_bonus = int(round(TDConfig.LURE_SHARE * income * exposure * saturation))
		reports[reports.size() - 1]["lure"] = {"gene": lgene, "bonus": lure_bonus, "exposure": exposure, "saturation": saturation, "income": income}
		lure = {}
		lure_cd = TDConfig.LURE_COOLDOWN
	elif lure_cd > 0:
		lure_cd -= 1
	var interest: int = mini(TDConfig.INTEREST_CAP, int(floor(gold * TDConfig.INTEREST)))
	reports[reports.size() - 1]["interest"] = interest
	var bonus: int = TDConfig.wave_bonus(w)
	if cur_special != "":
		bonus = int(round(bonus * TDConfig.SPECIAL_BONUS))
		reports[reports.size() - 1]["bonus"] = bonus
		reports[reports.size() - 1]["special"] = cur_special
	gold += bonus + interest + lure_bonus
	for k in damage_by:
		run_damage[k] = float(run_damage.get(k, 0.0)) + damage_by[k]
	if w == TDConfig.VICTORY_WAVE and mode_id() != "endless":
		victory = true
		_ev({"type": "victory"})
	wave = next_wave
	phase = "build"
	if next_wave % TDConfig.BOSS_EVERY == 0:
		upcoming_boss = _make_boss(reports[reports.size() - 1]["damageBy"])
	# перк даётся каждые N волн и за победу над боссом
	if w % TDConfig.PERK_EVERY == 0 or boss_killed:
		offer = _draw_offer()
