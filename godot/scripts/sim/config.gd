class_name TDConfig
extends RefCounted
## Константы баланса, башни и перки.

const COLS := 16
const ROWS := 10

## kind -> определение башни. type: physical | fire | frost | poison
const TOWERS := {
	"arrow": {
		"kind": "arrow", "cat": "damage", "name": "Лучники", "role": "Дёшево, бьёт всех",
		"hint": "Быстрые слабые стрелы. Броня съедает урон; лёд усиливает.",
		"icon": "tower-arrow", "cost": 25, "range": 3.2, "cooldown": 0.45, "damage": 6.0,
		"type": "physical", "ground": true, "air": true, "color": "#d6bd85",
	},
	"cannon": {
		"kind": "cannon", "cat": "damage", "name": "Пушка", "role": "Взрыв по земле",
		"hint": "Тяжёлый удар по площади, пробивает броню. Не бьёт летающих.",
		"icon": "tower-cannon", "cost": 75, "range": 2.6, "cooldown": 1.7, "damage": 28.0,
		"type": "physical", "ground": true, "air": false, "splash": 0.85, "color": "#9aa3b2",
	},
	"ember": {
		"kind": "ember", "cat": "effect", "name": "Огонь", "role": "Плавит броню",
		"hint": "Поджигает: обожжённые теряют часть брони. Огнестойкие её почти не боятся.",
		"icon": "tower-ember", "cost": 40, "range": 2.6, "cooldown": 0.6, "damage": 8.0,
		"type": "fire", "ground": true, "air": true, "color": "#ef6a3c",
	},
	"frost": {
		"kind": "frost", "cat": "effect", "name": "Лёд", "role": "Замедляет и ломает",
		"hint": "Замедляет врагов. Замороженные получают больше физического урона.",
		"icon": "tower-frost", "cost": 40, "range": 3.0, "cooldown": 0.9, "damage": 4.0,
		"type": "frost", "ground": true, "air": true, "slow": 0.45, "splash": 0.7, "color": "#62bdf0",
	},
	"sniper": {
		"kind": "sniper", "cat": "damage", "name": "Снайпер", "role": "Далеко и мощно",
		"hint": "Редкий мощный выстрел через пол-карты. Игнорирует половину брони.",
		"icon": "tower-sniper", "cost": 100, "range": 5.2, "cooldown": 2.5, "damage": 55.0,
		"type": "physical", "ground": true, "air": true, "pierce": 1.0, "color": "#c9a0ff",
	},
	"poison": {
		"kind": "poison", "cat": "effect", "name": "Яд", "role": "Против лечения",
		"hint": "Яд тикает сквозь броню и сопротивления и не даёт врагу лечиться.",
		"icon": "tower-poison", "cost": 50, "range": 2.8, "cooldown": 1.1, "damage": 2.0,
		"type": "poison", "ground": true, "air": true, "mode": "fresh", "color": "#7ddc5a",
	},
	"flak": {
		"kind": "flak", "cat": "damage", "name": "Зенитка", "role": "Только по воздуху",
		"hint": "Взрывает летающих по площади. Землю не бьёт.",
		"icon": "tower-flak", "cost": 70, "range": 3.4, "cooldown": 0.9, "damage": 11.0,
		"type": "physical", "ground": false, "air": true, "splash": 1.0, "color": "#ffb347",
	},
	"tesla": {
		"kind": "tesla", "cat": "damage", "name": "Тесла", "role": "Цепная молния",
		"hint": "Молния бьёт цель и перескакивает ещё на двоих рядом. Броня не спасает, замороженные получают +50%.",
		"icon": "tower-tesla", "cost": 80, "range": 2.8, "cooldown": 1.3, "damage": 14.0,
		"type": "shock", "ground": true, "air": true, "chain": 3, "chain_range": 1.6, "color": "#7fe3ff",
	},
	"net": {
		"kind": "net", "cat": "effect", "name": "Сеть", "role": "Тормозит летающих",
		"hint": "Накидывает сеть на летающих: сильно замедляет, ледяная защита не помогает. Землю не бьёт.",
		"icon": "tower-net", "cost": 55, "range": 3.4, "cooldown": 1.1, "damage": 3.0,
		"type": "physical", "ground": false, "air": true, "slow": 0.6, "splash": 0.9, "net": true, "color": "#37c9a0",
	},
	"beacon": {
		"kind": "beacon", "cat": "support", "name": "Маяк", "role": "Видит невидимок, ускоряет",
		"hint": "Не стреляет. Показывает невидимых врагов рядом и ускоряет стрельбу соседних башен.",
		"icon": "tower-beacon", "cost": 90, "range": 0.0, "cooldown": 1.0, "damage": 0.0,
		"type": "physical", "ground": false, "air": false,
		"aura": {"radius": 2.6, "fireRate": 0.25}, "color": "#ffe27a",
	},
}

## ── Улучшения ─────────────────────────────────────────────────
## Уровень 2 — общий прирост; уровень 3 — выбор одной из двух веток.
## Моды веток: damage/cooldown — множители; range/splash_add/aura_radius/scorch_bonus — прибавка;
## splash/slow/pierce/multishot/execute/plague/poison_mult/aura_rate — новое значение.
const MAX_LEVEL := 3
const UPGRADE_COST := 0.75
const BRANCH_COST := 1.25
const LEVEL2 := {"damage": 1.4, "range": 0.3, "cooldown": 0.9, "aura_radius": 0.3}
const LEVEL3 := {"damage": 1.25}

const BRANCHES := {
	"arrow": [
		{"id": "a", "name": "Залп", "icon": "perk-rapid", "desc": "Стреляет сразу в 3 цели, каждая стрела на 25% слабее", "mods": {"multishot": 3, "damage": 0.75}},
		{"id": "b", "name": "Бронебой", "icon": "gene-plated", "desc": "Урон +25%, игнорирует половину брони", "mods": {"damage": 1.25, "pierce": 0.5}},
	],
	"cannon": [
		{"id": "a", "name": "Мортира", "icon": "perk-range", "desc": "Дальность +1.4, взрыв шире", "mods": {"range": 1.4, "splash_add": 0.35}},
		{"id": "b", "name": "Осадная", "icon": "dmg-physical", "desc": "Урон ×1.9, пробивает половину брони, стреляет реже", "mods": {"damage": 1.9, "cooldown": 1.25, "pierce": 0.5}},
	],
	"ember": [
		{"id": "a", "name": "Пекло", "icon": "st-burn", "desc": "Поджигает всех в радиусе 0.7", "mods": {"splash": 0.7}},
		{"id": "b", "name": "Плавильня", "icon": "perk-scorch", "desc": "Обожжённые теряют ещё +30% брони, урон +30%", "mods": {"scorch_bonus": 0.3, "damage": 1.3}},
	],
	"frost": [
		{"id": "a", "name": "Вьюга", "icon": "st-frozen", "desc": "Шире облако, замедление 55%", "mods": {"splash_add": 0.5, "slow": 0.55}},
		{"id": "b", "name": "Стужа", "icon": "perk-shatter", "desc": "Одна цель: замедление 75%, урон ×3", "mods": {"splash": 0.0, "slow": 0.75, "damage": 3.0}},
	],
	"sniper": [
		{"id": "a", "name": "Палач", "icon": "boss", "desc": "Добивает врагов с запасом здоровья ниже 25% (кроме босса)", "mods": {"execute": 0.25}},
		{"id": "b", "name": "Дальнобой", "icon": "perk-range", "desc": "Дальность +2, стреляет на 30% чаще", "mods": {"range": 2.0, "cooldown": 0.7}},
	],
	"poison": [
		{"id": "a", "name": "Чума", "icon": "st-poison", "desc": "Умирая, отравленный заражает соседей", "mods": {"plague": 1.3}},
		{"id": "b", "name": "Токсин", "icon": "gene-regen", "desc": "Яд в 2.2 раза сильнее", "mods": {"poison_mult": 2.2}},
	],
	"flak": [
		{"id": "a", "name": "Кассета", "icon": "dmg-physical", "desc": "Взрыв шире на 0.6", "mods": {"splash_add": 0.6}},
		{"id": "b", "name": "Скорострел", "icon": "perk-rapid", "desc": "Стреляет почти вдвое чаще", "mods": {"cooldown": 0.55}},
	],
	"tesla": [
		{"id": "a", "name": "Шторм", "icon": "tower-tesla", "desc": "Молния прыгает по 5 целям", "mods": {"chain": 5, "chain_range": 1.9}},
		{"id": "b", "name": "Конденсатор", "icon": "st-boost", "desc": "Урон ×1.8, стреляет немного реже", "mods": {"damage": 1.8, "cooldown": 1.15}},
	],
	"net": [
		{"id": "a", "name": "Паутина", "icon": "st-frozen", "desc": "Сеть шире на 0.6, замедление 75%", "mods": {"splash_add": 0.6, "slow": 0.75}},
		{"id": "b", "name": "Гарпун", "icon": "perk-pierce", "desc": "Одна цель: урон ×6, пробивает половину брони", "mods": {"splash": 0.0, "damage": 6.0, "cooldown": 1.3, "pierce": 0.5}},
	],
	"beacon": [
		{"id": "a", "name": "Прожектор", "icon": "gene-veil", "desc": "Радиус +1.4", "mods": {"aura_radius": 1.4}},
		{"id": "b", "name": "Штаб", "icon": "perk-rapid", "desc": "Соседи стреляют на 45% чаще", "mods": {"aura_rate": 0.45}},
	],
}

## Режимы прицела. "fresh" — сперва враги без эффекта этой башни (только для башен с эффектом).
const TARGET_MODES: Array[Dictionary] = [
	{"id": "first", "name": "Первый", "desc": "Тот, кто ближе всех к замку"},
	{"id": "strong", "name": "Сильный", "desc": "У кого больше всего здоровья"},
	{"id": "fresh", "name": "Без эффекта", "desc": "Сперва те, на ком ещё нет эффекта этой башни"},
]

## Проценты: в конце волны к золоту добавляется доля накопленного, но не больше потолка.
const INTEREST := 0.05
const INTEREST_CAP := 20

## Вкладки магазина. У каждой башни в TOWERS есть поле "cat".
const CATEGORIES: Array[Dictionary] = [
	{"id": "all", "name": "Все"},
	{"id": "damage", "name": "Урон"},
	{"id": "effect", "name": "Эффекты"},
	{"id": "support", "name": "Помощь"},
]

const TOWER_KINDS: Array[String] = ["arrow", "cannon", "ember", "frost", "sniper", "poison", "flak", "tesla", "beacon", "net"]

const START_GOLD := 110
const START_LIVES := 20
## Цель забега: пережить столько волн. Дальше игра продолжается без конца.
const VICTORY_WAVE := 30
const SELL_RATIO := 0.7
## Каждая уже стоящая башня того же типа удорожает следующую на эту долю базовой цены.
const COST_GROWTH := 0.10
const KILL_REWARD := 3
const SPAWN_INTERVAL := 0.6
const SLOW_DURATION := 1.5

# Связки: холод делает цель хрупкой, огонь плавит броню.
const SHATTER_BONUS := 0.5
const SCORCH_ARMOR_CUT := 0.5
const SCORCH_DURATION := 2.5

# Тесла: каждый следующий прыжок молнии слабее, замороженные получают бонус.
const CHAIN_FALLOFF := 0.85
const SHOCK_CHILL_BONUS := 0.5

# Деление и щит роя.
const SPLIT_COUNT := 2
const SPLIT_HP := 0.3
const SPLIT_REWARD := 1
const WARD_RADIUS := 1.3
const WARD_CUT := 0.3

const POISON_DURATION := 3.0
const POISON_DPS := 7.0
## Сколько маяков суммарно ускоряют одну башню.
const BEACON_STACK := 2
const FLYER_SPEED := 0.6
const FLYER_HP := 0.75
## Невидимку без Маяка всё же видит башня, если он вплотную к ней.
const SELF_DETECT := 1.2

const PERKS: Array[Dictionary] = [
	{"id": "shatter", "icon": "perk-shatter", "name": "Хрупкость", "desc": "Замороженные получают ещё +20% физ. урона", "max": 3},
	{"id": "pierce", "icon": "perk-pierce", "name": "Бронебойность", "desc": "Физические удары игнорируют 1 броню", "max": 3},
	{"id": "scorch", "icon": "perk-scorch", "name": "Плавление", "desc": "Огонь срезает ещё +20% брони", "max": 2},
	{"id": "wildfire", "icon": "perk-wildfire", "name": "Искры", "desc": "Огненный удар поджигает соседей", "max": 2},
	{"id": "coldshell", "icon": "perk-coldshell", "name": "Ледяные ядра", "desc": "Взрыв пушки замораживает всех в радиусе", "max": 1},
	{"id": "rapid", "icon": "perk-rapid", "name": "Скорострельность", "desc": "Все башни стреляют на 10% чаще", "max": 2},
	{"id": "range", "icon": "perk-range", "name": "Дальний прицел", "desc": "Все башни бьют на 0.4 клетки дальше", "max": 2},
	{"id": "bounty", "icon": "perk-bounty", "name": "Трофеи", "desc": "+1 золото за каждого убитого", "max": 1},
	{"id": "lives", "icon": "perk-lives", "name": "Укрепления", "desc": "+3 жизни сразу", "max": 3},
	{"id": "bulk", "icon": "perk-bulk", "name": "Оптовик", "desc": "Дубликаты башен дорожают вдвое медленнее", "max": 2},
	{"id": "variety", "icon": "perk-variety", "name": "Разнообразие", "desc": "+4% урона за каждый тип башен на поле", "max": 1},
]

const PERK_EVERY := 3

# Вакцина: за золото между волнами выбранный ген не может вырасти выше потолка.
# Потолок = среднее значение гена в последней сыгранной волне (запоминается при покупке).
# Действует на ближайшую волну и на следующую за ней; одна вакцина за раз, затем пауза.
const VACCINE_WAVES := 2
const VACCINE_COOLDOWN := 2
const VACCINE_BASE_COST := 40
const VACCINE_WAVE_COST := 6
## Против редких признаков (полёт, невидимость, лечение, деление, щит) вакцина доступна только через столько волн после их появления: нельзя «вычеркнуть» новую механику до знакомства с ней.
const VACCINE_TRAIT_DELAY := 3

# Приманка: добровольно усилить один базовый ген следующей волны за долю золота этой волны.
# Эффект: фенотип врагов волны считается с геном +boost (до 1.0); геномы роя не меняются: приманка не наследуется и не трогает rng. Награда: LURE_SHARE от дохода волны
# (убитые × награда за убийство + бонус за волну) × exposure × saturation, если волна пройдена. Одна за раз, затем пауза; не на боссовых и особых волнах.
const LURE_GENES: Array[String] = ["tough", "swift", "plated", "ember", "frost"]
const LURE_BOOST := 0.2
## Прибавка своя для каждого гена: подобрана ботами так, чтобы приманки были сопоставимы по риску и ни одна не была бесплатной.
const LURE_BOOSTS := {"tough": 0.2, "swift": 0.4, "plated": 0.5, "ember": 0.7, "frost": 0.7}
const LURE_SHARE := 0.3
const LURE_COOLDOWN := 1
const LURE_MIN_WAVE := 3
## Риск должен быть настоящим: награда умножается на долю обороны, которую ген действительно затрагивает (exposure),
## и на степень, в которой ген реально усилился (saturation: у насыщенного гена прибавка упирается в 1.0).
## Ниже этих порогов приманку взять нельзя, а при выплате ниже порога exposure награда равна нулю.
const LURE_MIN_EXPOSURE := 0.15
const LURE_MIN_SATURATION := 0.5
const PERK_CHOICES := 3

# Боссы: каждые N волн приходит «зеркало» твоей обороны.
const BOSS_EVERY := 10
const BOSS_SPEED := 0.55
const BOSS_LEAK := 5


## Способности боссов по кругу: 10-я волна — щит, 20-я — призыв, 30-я — невосприимчивость и т.д.
const BOSS_ABILITIES := {
	"shield": {"name": "Панцирь", "desc": "Щит поглощает урон, пока его не пробить"},
	"summon": {"name": "Призыватель", "desc": "Четыре раза зовёт по трое быстрых прислужников"},
	"immune": {"name": "Зеркало", "desc": "Почти не боится урона того типа, которым ты бьёшь чаще всего"},
}
const BOSS_ABILITY_ORDER := ["shield", "summon", "immune"]
const SHIELD_SHARE := 0.45
const SUMMON_EVERY := 6.0
const SUMMON_COUNT := 3
const SUMMON_BATCHES := 4
const SUMMON_HP := 0.035
const SUMMON_SPEED := 1.4
const IMMUNE_MULT := 0.3

const TYPE_NAMES := {"physical": "физическому урону", "fire": "огню", "frost": "холоду", "poison": "яду", "shock": "молнии"}

## Особые волны — каждая пятая, кроме боссовых. Меняют состав роя, а не только его силу.
const SPECIAL_ORDER := ["swarm", "rush", "heavy"]
const SPECIAL_WAVES := {
	"swarm": {"name": "Нашествие", "desc": "Врагов на 70% больше, но они хрупкие", "hp": 0.6, "speed": 1.0, "count": 1.7},
	"rush": {"name": "Рывок", "desc": "Быстрые враги: на 45% быстрее, зато слабее", "hp": 0.8, "speed": 1.45, "count": 1.0},
	"heavy": {"name": "Бронеколонна", "desc": "Врагов меньше, но каждый крепче в 1.7 раза", "hp": 1.7, "speed": 0.9, "count": 0.6},
}
const SPECIAL_BONUS := 1.5


## Выключатели для балансных прогонов бота (tests/bot.gd --no-abilities / --no-specials).
static var abilities_on := true
static var specials_on := true


static func boss_ability(wave: int) -> String:
	if not abilities_on:
		return ""
	var i: int = maxi(0, wave / BOSS_EVERY - 1)
	return BOSS_ABILITY_ORDER[i % BOSS_ABILITY_ORDER.size()]


## Особая волна ("" — обычная).
static func special_for(wave: int) -> String:
	if not specials_on or wave < 5 or wave % 5 != 0 or wave % BOSS_EVERY == 0:
		return ""
	return SPECIAL_ORDER[(wave / 5 / 2) % SPECIAL_ORDER.size()]


## Сложность и режимы. Бонусы копятся в meta забега и сохраняются вместе с ним.
const DIFFICULTIES := {
	"easy": {"name": "Лёгкая", "desc": "+8 жизней, +40 золота, враги слабее на 15%, рой учится медленнее. Очков знаний ×0.75",
		"lives": 8, "gold": 40, "hp": 0.85, "adapt": 0.7, "points": 0.75},
	"normal": {"name": "Обычная", "desc": "Как задумано.",
		"lives": 0, "gold": 0, "hp": 1.0, "adapt": 1.0, "points": 1.0},
	"hard": {"name": "Тяжёлая", "desc": "−8 жизней, −30 золота, враги крепче на 20%, рой учится быстрее. Очков знаний ×1.5",
		"lives": -8, "gold": -30, "hp": 1.2, "adapt": 1.4, "points": 1.5},
}
const MODES := {
	"standard": {"name": "Поход", "desc": "30 волн. Победа открывает бесконечный режим."},
	"endless": {"name": "Бесконечный", "desc": "Без победы: держись как можно дольше. Волны растут без предела."},
	"daily": {"name": "Карта дня", "desc": "Одна карта для всех на сегодня, обычная сложность. Побей свой рекорд за день."},
}


static func difficulty(meta: Dictionary) -> Dictionary:
	return DIFFICULTIES.get(meta.get("difficulty", "normal"), DIFFICULTIES["normal"])


static func boss_hp_share(wave: int) -> float:
	return 0.3 + 0.06 * wave


static func boss_bonus(wave: int) -> int:
	return 60 + wave * 8


static func wave_size(wave: int) -> int:
	return 10 + int(floor(wave * 1.5))


static func lure_boost(gene: String) -> float:
	return float(LURE_BOOSTS.get(gene, LURE_BOOST))


static func vaccine_cost(wave: int) -> int:
	return VACCINE_BASE_COST + VACCINE_WAVE_COST * wave


static func wave_bonus(wave: int) -> int:
	return 10 + wave * 2


static func branch_def(kind: String, id: String) -> Dictionary:
	for b in BRANCHES.get(kind, []):
		if b["id"] == id:
			return b
	return {}


## Есть ли у башни эффект, для которого имеет смысл режим «Без эффекта».
static func has_status_effect(def: Dictionary) -> bool:
	return def["type"] in ["fire", "frost", "poison"] or def.get("slow", 0.0) > 0.0


## Параметры башни с учётом уровня и ветки.
static func tower_def(kind: String, level: int, branch: String) -> Dictionary:
	var d: Dictionary = TOWERS[kind].duplicate(true)
	if level >= 2:
		_apply_mods(d, LEVEL2)
	if level >= 3:
		_apply_mods(d, LEVEL3)
		var b := branch_def(kind, branch)
		if not b.is_empty():
			_apply_mods(d, b["mods"])
	d["level"] = level
	d["branch"] = branch
	return d


static func _apply_mods(d: Dictionary, m: Dictionary) -> void:
	for k in m:
		var v = m[k]
		match k:
			"damage", "cooldown":
				d[k] = d[k] * v
			"range":
				if d["range"] > 0.0:
					d["range"] += v
			"splash_add":
				d["splash"] = d.get("splash", 0.0) + v
			"aura_radius":
				if d.has("aura"):
					d["aura"]["radius"] += v
			"aura_rate":
				if d.has("aura"):
					d["aura"]["fireRate"] = v
			"scorch_bonus":
				d["scorch_bonus"] = d.get("scorch_bonus", 0.0) + v
			_:
				d[k] = v


static func perk_def(id: String) -> Dictionary:
	for p in PERKS:
		if p["id"] == id:
			return p
	return {}


static func targets_text(def: Dictionary) -> String:
	if def.has("aura"):
		return "поддержка"
	if def["ground"] and def["air"]:
		return "земля и воздух"
	if def["air"]:
		return "только воздух"
	return "только земля"


## Особенности башни для карточки: [{icon, text}]. Новая башня получает теги автоматически.
static func tower_tags(def: Dictionary) -> Array:
	var t: Array = []
	if def.get("splash", 0.0) > 0.0:
		t.append({"icon": "dmg-physical", "text": "Площадь"})
	if def.get("slow", 0.0) > 0.0:
		t.append({"icon": "st-frozen", "text": "Замедляет"})
	if def.has("pierce"):
		t.append({"icon": "gene-plated", "text": "Пробивает броню"})
	match def["type"]:
		"fire":
			t.append({"icon": "st-burn", "text": "Поджигает"})
		"poison":
			t.append({"icon": "st-poison", "text": "Яд"})
		"shock":
			t.append({"icon": "gene-plated", "text": "Сквозь броню"})
	if def.has("aura"):
		t.append({"icon": "gene-veil", "text": "Видит невидимок"})
		t.append({"icon": "perk-rapid", "text": "Ускоряет соседей"})
	if def.get("multishot", 1) > 1:
		t.append({"icon": "tower-arrow", "text": "%d цели" % def["multishot"]})
	if def.get("execute", 0.0) > 0.0:
		t.append({"icon": "boss", "text": "Добивает"})
	if def.get("chain", 1) > 1:
		t.append({"icon": "tower-tesla", "text": "Цепь ×%d" % def["chain"]})
	if def.get("plague", 0.0) > 0.0:
		t.append({"icon": "st-poison", "text": "Заражает"})
	return t


## Максимумы по всем башням: полоски в карточке считаются относительно них.
static func tower_stat_max() -> Dictionary:
	var m := {"damage": 1.0, "rate": 1.0, "range": 1.0}
	for k in TOWERS:
		var d: Dictionary = TOWERS[k]
		if d.has("aura"):
			continue
		m["damage"] = maxf(m["damage"], d["damage"])
		m["rate"] = maxf(m["rate"], 1.0 / d["cooldown"])
		m["range"] = maxf(m["range"], d["range"])
	return m
