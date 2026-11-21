extends SceneTree
## PRO-151: диагностический баланс-харнесс. Боевую логику не меняет: бот играет через публичное API TDGame,
## а метрики снимаются чтением состояния между шагами симуляции.
##
## Запуск (из папки godot):
##   Godot --headless --path . --script res://tests/balance_audit.gd -- --strategy=owner --difficulty=normal \
##     --family=snake --seeds=10 [--seed-from=0] [--workshop=1] [--waves=30] [--cap=45] [--swarm=no_press] \
##     [--branch=a|b] [--no-upgrades] [--ablate=frost] [--perks=random] [--out=file.jsonl]
## Каждая партия — одна строка JSON (summary + метрики по волнам). Без --out печатает краткую строку на партию.
## PRO-152 (без этих ключей вывод побайтово прежний):
##   --model=signature|observe — флаг эксперимента TDStrains (observe: сигнатура считается, состав волн не меняется — контрольное плечо);
##   --counter=auto [--counter-at=W] — бот читает предупреждения роя и с волны W строит ответ на объявленный пакет;
##   --record=file.json / --replay=file.json — записать журнал покупок партии / воспроизвести его с неограниченным золотом
##   («замороженная политика»: различие между плечами — только модель роя).
## Сиды: (seed_from + i + 1) * 4243, как у tests/bot.gd, но карта строится с принудительным семейством.

const DT := 1.0 / 30.0
const PERK_PRIORITY: Array[String] = ["rapid", "range", "pierce", "shatter", "scorch", "variety", "bounty", "bulk", "wildfire", "lives", "coldshell"]
## Ветки по умолчанию: выбраны по результатам tests/tower_lab.gd (сильнейшая ветка на равный бюджет, см. docs/balance).
const DEFAULT_BRANCH := {"arrow": "a", "cannon": "b", "ember": "b", "frost": "a", "sniper": "b", "poison": "b",
	"flak": "b", "tesla": "a", "net": "a", "beacon": "b"}

## Стратегии. core — веса основных башен (строятся без предела в пропорции весов);
## support — [башня, минимум основных башен, сколько держать, с какой волны]; react — реагировать на состав следующей волны.
const STRATEGIES := {
	"arrow": {"core": {"arrow": 1.0}},
	"sniper": {"core": {"sniper": 1.0}},
	"arrow_sniper": {"core": {"arrow": 1.0, "sniper": 1.0}},
	"arrow_frost_ember": {"core": {"arrow": 2.0, "frost": 1.0, "ember": 1.0}},
	## Стратегия владельца по плейтесту 15.11.2026: основа лучники+снайперы, 1–2 огня, 1–2 льда, 2 яда, 1 Тесла, 1 Маяк.
	"owner": {"core": {"arrow": 1.0, "sniper": 1.0}, "react": "stealth", "support": [
		["frost", 2, 1, 1], ["ember", 3, 1, 1], ["poison", 5, 1, 4], ["beacon", 6, 1, 1], ["frost", 7, 2, 1],
		["ember", 8, 2, 1], ["poison", 8, 2, 1], ["tesla", 9, 1, 1]]},
	## Разумная смешанная оборона: пушки, зенитки и сеть в составе.
	"mixed": {"core": {"arrow": 1.0, "sniper": 0.7, "cannon": 0.7}, "react": "stealth", "support": [
		["frost", 2, 1, 1], ["ember", 3, 1, 1], ["flak", 4, 1, 6], ["poison", 5, 1, 4], ["net", 6, 1, 6], ["beacon", 6, 1, 1],
		["frost", 7, 2, 1], ["ember", 8, 2, 1], ["flak", 8, 2, 8], ["tesla", 9, 1, 1]]},
	## Смена обороны: до волны switch_at — стратегия владельца (почти весь урон физический),
	## затем всё физическое продаётся и строится огонь/яд/Тесла/лёд — меряем, как быстро рой «забывает» броню.
	"switch": {"core": {"arrow": 1.0, "sniper": 1.0}, "react": "stealth", "support": [
		["frost", 2, 1, 1], ["ember", 3, 1, 1], ["poison", 5, 1, 4], ["beacon", 6, 1, 1], ["frost", 7, 2, 1]],
		"switch_at": 13, "after": {"core": {"ember": 1.0, "poison": 1.0, "tesla": 1.0}, "react": "stealth", "support": [["frost", 0, 3, 1], ["beacon", 0, 1, 1]]}},
	## PRO-192: поздняя сборка владельца из победы на Hard 17.11.2026: основа снайперы + пушки (ветка «Мортира»),
	## немного лучников, огонь, яд, лёд и Маяк. Ветки: пушка — a («Мортира»), остальные — по умолчанию.
	"owner2": {"core": {"sniper": 1.0, "cannon": 1.0, "arrow": 0.4}, "react": "stealth", "branches": {"cannon": "a"}, "support": [
		["ember", 2, 1, 1], ["frost", 3, 1, 1], ["poison", 5, 1, 4], ["beacon", 6, 1, 1], ["ember", 8, 2, 1],
		["poison", 9, 2, 1], ["flak", 10, 1, 8], ["frost", 12, 2, 1]]},
	## PRO-152: оборона без ПВО (только пушки + Маяк по невидимкам) — проверка «Стаи», которую остальные стратегии не вызывают.
	"cannon": {"core": {"cannon": 1.0}, "react": "stealth"},
	## Владелец + реакция на состав следующей волны (невидимки, летающие, броня, лечение, деление, стойкости).
	"adaptive": {"core": {"arrow": 1.0, "sniper": 1.0}, "react": "full", "support": [
		["frost", 2, 1, 1], ["ember", 3, 1, 1], ["poison", 5, 1, 4], ["beacon", 6, 1, 1], ["frost", 7, 2, 1],
		["ember", 8, 2, 1], ["tesla", 9, 1, 1]]},
}

var strategy_id := "owner"
var difficulty := "normal"
var family := ""
var seeds := 10
var seed_from := 0
var workshop := false
var max_wave := 30
## До какой волны играть дальше 30-й, чтобы измерить запас прочности (0 — только max_wave).
var cap := 0
var swarm := ""
var branch_override := ""
var upgrades := true
var ablate := ""
var perk_mode := "smart"
var out_path := ""
## Микроконтроль режима прицела на боссовых волнах (--micro=0 — выключить).
var micro := true
## PRO-152
var model := ""
var counter := ""
var counter_at := 1
var record_path := ""
var replay_path := ""
var _record := {}
var _replay := {}
## PRO-192: фазовые метрики поздней игры (--late=1). Без ключа вывод побайтово прежний.
var late_metrics := false
## Ответы бота на пакеты роя: что строить (сколько держать), когда пакет объявлен или уже в волне.
const COUNTER_PLAN := {"brood": [["cannon", 2], ["tesla", 1]], "hulk": [["cannon", 2], ["poison", 3]], "flock": [["flak", 2]]}

var strat: Dictionary = {}
var branches: Dictionary = {}
var branch_set: Dictionary = {}
## PRO-213, только для диагностики: заменить шаблон распределения врагов по дорогам развилки (например 0 — все по одной).
var route_plan_override: Array[int] = []
## PRO-141: карта с двумя порталами (--family=portal_a). --portal-open/-announce/-share — расписание второго портала
## (контроль «один активный портал» на той же геометрии: --portal-open=999 --portal-announce=999). --portal-policy — когда бот
## начинает строить под второй вход: announce (после предупреждения; по умолчанию), blind (только когда портал открыт и
## пошли враги — независимая реактивная политика), early (с первой волны, как на развилке).
var portal_open := 18
var portal_announce := 15
var portal_share := 50
var portal_policy := "announce"
var spent_build := 0
var spent_upgrade := 0
var cells_by_kind: Dictionary = {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--strategy="):
			strategy_id = a.substr(11)
		elif a.begins_with("--difficulty="):
			difficulty = a.substr(13)
		elif a.begins_with("--family="):
			family = a.substr(9)
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed-from="):
			seed_from = int(a.substr(12))
		elif a.begins_with("--workshop="):
			workshop = a.substr(11) == "1"
		elif a.begins_with("--waves="):
			max_wave = int(a.substr(8))
		elif a.begins_with("--cap="):
			cap = int(a.substr(6))
		elif a.begins_with("--swarm="):
			swarm = a.substr(8)
		elif a.begins_with("--branch="):
			branch_override = a.substr(9)
		elif a == "--no-upgrades":
			upgrades = false
		elif a.begins_with("--ablate="):
			ablate = a.substr(9)
		elif a.begins_with("--perks="):
			perk_mode = a.substr(8)
		elif a.begins_with("--micro="):
			micro = a.substr(8) != "0"
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--model="):
			model = a.substr(8)
		elif a.begins_with("--counter="):
			counter = a.substr(10)
		elif a.begins_with("--counter-at="):
			counter_at = int(a.substr(13))
		elif a.begins_with("--record="):
			record_path = a.substr(9)
		elif a.begins_with("--portal-open="):
			portal_open = int(a.substr(14))
		elif a.begins_with("--portal-announce="):
			portal_announce = int(a.substr(18))
		elif a.begins_with("--portal-share="):
			portal_share = int(a.substr(15))
		elif a.begins_with("--portal-policy="):
			portal_policy = a.substr(16)
		elif a.begins_with("--route-plan="):
			for k in a.substr(13).split(",", false):
				route_plan_override.append(int(k))
		elif a.begins_with("--range-variant="):
			TDConfig.range_variant = a.substr(16)
		elif a.begins_with("--branch-set="):
			# PRO-212: ветки отдельных башен, например --branch-set=sniper:a,cannon:b
			for kv in a.substr(13).split(",", false):
				var p := String(kv).split(":")
				if p.size() == 2:
					branch_set[p[0]] = p[1]
		elif a.begins_with("--late-variant="):
			TDConfig.late_variant = a.substr(15)
		elif a.begins_with("--late="):
			late_metrics = a.substr(7) == "1"
		elif a.begins_with("--replay="):
			replay_path = a.substr(9)
		elif a.begins_with("--lab-strain="):
			# лаборатория: --lab-strain=пакет[:доля[:с волны]] — принудительно разметить волны (только с --model=signature)
			var lab := a.substr(13).split(":")
			TDStrains.lab_strain = lab[0]
			TDStrains.lab_share = float(lab[1]) if lab.size() > 1 else 1.0
			TDStrains.lab_from = int(lab[2]) if lab.size() > 2 else 6
	if not STRATEGIES.has(strategy_id):
		push_error("unknown strategy " + strategy_id)
		quit(1)
		return
	strat = _ablated(STRATEGIES[strategy_id].duplicate(true))
	branches = DEFAULT_BRANCH.duplicate()
	branches.merge(strat.get("branches", {}), true)
	if branch_override in ["a", "b"]:
		for k in branches:
			branches[k] = branch_override
	branches.merge(branch_set, true)
	TDConfig.track_zones = late_metrics
	TDGenome.diag_evolution = swarm
	if replay_path != "":
		_replay = JSON.parse_string(FileAccess.get_file_as_string(replay_path))
	var f: FileAccess = null
	if out_path != "":
		f = FileAccess.open(out_path, FileAccess.WRITE)
	for i in seeds:
		var seed_v: int = (seed_from + i + 1) * 4243
		var res := _play(seed_v)
		if f != null:
			f.store_line(JSON.stringify(res))
		else:
			var s: Dictionary = res["summary"]
			print("%s seed=%d fam=%s end=%d leaks30=%d lives30=%d minlives=%d" % [strategy_id, seed_v, res["family"], s["end_wave"], s["leaks_by_30"], s["lives_at_30"], s["min_lives"]])
	if f != null:
		f.close()
	if record_path != "":
		var rf := FileAccess.open(record_path, FileAccess.WRITE)
		rf.store_string(JSON.stringify(_record))
		rf.close()
	quit()


## Абляция: убрать тип башни из стратегии, чтобы измерить её предельную ценность.
func _ablated(s: Dictionary) -> Dictionary:
	if ablate == "":
		return s
	var core: Dictionary = s.get("core", {})
	core.erase(ablate)
	if core.is_empty():
		core["arrow"] = 1.0
	s["core"] = core
	var sup: Array = []
	for e in s.get("support", []):
		if e[0] != ablate:
			sup.append(e)
	s["support"] = sup
	return s


func _meta() -> Dictionary:
	var m := {"difficulty": difficulty, "mode": "standard"}
	if model != "":
		m["swarm_model"] = model
	if workshop:
		# Мастерская на максимуме (TDMeta.bonuses() при всех уровнях).
		m.merge({"gold": 60, "lives": 6, "upgrade_disc": 0.24, "growth_cut": 0.4, "perk_choices": 1, "start_perk": true})
	return m


# ── Расстановка ──────────────────────────────────────────────────

## PRO-213: длина наземной дороги в радиусе r от точки c. На карте с развилкой — по всем дорогам с весом их доли врагов
## (а не только по основной); на карте с одним путём — прежний расчёт, те же числа.
func _ground_len(g: TDGame, c: Vector2, r: float) -> float:
	var v := 0.0
	if not g.map.is_multi():
		for s in 120:
			if g.map.pos_at((s + 0.5) / 120.0 * g.map.length).distance_to(c) <= r:
				v += g.map.length / 120.0
		return v
	for rt in g.map.routes:
		var w := _route_weight(g, rt.id)
		for s in 120:
			if rt.pos_at((s + 0.5) / 120.0 * rt.length).distance_to(c) <= r:
				v += w * rt.length / 120.0
	return v


## Вес дороги при оценке клеток. Развилка и карта с одним входом — установившаяся доля. Два портала (PRO-141): по политике
## бота — announce: второй вход учитывается с волны предупреждения, blind: только с волны открытия, early: всегда.
func _route_weight(g: TDGame, rid: int) -> float:
	if not g.map.portal2:
		return TDAdvisor.route_share(g.map, rid)
	var first := 1.0 if rid == 0 else 0.0
	match portal_policy:
		"early":
			return g.map.share_at(rid)
		"blind":
			return g.map.share_at(rid) if g.wave >= g.map.portal_open else first
	return g.map.share_at(rid) if g.wave >= g.map.portal_announce else first


## Длина прямой полёта в радиусе r от точки c; два портала — по прямой каждого входа с весом его доли.
func _air_len(g: TDGame, c: Vector2, r: float) -> float:
	var v := 0.0
	if not g.map.portal2:
		for s in 60:
			if g.map.fly_pos_at((s + 0.5) / 60.0 * g.map.fly_length).distance_to(c) <= r:
				v += g.map.fly_length / 60.0
		return v
	for rt in g.map.routes:
		var w := _route_weight(g, rt.id)
		for s in 60:
			if rt.fly_pos_at((s + 0.5) / 60.0 * rt.fly_length).distance_to(c) <= r:
				v += w * rt.fly_length / 60.0
	return v


## Расписание второго портала меняет веса в волны предупреждения и открытия: кэш клеток пересчитывается.
func _refresh_weights(g: TDGame) -> void:
	if g.map.portal2 and (g.wave == g.map.portal_announce or g.wave == g.map.portal_open):
		cells_by_kind = {}
		_cover_cache = {}


## Клетки для типа башни по убыванию длины дороги в радиусе (воздух — по прямой вход→выход).
func _cells_for(g: TDGame, kind: String) -> Array:
	if cells_by_kind.has(kind):
		return cells_by_kind[kind]
	var def: Dictionary = TDConfig.TOWERS[kind]
	var r: float = def["range"]
	var cells: Array = []
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if g.map.is_path(x, y) or g.map.is_blocked(x, y):
				continue
			var c := Vector2(x + 0.5, y + 0.5)
			var score := 0.0
			if def["ground"]:
				score += _ground_len(g, c, r)
			if def["air"]:
				var w: float = 1.0 if not def["ground"] else 0.35
				if g.map.portal2:
					score += w * _air_len(g, c, r)
				else:
					for s in 60:
						if g.map.fly_pos_at((s + 0.5) / 60.0 * g.map.fly_length).distance_to(c) <= r:
							score += w * g.map.fly_length / 60.0
			cells.append({"x": x, "y": y, "score": score})
	cells.sort_custom(func(a, b): return a["score"] > b["score"])
	cells_by_kind[kind] = cells
	return cells


## Маяк — туда, где больше всего уже вложенного в стреляющие башни в радиусе ауры.
func _beacon_cell(g: TDGame) -> Dictionary:
	var rad: float = TDConfig.TOWERS["beacon"]["aura"]["radius"]
	var best := {}
	var best_v := -1.0
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if g.map.is_path(x, y) or g.map.is_blocked(x, y) or g.tower_at(x, y) != null:
				continue
			var v := 0.0
			for t in g.towers:
				if not t.def.has("aura") and Vector2(t.x, t.y).distance_to(Vector2(x, y)) <= rad:
					v += t.spent
			if v > best_v:
				best_v = v
				best = {"x": x, "y": y}
	return best


func _spot(g: TDGame, kind: String) -> Dictionary:
	if kind == "beacon":
		return _beacon_cell(g)
	for c in _cells_for(g, kind):
		if g.tower_at(c["x"], c["y"]) == null:
			return c
	return {}


# ── Решения бота ────────────────────────────────────────────────

func _core_count(g: TDGame) -> int:
	var n := 0
	for k in strat["core"]:
		n += g.count_of(k)
	return n


## Реакция на состав следующей волны. "stealth" — только Маяк против невидимок (это делает любой человек);
## "full" — ещё зенитки, пушки, яд по составу волны.
func _reactive_need(g: TDGame) -> String:
	var mode: String = strat.get("react", "")
	if mode == "":
		return ""
	var info := TDAdvisor.wave_info(g)
	var n: float = maxf(1.0, float(info["n"]))
	if info["stealth"] > 0 and g.count_of("beacon") < (2 if mode == "full" else 1):
		return "beacon"
	if mode != "full":
		return ""
	if float(info["fliers"]) / n >= 0.15 and g.count_of("flak") < 1 + int(g.wave / 8):
		return "flak"
	if info.get("split", 0) > 1 and g.count_of("cannon") < 2:
		return "cannon"
	if info["regen"] * 100.0 >= 0.8 and g.count_of("poison") < 2:
		return "poison"
	if info["avg"]["armor"] >= 2.5 and g.count_of("cannon") < 1 + int(g.wave / 10):
		return "cannon"
	return ""


## PRO-152: ответ на объявленный или идущий пакет роя по предупреждению (как сделал бы игрок, прочитавший отчёт).
func _counter_need(g: TDGame) -> String:
	if counter != "auto" or g.wave < counter_at:
		return ""
	for e in TDStrains.forecast(g):
		if String(e["phase"]) not in ["announced", "active"]:
			continue
		for need in COUNTER_PLAN[e["id"]]:
			if not g.is_locked(need[0]) and g.count_of(need[0]) < int(need[1]):
				return need[0]
	return ""


## Обязательная постройка (реакция или опорная башня по плану) — "" если нет.
func _forced_build(g: TDGame) -> String:
	var cn := _counter_need(g)
	if cn != "":
		return cn
	var need := _reactive_need(g)
	if need == ablate:
		need = "" # абляция убирает тип и из реакций
	if need != "":
		return need
	var core_n := _core_count(g)
	for e in strat.get("support", []):
		if core_n >= int(e[1]) and g.count_of(e[0]) < int(e[2]) and g.wave >= int(e[3]):
			return e[0]
	return ""


## Основная башня, которой меньше всего относительно веса в стратегии.
func _core_pick(g: TDGame) -> String:
	var best := ""
	var best_v := INF
	var avg: Dictionary = TDAdvisor.wave_info(g)["avg"]
	for k in strat["core"]:
		var w: float = strat["core"][k]
		if strat.get("react", "") == "full":
			if k == "frost" and avg["frostRes"] >= 0.4:
				w *= 0.3
			if k == "ember" and avg["fireRes"] >= 0.4:
				w *= 0.3
		var v: float = (g.count_of(k) + 1.0) / w
		if v < best_v or (v == best_v and g.tower_cost(k) < g.tower_cost(best)):
			best_v = v
			best = k
	return best


## Длина дороги (и прямой полёта с весом доли летающих) в радиусе r от клетки.
var _cover_cache := {}
func _cover(g: TDGame, x: int, y: int, def: Dictionary, fly_frac: float) -> float:
	var r: float = g._range_with_perks(def["range"])
	var key := "%d,%d,%.2f" % [x, y, r]
	var gc: Array
	if _cover_cache.has(key):
		gc = _cover_cache[key]
	else:
		var c := Vector2(x + 0.5, y + 0.5)
		var gl := _ground_len(g, c, r)
		var al := 0.0
		if g.map.portal2:
			al = _air_len(g, c, r)
		else:
			for s in 60:
				if g.map.fly_pos_at((s + 0.5) / 60.0 * g.map.fly_length).distance_to(c) <= r:
					al += g.map.fly_length / 60.0
		gc = [gl, al]
		_cover_cache[key] = gc
	var v := 0.0
	if def["ground"]:
		v += float(gc[0]) * (1.0 - fly_frac)
	if def["air"]:
		v += float(gc[1]) * fly_frac / TDConfig.FLYER_SPEED
	return v


## Грубая оценка урона в секунду по средней цели следующей волны (для решений бота, не для отчётов).
func _est_dps(g: TDGame, def: Dictionary, avg: Dictionary) -> float:
	if def.has("aura"):
		return 0.0
	var dmg: float = def["damage"] * g._variety_mult()
	var per: float = TDGame.effective_damage(dmg, def["type"], avg, {}, g.mods(), def.get("pierce", 0.0))
	per *= float(def.get("multishot", 1))
	per *= 1.0 + 1.5 * float(def.get("splash", 0.0))
	var chain: int = int(def.get("chain", 1))
	if chain > 1:
		per *= 1.0 + 0.6 * (chain - 1) * TDConfig.CHAIN_FALLOFF
	var cd: float = def["cooldown"] * pow(0.9, g.perk_level("rapid"))
	var dps: float = per / cd
	if def["type"] == "poison":
		dps += TDConfig.POISON_DPS * (dmg / TDConfig.TOWERS[def["kind"]]["damage"]) * def.get("poison_mult", 1.0)
	if def.get("execute", 0.0) > 0.0:
		dps *= 1.15
	return dps


func _fly_frac(g: TDGame) -> float:
	var info := TDAdvisor.wave_info(g)
	return float(info["fliers"]) / maxf(1.0, float(info["n"]))


## Польза постройки: урон за проход средней цели на монету.
func _build_value(g: TDGame, kind: String, spot: Dictionary, avg: Dictionary, ff: float) -> float:
	var def: Dictionary = TDConfig.tower_def(kind, 1, "")
	return _est_dps(g, def, avg) * _cover(g, spot["x"], spot["y"], def, ff) / float(g.tower_cost(kind))


## Лучшее улучшение по приросту урона за проход на монету. Маяк — по ускорению соседей.
func _best_upgrade(g: TDGame, avg: Dictionary, ff: float) -> Array:
	var best: TDGame.Tower = null
	var best_v := -1.0
	for t in g.towers:
		var cost := g.upgrade_cost(t)
		if cost < 0:
			continue
		var nxt: Dictionary = TDConfig.tower_def(t.kind, t.level + 1, String(branches.get(t.kind, "a")))
		var v := 0.0
		if t.def.has("aura"):
			var gain: float = (nxt["aura"]["fireRate"] - t.def["aura"]["fireRate"])
			for o in g.towers:
				if not o.def.has("aura") and Vector2(o.x, o.y).distance_to(Vector2(t.x, t.y)) <= nxt["aura"]["radius"]:
					v += _est_dps(g, o.def, avg) * _cover(g, o.x, o.y, o.def, ff) * maxf(gain, 0.05)
		else:
			v = _est_dps(g, nxt, avg) * _cover(g, t.x, t.y, nxt, ff) - _est_dps(g, t.def, avg) * _cover(g, t.x, t.y, t.def, ff)
		v /= float(cost)
		if v > best_v:
			best_v = v
			best = t
	return [best, best_v]


func _build_phase(g: TDGame) -> void:
	_refresh_weights(g)
	for _guard in 200:
		var forced := _forced_build(g)
		if forced != "":
			var fs := _spot(g, forced)
			if not fs.is_empty():
				if not g.can_place(forced, fs["x"], fs["y"]):
					# копим на обязательную башню, но не ценой утечек
					if _comfortable(g) or not _buy_affordable(g, TDAdvisor.wave_info(g)["avg"], _fly_frac(g)):
						return
					continue
				var fc := g.tower_cost(forced)
				g.place_tower(forced, fs["x"], fs["y"])
				spent_build += fc
				continue
		var avg: Dictionary = TDAdvisor.wave_info(g)["avg"]
		var ff := _fly_frac(g)
		var kind := _core_pick(g)
		var spot := _spot(g, kind)
		var bv: float = _build_value(g, kind, spot, avg, ff) if not spot.is_empty() else -1.0
		var up: TDGame.Tower = null
		var uv := -1.0
		if upgrades:
			var bu := _best_upgrade(g, avg, ff)
			up = bu[0]
			uv = bu[1]
		if up != null and uv >= bv:
			if not g.can_upgrade(up):
				if _comfortable(g):
					return # копим на улучшение: прошлую волну держали с запасом
				# не копим, если прошлая волна дошла далеко: берём лучшее из доступного
				if _buy_affordable(g, avg, ff):
					continue
				return
			var c := g.upgrade_cost(up)
			if g.upgrade_tower(up, String(branches.get(up.kind, "a"))):
				spent_upgrade += c
				continue
			return
		if spot.is_empty():
			return
		var cost := g.tower_cost(kind)
		if not g.can_place(kind, spot["x"], spot["y"]):
			if g.towers.is_empty():
				# на тяжёлой стартового золота может не хватить даже на одну основную башню (снайпер 100 > 80): открываемся лучником
				var a := _spot(g, "arrow")
				if not a.is_empty() and g.place_tower("arrow", a["x"], a["y"]):
					spent_build += g.tower_at(a["x"], a["y"]).spent
					continue
				return
			if _comfortable(g) or not _buy_affordable(g, avg, ff):
				return
			continue
		if not g.place_tower(kind, spot["x"], spot["y"]):
			return
		spent_build += cost


## Сценарий switch: продать физические башни и перейти на вторую стратегию.
func _switch(g: TDGame) -> void:
	var after: Dictionary = strat["after"]
	strat = after.duplicate(true)
	for t in g.towers.duplicate():
		if t.def["type"] == "physical" and not t.def.has("aura"):
			g.sell_tower(t.x, t.y)
	cells_by_kind = {}


## Прошлая волна прошла с запасом: без утечек и 90% убитых не дошли до середины пути.
func _comfortable(g: TDGame) -> bool:
	if g.reports.is_empty():
		return false
	var r: Dictionary = g.reports[g.reports.size() - 1]
	if int(r["leaked"]) > 0:
		return false
	var prog: Array = []
	for f in g.finished:
		prog.append(float(f["fitness"]))
	return _pct(prog, 0.9) < 0.5


## Под давлением не копим: покупаем лучшее по пользе на монету из того, на что хватает (основные башни или улучшения).
func _buy_affordable(g: TDGame, avg: Dictionary, ff: float) -> bool:
	var best_t: TDGame.Tower = null
	var best_kind := ""
	var best_spot := {}
	var best_v := 0.0
	for t in g.towers:
		if not g.can_upgrade(t) or t.def.has("aura"):
			continue
		var nxt: Dictionary = TDConfig.tower_def(t.kind, t.level + 1, String(branches.get(t.kind, "a")))
		var v: float = (_est_dps(g, nxt, avg) * _cover(g, t.x, t.y, nxt, ff) - _est_dps(g, t.def, avg) * _cover(g, t.x, t.y, t.def, ff)) / float(g.upgrade_cost(t))
		if v > best_v:
			best_v = v
			best_t = t
	for k in strat["core"]:
		var sp := _spot(g, k)
		if sp.is_empty() or not g.can_place(k, sp["x"], sp["y"]):
			continue
		var v2 := _build_value(g, k, sp, avg, ff)
		if v2 > best_v:
			best_v = v2
			best_t = null
			best_kind = k
			best_spot = sp
	if best_kind != "":
		var c := g.tower_cost(best_kind)
		if g.place_tower(best_kind, best_spot["x"], best_spot["y"]):
			spent_build += c
			return true
		return false
	if best_t != null:
		var c2 := g.upgrade_cost(best_t)
		if g.upgrade_tower(best_t, String(branches.get(best_t.kind, "a"))):
			spent_upgrade += c2
			return true
	return false


func _pick_perk(g: TDGame, rng: TDRng) -> void:
	if g.offer.is_empty():
		return
	if perk_mode == "random":
		g.choose_perk(g.offer[int(floor(rng.next() * g.offer.size()))])
		return
	for p in PERK_PRIORITY:
		if g.offer.has(p):
			g.choose_perk(p)
			return
	g.choose_perk(g.offer[0])


# ── Метрики ─────────────────────────────────────────────────────

static func _pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return -1.0
	var s := arr.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(q * s.size())))])


static func _mean(arr: Array) -> float:
	if arr.is_empty():
		return -1.0
	var t := 0.0
	for v in arr:
		t += float(v)
	return t / arr.size()


static func _r(v: float, d: int = 3) -> float:
	var m := pow(10.0, d)
	return round(v * m) / m


## Стреляющая башня может прямо сейчас бить врага (тип цели, видимость, радиус).
func _exposed(g: TDGame, e: TDGame.Enemy) -> bool:
	var p := g.pos_of(e)
	for t in g.towers:
		if t.def.has("aura") or not TDGame.can_hit(t.def, e):
			continue
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		if p.distance_to(c) <= g.t_range(t) and g._visible_to(e, c):
			return true
	return false


func _play(seed_v: int) -> Dictionary:
	cells_by_kind = {}
	_cover_cache = {}
	strat = _ablated(STRATEGIES[strategy_id].duplicate(true)) # сценарий switch меняет стратегию по ходу партии
	spent_build = 0
	spent_upgrade = 0
	var map_ := TDMap.portal_test(family, portal_open, portal_announce, portal_share) if TDMap.PORTAL_MAPS.has(family) else TDMap.generate(seed_v, family)
	if not route_plan_override.is_empty() and map_.is_multi():
		map_.route_plan = route_plan_override.duplicate()
	var g := TDGame.new(seed_v, map_, _meta())
	var perk_rng := TDRng.new(seed_v * 7919)
	var last := maxi(max_wave, cap)
	var waves: Array = []
	var min_lives: int = g.lives
	var lives_at_30 := -1
	var leaks_by_30 := 0
	var t_sim := 0.0
	# трекинг врагов: id -> [время появления, летит, время под огнём, босс, ребёнок]
	var track := {}
	var life_g: Array = []
	var life_a: Array = []
	var expo_g: Array = []
	var expo_a: Array = []
	while g.phase != "over" and g.wave <= last:
		if g.phase == "build":
			if strat.has("switch_at") and g.wave == int(strat["switch_at"]):
				_switch(g)
			var gold0 := g.gold
			var sb0 := spent_build
			var su0 := spent_upgrade
			if not _replay.is_empty():
				_replay_wave(g, perk_rng, seed_v)
			else:
				var before := _tower_state(g)
				var perks_before := g.perks.duplicate()
				_pick_perk(g, perk_rng)
				_build_phase(g)
				_pick_perk(g, perk_rng)
				if record_path != "":
					_record_wave(g, seed_v, before, perks_before)
			if not g.start_wave():
				break
			# микро как у человека: на боссовой волне снайперы и пушки бьют самого крепкого
			if micro:
				for t in g.towers:
					if t.kind in ["sniper", "cannon"]:
						g.set_mode(t, "strong" if not g.pending_boss.is_empty() else "first")
			life_g = []
			life_a = []
			expo_g = []
			expo_a = []
			track = {}
			waves.append({"w": g.wave, "gold_pre": gold0, "gold_post": g.gold, "build": spent_build - sb0, "upg": spent_upgrade - su0, "lives0": g.lives})
		g.step(DT)
		t_sim += DT
		var seen := {}
		for e in g.enemies:
			seen[e.id] = true
			if not track.has(e.id):
				track[e.id] = [t_sim, bool(e.ph["fly"]), 0.0, e.boss, e.child, 0.0, e.strain]
			if e.hp > 0.0 and _exposed(g, e):
				track[e.id][2] += DT
			if e.dist >= 0.0:
				track[e.id][5] = g.progress_of(e)
			else:
				track[e.id][5] = 1.5
			if e.boss and not waves.is_empty():
				waves[waves.size() - 1]["boss_prog"] = _r(track[e.id][5])
				waves[waves.size() - 1]["boss_hp"] = int(e.ph["hp"])
		for id in track.keys():
			if not seen.has(id):
				var rec: Array = track[id]
				# прорыв: враг исчез у самого замка (утечка снимается с поля в тот же шаг, поэтому 1.5 харнесс не видит)
				if model != "" and not waves.is_empty() and float(rec[5]) >= 0.99 and not rec[3]:
					var sk := "leak_" + (String(rec[6]) if String(rec[6]) != "" else "base")
					waves[waves.size() - 1][sk] = int(waves[waves.size() - 1].get(sk, 0)) + 1
				if not rec[3] and not rec[4]:
					(life_a if rec[1] else life_g).append(t_sim - rec[0])
					(expo_a if rec[1] else expo_g).append(rec[2])
				track.erase(id)
		min_lives = mini(min_lives, g.lives)
		if waves.is_empty() or waves[waves.size() - 1].has("done"):
			continue
		if g.phase == "over":
			var wl: Dictionary = waves[waves.size() - 1]
			wl["done"] = true
			wl["lost"] = true
			wl["leaked"] = g.leaked
			wl["lives"] = 0
			if wl["w"] <= 30:
				leaks_by_30 += g.leaked
		elif g.phase == "build":
			_close_wave(g, waves[waves.size() - 1], life_g, life_a, expo_g, expo_a)
			var wr: Dictionary = waves[waves.size() - 1]
			if wr["w"] <= 30:
				leaks_by_30 += int(wr["leaked"])
			if wr["w"] == 30:
				lives_at_30 = g.lives
	var end_wave: int = g.wave if g.phase == "over" else last + 1
	var comp := {}
	var spent_by := {}
	var levels := {}
	for t in g.towers:
		comp[t.kind] = int(comp.get(t.kind, 0)) + 1
		spent_by[t.kind] = int(spent_by.get(t.kind, 0)) + t.spent
		levels[t.kind] = levels.get(t.kind, []) + [t.level if t.level < 3 else "3" + t.branch]
	var dmg := {}
	for k in g.run_damage:
		if g.run_damage[k] > 0.0:
			dmg[k] = int(g.run_damage[k])
	var res := {
		"strategy": strategy_id, "seed": seed_v, "family": g.map.family, "difficulty": difficulty, "workshop": workshop,
		"swarm": swarm, "ablate": ablate, "micro": micro, "branch": branch_override, "range_variant": TDConfig.range_variant, "branch_set": branch_set, "upgrades": upgrades, "perks": perk_mode,
		"path_len": _r(g.map.length, 2), "fly_len": _r(g.map.fly_length, 2),
		"summary": {
			"end_wave": end_wave, "won30": end_wave > 30, "lives_at_30": lives_at_30, "leaks_by_30": leaks_by_30,
			"min_lives": min_lives, "final_lives": g.lives, "spent_build": spent_build, "spent_upgrade": spent_upgrade,
			"composition": comp, "spent_by": spent_by, "levels": levels, "run_damage": dmg, "perks": g.perks,
			"bosses_killed": g.bosses_killed,
		},
		"waves": waves,
	}
	# PRO-213: карта с развилкой — длины дорог, общие участки, геометрия; откат развилки на обычную карту отмечается
	if g.map.is_multi():
		var lens: Array = []
		for rt in g.map.routes:
			lens.append(_r(rt.length, 2))
		res["routes"] = {"len": lens, "plan": g.map.route_plan, "shared_in": g.map.shared_in(), "shared_out": g.map.shared_out(), "geometry": g.map.geometry_key()}
	if g.map.portal2:
		res["routes"]["portal"] = {"open": g.map.portal_open, "announce": g.map.portal_announce, "share": g.map.portal_share, "policy": portal_policy}
	if g.map.fork_fallback or g.map.portal_fallback:
		res["fork_fallback"] = true
	if model != "" or counter != "" or replay_path != "":
		res["model"] = model
		res["counter"] = counter
		res["counter_at"] = counter_at
		res["replay"] = replay_path != ""
	return res


func _close_wave(g: TDGame, wr: Dictionary, life_g: Array, life_a: Array, expo_g: Array, expo_a: Array) -> void:
	wr["done"] = true
	var r: Dictionary = g.reports[g.reports.size() - 1]
	wr["leaked"] = int(r["leaked"])
	wr["killed"] = int(r["killed"])
	wr["size"] = int(r["size"])
	wr["special"] = String(r.get("special", ""))
	wr["bonus"] = int(r["bonus"])
	wr["interest"] = int(r["interest"])
	wr["gold_end"] = g.gold
	wr["kill_income"] = g.gold - int(wr["gold_post"]) - int(r["bonus"]) - int(r["interest"])
	wr["lives"] = g.lives
	wr["lives_lost"] = int(wr["lives0"]) - g.lives
	# прорвавшийся босс стоит BOSS_LEAK жизней, остальные по одной
	wr["boss_leak"] = (int(wr["lives_lost"]) - int(wr["leaked"])) / (TDConfig.BOSS_LEAK - 1) if wr.has("boss_prog") else 0
	var dmg := {}
	for k in r["damageBy"]:
		if float(r["damageBy"][k]) > 0.0:
			dmg[k] = int(r["damageBy"][k])
	wr["dmg"] = dmg
	var avg := {}
	for k in r["avg"]:
		avg[k] = _r(float(r["avg"][k]))
	wr["genes"] = avg
	var press := {}
	for k in r["pressure"]:
		press[k] = _r(float(r["pressure"][k]))
	wr["press"] = press
	# фенотип волны и активные признаки
	var n: int = g.wave_genomes.size()
	var fly := 0
	var stealth := 0
	var split := 0
	var ward := 0
	var armor := 0.0
	var fire_res := 0.0
	var frost_res := 0.0
	var speed := 0.0
	var hp := 0.0
	var arrow_eff := 0.0
	var arrow3_eff := 0.0
	var w: int = int(wr["w"])
	var arrow1: Dictionary = TDConfig.tower_def("arrow", 1, "")
	var arrow3: Dictionary = TDConfig.tower_def("arrow", 3, "a")
	for ge in g.wave_genomes:
		var ph := TDGenome.phenotype(ge, w)
		fly += 1 if ph["fly"] else 0
		stealth += 1 if ph["stealth"] else 0
		split += 1 if ph["split"] else 0
		ward += 1 if ph["ward"] else 0
		armor += ph["armor"]
		fire_res += ph["fireRes"]
		frost_res += ph["frostRes"]
		speed += ph["speed"]
		hp += ph["hp"]
		arrow_eff += TDGame.effective_damage(arrow1["damage"], "physical", ph) / arrow1["damage"]
		arrow3_eff += TDGame.effective_damage(arrow3["damage"], "physical", ph) / arrow3["damage"]
	var nn: float = maxf(1.0, float(n))
	wr["ph"] = {"fly": fly, "stealth": stealth, "split": split, "ward": ward, "armor": _r(armor / nn), "fireRes": _r(fire_res / nn),
		"frostRes": _r(frost_res / nn), "speed": _r(speed / nn), "hp": _r(hp / nn, 1), "arrow1_eff": _r(arrow_eff / nn), "arrow3a_eff": _r(arrow3_eff / nn)}
	# дистанция гибели: доля пути убитого врага (без малышей и босса); 1.5 = прорвался
	var prog_g: Array = []
	var prog_a: Array = []
	for f in g.finished:
		var p: float = f["fitness"]
		var is_fly: bool = float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD
		(prog_a if is_fly else prog_g).append(p)
	wr["prog_g"] = [_r(_pct(prog_g, 0.5)), _r(_pct(prog_g, 0.9)), prog_g.size()]
	wr["prog_a"] = [_r(_pct(prog_a, 0.5)), _r(_pct(prog_a, 0.9)), prog_a.size()]
	# PRO-213: по дорогам развилки — доля врагов, погибших в первых 20% своей дороги, p90 и максимум пройденной доли,
	# доля дальше 40%, прорывы (обычные враги волны, наземные; доля пути — своей дороги)
	if g.map.is_multi():
		var per := {}
		for rt in g.map.routes:
			per[rt.id] = []
		for f in g.finished:
			if float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD:
				continue
			per[int(f.get("route", 0))].append(float(f["fitness"]))
		var routes_out := {}
		for rid in per:
			var ps: Array = per[rid]
			var g20 := 0
			var b40 := 0
			var lk := 0
			var mx := -1.0
			for p in ps:
				g20 += 1 if p < 0.2 else 0
				b40 += 1 if p > 0.4 else 0
				lk += 1 if p >= 1.5 else 0
				mx = maxf(mx, p)
			routes_out[str(rid)] = {"n": ps.size(), "gate20": _r(float(g20) / maxf(1.0, ps.size())), "p90": _r(_pct(ps, 0.9)),
				"max": _r(mx), "beyond40": _r(float(b40) / maxf(1.0, ps.size())), "leaked": lk}
		wr["routes"] = routes_out
	wr["life_g"] = [_r(_mean(life_g), 2), _r(_mean(expo_g), 2), life_g.size()]
	wr["life_a"] = [_r(_mean(life_a), 2), _r(_mean(expo_a), 2), life_a.size()]
	var invested := 0
	var counts := {}
	for t in g.towers:
		invested += t.spent
		counts[t.kind] = int(counts.get(t.kind, 0)) + 1
	wr["invested"] = invested
	wr["towers"] = counts
	if late_metrics:
		_close_wave_late(g, wr)
	if g.strains_on():
		_close_wave_strains(g, wr, r)


## PRO-192: где гибнет волна и насколько оборона превосходит угрозу.
## kill_g/kill_a — [доля убитых в первых 10% пути, в первых 20%, число] (обычные враги волны, без малышей и босса);
## wave_hp — суммарное здоровье волны (сложность, особая волна, пакеты; без босса);
## dps_all — оценка урона в секунду всей обороны по средней цели волны; dps_gate — то же для башен, достающих первые 20% дороги;
## ttk_gate — за сколько секунд «ворота» снимают всё здоровье волны; spawn_s — сколько секунд волна выходит из портала.
func _close_wave_late(g: TDGame, wr: Dictionary) -> void:
	var w: int = int(wr["w"])
	var kg := [0, 0, 0]
	var ka := [0, 0, 0]
	for f in g.finished:
		var p: float = f["fitness"]
		var is_fly: bool = float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD
		var k: Array = ka if is_fly else kg
		k[2] += 1
		if p < 0.1:
			k[0] += 1
		if p < 0.2:
			k[1] += 1
	wr["kill_g"] = [_r(float(kg[0]) / maxf(1.0, kg[2])), _r(float(kg[1]) / maxf(1.0, kg[2])), kg[2]]
	# PRO-212: как далеко заходят наземные враги — максимум (1.5 = прорыв) и доля дальше 40% пути
	var mx := -1.0
	var b40 := 0
	for f in g.finished:
		if float(f["genome"].get("wings", 0.0)) > TDGenome.TRAIT_THRESHOLD:
			continue
		mx = maxf(mx, float(f["fitness"]))
		if float(f["fitness"]) > 0.4:
			b40 += 1
	wr["max_g"] = _r(mx)
	wr["beyond40"] = _r(float(b40) / maxf(1.0, kg[2]))
	# реальный урон и попадания по наземным врагам по зонам пути: < 20%, 20–40%, > 40%
	var zd: float = g.zone_dmg[0] + g.zone_dmg[1] + g.zone_dmg[2]
	var zh: int = g.zone_hits[0] + g.zone_hits[1] + g.zone_hits[2]
	wr["zone_dmg"] = [_r(g.zone_dmg[0] / maxf(1.0, zd)), _r(g.zone_dmg[1] / maxf(1.0, zd)), int(zd)]
	wr["zone_hits"] = [_r(float(g.zone_hits[0]) / maxf(1.0, zh)), _r(float(g.zone_hits[1]) / maxf(1.0, zh)), zh]
	g.zone_dmg = [0.0, 0.0, 0.0]
	g.zone_hits = [0, 0, 0]
	wr["kill_a"] = [_r(float(ka[0]) / maxf(1.0, ka[2])), _r(float(ka[1]) / maxf(1.0, ka[2])), ka[2]]
	var hp_mult: float = float(TDConfig.difficulty(g.meta)["hp"])
	var sp: Dictionary = TDConfig.SPECIAL_WAVES.get(String(wr.get("special", "")), {})
	var hp := 0.0
	var phs: Array = []
	for ge in g.wave_genomes:
		var strain := String(ge.get("strain", ""))
		var ph := TDStrains.apply_ph(TDGenome.phenotype(ge, w), strain)
		phs.append(ph)
		hp += float(ph["hp"]) * (TDStrains.BROOD_N if strain == "brood" else 1) * hp_mult * float(sp.get("hp", 1.0))
	var avg := {"armor": 0.0, "fireRes": 0.0, "frostRes": 0.0, "regen": 0.0, "fly": false, "stealth": false}
	for ph in phs:
		for k2 in ["armor", "fireRes", "frostRes", "regen"]:
			avg[k2] += float(ph[k2]) / maxf(1.0, phs.size())
	var gate: Array = []
	for i in 12:
		gate.append(g.map.pos_at((i + 0.5) / 12.0 * 0.2 * g.map.length))
	# PRO-213: на развилке «ворота» — первые 20% каждой дороги, и покрытие считается и по каждой дороге отдельно
	if g.map.is_multi():
		gate.clear()
		var cov_r := {}
		for rt in g.map.routes:
			var hit := 0
			for i in 12:
				var p := rt.pos_at((i + 0.5) / 12.0 * 0.2 * rt.length)
				gate.append(p)
				for t in g.towers:
					if not t.def.has("aura") and t.def["ground"] and p.distance_to(Vector2(t.x + 0.5, t.y + 0.5)) <= g.t_range(t):
						hit += 1
						break
			cov_r[str(rt.id)] = _r(hit / 12.0)
		wr["cov20_routes"] = cov_r
	var dps_all := 0.0
	var dps_gate := 0.0
	for t in g.towers:
		var d := _est_dps(g, t.def, avg) * g.beacon_buff(t.x, t.y) if not t.def.has("aura") else 0.0
		if t.def.has("aura") or not t.def["ground"]:
			continue
		dps_all += d
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		for p2 in gate:
			if p2.distance_to(c) <= g.t_range(t):
				dps_gate += d
				break
	# PRO-141: два портала — отдельно ворота каждого входа: покрытие, урон в секунду, сколько башен достают оба входа
	if g.map.portal2:
		var gates: Array = []
		for rt in g.map.routes:
			var pts_: Array = []
			for i in 12:
				pts_.append(rt.pos_at((i + 0.5) / 12.0 * 0.2 * rt.length))
			gates.append(pts_)
		var dps_r := [0.0, 0.0]
		var n_r := [0, 0]
		var n_both := 0
		var dps_both := 0.0
		var dps_any := 0.0
		var shooters_n := 0
		for t in g.towers:
			if t.def.has("aura") or not t.def["ground"]:
				continue
			shooters_n += 1
			var d2 := _est_dps(g, t.def, avg) * g.beacon_buff(t.x, t.y)
			var c2 := Vector2(t.x + 0.5, t.y + 0.5)
			var hits := [false, false]
			for ri in 2:
				for p4 in gates[ri]:
					if p4.distance_to(c2) <= g.t_range(t):
						hits[ri] = true
						break
				if hits[ri]:
					dps_r[ri] += d2
					n_r[ri] += 1
			if hits[0] and hits[1]:
				n_both += 1
				dps_both += d2
			if hits[0] or hits[1]:
				dps_any += d2
		wr["portal"] = {"dps_gate": [int(dps_r[0]), int(dps_r[1])], "n_gate": n_r, "n_both": n_both, "n_shooters": shooters_n,
			"dps_both": int(dps_both), "dps_any": int(dps_any), "state": g.map.portal_state(w)}
	# покрытие дороги дальностью: доля точек первых 20% пути, которые достаёт хоть одна наземная башня,
	# и сколько башен в среднем достают точку в первых 20% и на остальных 80% пути
	var rest: Array = []
	for rt in (g.map.routes if g.map.is_multi() else [g.map.routes[0]]):
		for i in 32:
			rest.append(rt.pos_at((0.2 + (i + 0.5) / 32.0 * 0.8) * rt.length))
	var cov := 0
	var depth_g := 0
	var depth_r := 0
	for pts in [gate, rest]:
		for p3 in pts:
			var n := 0
			for t in g.towers:
				if t.def.has("aura") or not t.def["ground"]:
					continue
				if p3.distance_to(Vector2(t.x + 0.5, t.y + 0.5)) <= g.t_range(t):
					n += 1
			if pts == gate:
				depth_g += n
				cov += 1 if n > 0 else 0
			else:
				depth_r += n
	wr["cov20"] = _r(float(cov) / gate.size())
	wr["depth20"] = _r(float(depth_g) / gate.size())
	wr["depth_rest"] = _r(float(depth_r) / rest.size())
	if w in [10, 20, 29]:
		var l3 := {}
		for t in g.towers:
			if t.level >= 3:
				var k3 := "%s_%s" % [t.kind, t.branch]
				l3[k3] = int(l3.get(k3, 0)) + 1
		wr["l3"] = l3
	wr["wave_hp"] = int(hp)
	wr["dps_all"] = int(dps_all)
	wr["dps_gate"] = int(dps_gate)
	wr["ttk_gate"] = _r(hp / maxf(1.0, dps_gate), 1)
	wr["spawn_s"] = _r(g.wave_genomes.size() * TDConfig.spawn_interval(w, String(wr.get("special", ""))), 1)
	wr["gold_bank"] = g.gold


## PRO-152: сигнатура, инкубация и состав пакетов этой волны; суммарное здоровье волны (бюджет угрозы).
func _close_wave_strains(g: TDGame, wr: Dictionary, r: Dictionary) -> void:
	var sx: Dictionary = r.get("strains", {})
	var sig: Dictionary = sx.get("sig", {})
	var out := {"C": _r(float(sx.get("C", 0.0))), "air_gap": _r(float(sig.get("air_gap", 0.0)))}
	for k in ["burst", "rapid", "chill", "control"]:
		out[k] = _r(float(sig.get(k, 0.0)))
	for dist in ["del", "el"]:
		var d := {}
		for k in sig.get(dist, {}):
			d[k] = _r(float(sig[dist][k]))
		out[dist] = d
	var pk := {}
	for p in sx.get("pk", {}):
		var k: Dictionary = sx["pk"][p]
		pk[p] = [_r(float(k["inc"])), _r(float(k["share"])), String(k["phase"])]
	out["pk"] = pk
	# состав и здоровье сыгранной волны (без босса), с учётом пакетов, сложности и особой волны
	var w: int = int(wr["w"])
	var hp_mult: float = float(TDConfig.difficulty(g.meta)["hp"])
	var sp: Dictionary = TDConfig.SPECIAL_WAVES.get(String(wr.get("special", "")), {})
	var hp := 0.0
	var bodies := 0
	var by := {}
	for ge in g.wave_genomes:
		var strain := String(ge.get("strain", ""))
		var ph := TDStrains.apply_ph(TDGenome.phenotype(ge, w), strain)
		var n_b: int = TDStrains.BROOD_N if strain == "brood" else 1
		hp += float(ph["hp"]) * n_b * hp_mult * float(sp.get("hp", 1.0))
		bodies += n_b
		if strain != "":
			by[strain] = int(by.get(strain, 0)) + 1
	out["wave_hp"] = int(hp)
	out["bodies"] = bodies
	out["strain_n"] = by
	wr["sx"] = out


# ── PRO-152: замороженная политика ──────────────────────────────

func _tower_state(g: TDGame) -> Dictionary:
	var d := {}
	for t in g.towers:
		d[t.id] = [t.kind, t.x, t.y, t.level, t.branch]
	return d


## Журнал фазы строительства: перки, продажи, постройки, улучшения — в порядке применения.
func _record_wave(g: TDGame, seed_v: int, before: Dictionary, perks_before: Dictionary) -> void:
	var ops: Array = []
	for p in g.perks:
		for _i in int(g.perks[p]) - int(perks_before.get(p, 0)):
			ops.append(["perk", p])
	var after := _tower_state(g)
	for id in before:
		if not after.has(id):
			ops.append(["sell", before[id][1], before[id][2]])
	for t in g.towers:
		var lvl0: int = int(before[t.id][3]) if before.has(t.id) else 0
		if lvl0 == 0:
			ops.append(["place", t.kind, t.x, t.y])
			lvl0 = 1
		for l in range(lvl0 + 1, t.level + 1):
			ops.append(["up", t.x, t.y, t.branch if l == 3 else ""])
	var key := str(seed_v)
	if not _record.has(key):
		_record[key] = {}
	_record[key][str(g.wave)] = ops


## Повтор журнала: те же действия в те же волны, золото не ограничивает (одинаковый бюджет в обоих плечах).
func _replay_wave(g: TDGame, perk_rng: TDRng, seed_v: int) -> void:
	var ops: Array = _replay.get(str(seed_v), {}).get(str(g.wave), [])
	for op in ops:
		if op[0] == "perk" and g.offer.has(op[1]):
			g.choose_perk(op[1])
	if not g.offer.is_empty():
		_pick_perk(g, perk_rng)
	for op in ops:
		g.gold = maxi(g.gold, 1000000)
		match String(op[0]):
			"sell":
				g.sell_tower(int(op[1]), int(op[2]))
			"place":
				var c := g.tower_cost(op[1])
				if g.place_tower(op[1], int(op[2]), int(op[3])):
					spent_build += c
			"up":
				var t := g.tower_at(int(op[1]), int(op[2]))
				if t != null:
					var c2 := g.upgrade_cost(t)
					if g.upgrade_tower(t, String(op[3])):
						spent_upgrade += c2
	g.gold = 0
