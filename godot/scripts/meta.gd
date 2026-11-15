class_name TDMeta
extends RefCounted
## Мета-прогрессия между забегами: «очки знаний», постоянные улучшения «Мастерской», рекорды.
## Хранится в user://meta.cfg. Симуляция получает только словарь бонусов (bonuses()).

const PATH := "user://meta.cfg"

## За что дают очки знаний в конце забега.
const POINTS_PER_WAVE := 1
const POINTS_PER_BOSS := 5
const POINTS_VICTORY := 20

## Постоянные улучшения. cost[i] — цена уровня i+1.
const UPGRADES: Array[Dictionary] = [
	{"id": "treasury", "icon": "coin", "name": "Казна", "desc": "+15 золота на старте", "cost": [4, 8, 14, 22]},
	{"id": "walls", "icon": "lives", "name": "Стены", "desc": "+2 жизни на старте", "cost": [5, 10, 18]},
	{"id": "craft", "icon": "perk-rapid", "name": "Ремесло", "desc": "Улучшения башен на 8% дешевле", "cost": [6, 12, 20]},
	{"id": "supply", "icon": "perk-bulk", "name": "Поставки", "desc": "Дубли башен дорожают на 20% медленнее", "cost": [8, 16]},
	{"id": "scouting", "icon": "target", "name": "Разведка", "desc": "При выборе усиления — 4 варианта вместо 3", "cost": [15]},
	{"id": "legacy", "icon": "perk-variety", "name": "Наследие", "desc": "Забег начинается с выбора усиления", "cost": [20]},
]

static var points: int = 0
static var levels: Dictionary = {}
## seed карты -> лучшая волна.
static var records: Dictionary = {}
static var runs: int = 0
static var wins: int = 0
static var best_wave: int = 0
## id достижения -> true.
static var achievements: Dictionary = {}
static var _loaded := false
static var credited_runs: Dictionary = {}


static func load_meta() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	points = cf.get_value("meta", "points", 0)
	levels = cf.get_value("meta", "levels", {})
	records = cf.get_value("meta", "records", {})
	runs = cf.get_value("meta", "runs", 0)
	wins = cf.get_value("meta", "wins", 0)
	best_wave = cf.get_value("meta", "best_wave", 0)
	credited_runs = cf.get_value("meta", "credited_runs", {})
	achievements = cf.get_value("meta", "achievements", {})


static func save_meta() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "points", points)
	cf.set_value("meta", "levels", levels)
	cf.set_value("meta", "records", records)
	cf.set_value("meta", "runs", runs)
	cf.set_value("meta", "wins", wins)
	cf.set_value("meta", "best_wave", best_wave)
	cf.set_value("meta", "credited_runs", credited_runs)
	cf.set_value("meta", "achievements", achievements)
	cf.save(PATH)


static func level(id: String) -> int:
	return int(levels.get(id, 0))


static func upgrade_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return {}


## Цена следующего уровня (-1 — максимум).
static func next_cost(id: String) -> int:
	var u := upgrade_def(id)
	var lv := level(id)
	if u.is_empty() or lv >= u["cost"].size():
		return -1
	return int(u["cost"][lv])


static func buy(id: String) -> bool:
	var c := next_cost(id)
	if c < 0 or points < c:
		return false
	points -= c
	levels[id] = level(id) + 1
	save_meta()
	return true


## Бонусы для нового забега (их понимает TDGame).
static func bonuses() -> Dictionary:
	return {
		"gold": 15 * level("treasury"),
		"lives": 2 * level("walls"),
		"upgrade_disc": 0.08 * level("craft"),
		"growth_cut": 0.2 * level("supply"),
		"perk_choices": level("scouting"),
		"start_perk": level("legacy") > 0,
	}


## Сколько очков даст забег, с разбивкой для экрана итогов.
static func award_for(waves: int, bosses: int, victory: bool) -> Dictionary:
	var parts: Array = []
	var total := 0
	if waves > 0:
		parts.append(["Пережито волн: %d" % waves, waves * POINTS_PER_WAVE])
		total += waves * POINTS_PER_WAVE
	if bosses > 0:
		parts.append(["Побеждено боссов: %d" % bosses, bosses * POINTS_PER_BOSS])
		total += bosses * POINTS_PER_BOSS
	if victory:
		parts.append(["Победа", POINTS_VICTORY])
		total += POINTS_VICTORY
	return {"total": total, "parts": parts}


## ── Достижения и открытия ────────────────────────────────────

## cond проверяется по ходу забега (см. evaluate). reward — очки знаний.
const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "survive10", "icon": "target", "name": "Первый рубеж", "desc": "Пережить 10 волн", "reward": 3, "unlock": "Открывает башню «Сеть»"},
	{"id": "boss1", "icon": "boss", "name": "Охотник на боссов", "desc": "Победить босса", "reward": 3, "unlock": "Открывает башню «Тесла»"},
	{"id": "variety6", "icon": "perk-variety", "name": "Арсенал", "desc": "Держать 6 разных башен одновременно", "reward": 3, "unlock": ""},
	{"id": "rich", "icon": "coin", "name": "Золотая лихорадка", "desc": "Накопить 1000 золота", "reward": 3, "unlock": ""},
	{"id": "citadels", "icon": "castle", "name": "Цитадели", "desc": "Иметь 3 башни 3-го уровня", "reward": 4, "unlock": ""},
	{"id": "daily10", "icon": "dice", "name": "Задание дня", "desc": "Пережить 10 волн на карте дня", "reward": 4, "unlock": ""},
	{"id": "survive20", "icon": "wave", "name": "Закалка", "desc": "Пережить 20 волн", "reward": 5, "unlock": ""},
	{"id": "flawless", "icon": "gene-plated", "name": "Без потерь", "desc": "Пережить 10 волн, не пропустив ни одного врага", "reward": 5, "unlock": ""},
	{"id": "boss3", "icon": "boss", "name": "Тройной удар", "desc": "Победить трёх боссов за один забег", "reward": 6, "unlock": ""},
	{"id": "hard15", "icon": "lives", "name": "Испытание", "desc": "Пережить 15 волн на тяжёлой сложности", "reward": 8, "unlock": ""},
	{"id": "victory", "icon": "play", "name": "Рой остановлен", "desc": "Победить на 30-й волне", "reward": 10, "unlock": "Открывает бесконечный режим"},
	{"id": "endless40", "icon": "portal", "name": "Бесконечность", "desc": "Дойти до 40-й волны в бесконечном режиме", "reward": 10, "unlock": ""},
	{"id": "hard_win", "icon": "perk-bounty", "name": "Закалённый", "desc": "Победить на тяжёлой сложности", "reward": 15, "unlock": ""},
]

## Башни, закрытые до достижения: kind -> id достижения.
const TOWER_UNLOCK := {"tesla": "boss1", "net": "survive10"}
## С какой лучшей волны открываются биомы (лес и осень — сразу).
const BIOME_UNLOCK := {"forest": 0, "autumn": 0, "winter": 10, "swamp": 15, "volcanic": 20, "dungeon": 25}
const HARD_UNLOCK_WAVE := 15


static func achievement_def(id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a["id"] == id:
			return a
	return {}


static func has_achievement(id: String) -> bool:
	return achievements.get(id, false)


static func locked_towers() -> Array:
	var out: Array = []
	for kind in TOWER_UNLOCK:
		if not has_achievement(TOWER_UNLOCK[kind]):
			out.append(kind)
	return out


static func biome_unlocked(biome_id: String) -> bool:
	return best_wave >= int(BIOME_UNLOCK.get(biome_id, 0))


static func difficulty_unlocked(id: String) -> bool:
	return id != "hard" or best_wave >= HARD_UNLOCK_WAVE


static func mode_unlocked(id: String) -> bool:
	return id != "endless" or wins >= 1 or has_achievement("victory")


static func unlock_hint(kind: String, id: String) -> String:
	if kind == "difficulty" and id == "hard":
		return "Откроется после %d-й волны" % HARD_UNLOCK_WAVE
	if kind == "mode" and id == "endless":
		return "Откроется после первой победы"
	return ""


## Одна карта на всех на сегодня.
static func daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])


## Проверяет достижения по состоянию забега, выдаёт награды. Возвращает вновь полученные.
static func evaluate(game: TDGame) -> Array:
	var survived: int = game.wave - 1
	var citadels := 0
	for t in game.towers:
		if t.level >= 3:
			citadels += 1
	var diff := game.difficulty_id()
	var mode := game.mode_id()
	var state := {
		"survive10": survived >= 10,
		"boss1": game.bosses_killed >= 1,
		"variety6": game.kinds_owned() >= 6,
		"rich": game.gold >= 1000,
		"citadels": citadels >= 3,
		"daily10": mode == "daily" and survived >= 10,
		"survive20": survived >= 20,
		"flawless": survived >= 10 and game.run_leaked == 0,
		"boss3": game.bosses_killed >= 3,
		"hard15": diff == "hard" and survived >= 15,
		"victory": game.victory,
		"endless40": mode == "endless" and survived >= 40,
		"hard_win": diff == "hard" and game.victory,
	}
	var fresh: Array = []
	for a in ACHIEVEMENTS:
		if state.get(a["id"], false) and not has_achievement(a["id"]):
			achievements[a["id"]] = true
			points += int(a["reward"])
			fresh.append(a)
	if not fresh.is_empty():
		save_meta()
	return fresh


static func record_for(seed_v: int) -> int:
	return int(records.get(str(seed_v), 0))


## Запомнить результат: рекорд карты, лучший результат, счётчики.
static func note_run(seed_v: int, wave: int, victory: bool, finished: bool) -> bool:
	var key := str(seed_v)
	var new_record := wave > int(records.get(key, 0))
	if new_record:
		records[key] = wave
	best_wave = maxi(best_wave, wave)
	if finished:
		runs += 1
	if victory:
		wins += 1
	return new_record


## Older saves of the same run cannot award the same meta progress twice.
static func claim_run(id: String, seed_v: int, waves: int, bosses: int, victory: bool, final: bool, mult: float = 1.0) -> Dictionary:
	var old: Dictionary = credited_runs.get(id, {"waves": 0, "bosses": 0, "victory": false, "final": false})
	var award := award_for(maxi(0, waves - int(old["waves"])), maxi(0, bosses - int(old["bosses"])), victory and not old["victory"])
	award["total"] = int(round(award["total"] * mult))
	points += award["total"]
	var record := note_run(seed_v, waves, victory and not old["victory"], final and not old["final"])
	credited_runs[id] = {"waves": maxi(waves, old["waves"]), "bosses": maxi(bosses, old["bosses"]), "victory": victory or old["victory"], "final": final or old["final"]}
	return {"total": award["total"], "record": record}
