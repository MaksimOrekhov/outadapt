extends SceneTree
## Боты играют разными стратегиями: смотрим баланс и то, как эволюционирует рой.
## Запуск: godot --headless --path godot --script res://tests/bot.gd [-- -v] [-- --waves=40] [-- --seeds=3]

const DT := 1.0 / 30.0

var max_wave := 40
var seeds := 3
## Сдвиг сидов: чтобы гонять карты параллельно разными процессами (--seed-from=2 --seeds=1).
var seed_from := 0
## Улучшать ли башни и какую ветку брать: "a", "b" или "mix" (по чётности id).
var upgrades := true
var branch_mode := "mix"
var verbose := false
## Сложность и режим для прогона: --difficulty=easy|normal|hard, --mode=standard|endless
var only := ""
var difficulty := "normal"
var mode := "standard"
## Вакцина: off — не покупать; grow — против самого быстро растущего гена; threat — против полёта, невидимости, щита, лечения, деления; surplus — grow, но только на остаток золота после постройки.
var vaccine_mode := "off"  # off | grow | threat | surplus (только на остаток золота после постройки)
var vaccine_buys := 0
## Принудительное семейство карт: --family=snake|vsnake|stairs|hooks (по умолчанию по сиду).
var family := ""
## Приманка: --lure=off|tough|swift|plated|ember|frost|rotate (по кругу). Бот берёт её, когда она доступна.
var lure_mode := "off"
var lure_buys := 0

const ALL: Array[String] = ["arrow", "frost", "ember", "poison", "arrow", "flak", "cannon", "tesla", "sniper", "beacon"]
const COMBO: Array[String] = ["arrow", "frost", "arrow", "ember"]
const CYCLE: Array[String] =["arrow", "frost", "ember", "cannon", "sniper", "arrow", "frost", "poison"]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "-v":
			verbose = true
		elif a.begins_with("--waves="):
			max_wave = int(a.substr(8))
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed-from="):
			seed_from = int(a.substr(12))
		elif a.begins_with("--difficulty="):
			difficulty = a.substr(13)
		elif a.begins_with("--mode="):
			mode = a.substr(7)
		elif a == "--no-abilities":
			TDConfig.abilities_on = false
		elif a == "--no-specials":
			TDConfig.specials_on = false
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a == "--no-upgrades":
			upgrades = false
		elif a.begins_with("--lure="):
			lure_mode = a.substr(7)
		elif a.begins_with("--family="):
			family = a.substr(9)
		elif a.begins_with("--vaccine="):
			vaccine_mode = a.substr(10)
		elif a.begins_with("--branch="):
			branch_mode = a.substr(9)
	var strategies := {
		"только лучники": func(_g: TDGame) -> String: return "arrow",
		"только пушки": func(_g: TDGame) -> String: return "cannon",
		"только снайперы": func(_g: TDGame) -> String: return "sniper",
		"только огонь": func(_g: TDGame) -> String: return "ember",
		"только тесла": func(_g: TDGame) -> String: return "tesla",
		"все по кругу (дешёвые первыми)": func(g: TDGame) -> String: return ALL[g.towers.size() % ALL.size()],
		"связка: лучники + лёд + огонь": func(g: TDGame) -> String: return COMBO[g.towers.size() % COMBO.size()],
		"адаптивный (читает рой)": _adaptive,
		"советник (берёт башню с лучшими звёздами)": _advisor,
	}
	for name in strategies:
		if only != "" and not name.contains(only):
			continue
		print("\n", name)
		var results: Array[String] = []
		for i in seeds:
			results.append(str(_play(strategies[name], (seed_from + i + 1) * 4243, verbose and i == 0)))
		var sum := 0.0
		for r in results:
			sum += float(r)
		print("  => дошёл до волны: %s  среднее %.1f  (>%d = не проиграл)%s" % [", ".join(results), sum / results.size(), max_wave, ("  вакцин куплено: %d" % vaccine_buys) if vaccine_mode != "off" else ""])
		if lure_mode != "off":
			print("  приманок куплено: %d" % lure_buys)
		vaccine_buys = 0
		lure_buys = 0
	quit()


## Слушается советника: башня с максимумом звёзд, при равенстве — дешевле.
func _advisor(g: TDGame) -> String:
	var ratings := TDAdvisor.rate_towers(g, TDAdvisor.wave_info(g))
	var best := "arrow"
	for k in TDConfig.TOWER_KINDS:
		var s: int = ratings[k]["stars"]
		var bs: int = ratings[best]["stars"]
		if s > bs or (s == bs and g.tower_cost(k) < g.tower_cost(best)):
			best = k
	return best


func _adaptive(g: TDGame) -> String:
	var n: int = maxi(1, g.upcoming.size())
	var fly := 0.0
	var stealth := 0.0
	var regen := 0.0
	for e in g.upcoming:
		if e["wings"] > TDGenome.TRAIT_THRESHOLD:
			fly += 1.0
		if e["veil"] > TDGenome.TRAIT_THRESHOLD:
			stealth += 1.0
		regen += e["regen"]
	if stealth / n > 0.1 and g.count_of("beacon") < 2:
		return "beacon"
	if fly / n > 0.15 and g.count_of("flak") < 4:
		return "flak"
	if regen / n > 0.15 and g.count_of("poison") < 4:
		return "poison"
	return CYCLE[g.towers.size() % CYCLE.size()]


## Клетки, отсортированные по тому, сколько пути они накрывают.
func _coverage_cells(g: TDGame, r: float = 3.0) -> Array:
	var cells: Array = []
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if g.map.is_path(x, y) or g.map.is_blocked(x, y):
				continue
			var score := 0
			for s in 80:
				var p := g.map.pos_at(s / 80.0 * g.map.length)
				if p.distance_to(Vector2(x + 0.5, y + 0.5)) <= r:
					score += 1
			cells.append({"x": x, "y": y, "score": score})
	cells.sort_custom(func(a, b): return a["score"] > b["score"])
	return cells


## Улучшение, которое бот взял бы сейчас: башня, больше всех наносившая урона.
func _best_upgrade(g: TDGame) -> TDGame.Tower:
	var best: TDGame.Tower = null
	for t in g.towers:
		if g.upgrade_cost(t) < 0:
			continue
		if best == null or t.dealt > best.dealt:
			best = t
	return best


func _branch_for(t: TDGame.Tower) -> String:
	if branch_mode == "mix":
		return "a" if t.id % 2 == 0 else "b"
	return branch_mode


func _build_phase(g: TDGame, pick: Callable, cells: Array) -> void:
	for _guard in 160:
		var kind: String = pick.call(g)
		var spot = null
		for c in cells:
			if g.can_place(kind, c["x"], c["y"]):
				spot = c
				break
		var up := _best_upgrade(g) if upgrades else null
		# улучшаем, если это не дороже новой башни (или строить уже негде)
		if up != null and (spot == null or g.upgrade_cost(up) <= g.tower_cost(kind)):
			if g.can_upgrade(up):
				g.upgrade_tower(up, _branch_for(up))
				continue
			return
		if spot == null or not g.place_tower(kind, spot["x"], spot["y"]):
			return


## Бот покупает вакцину против самого быстро растущего гена (по отчёту прошлой волны).
func _vaccinate(g: TDGame) -> void:
	if vaccine_mode == "off" or g.reports.is_empty():
		return
	if vaccine_mode == "surplus" and g.gold < TDConfig.vaccine_cost(g.wave) + 60:
		return
	var r: Dictionary = g.reports[g.reports.size() - 1]
	var best := ""
	var best_growth := 0.05
	for k in TDGenome.GENES:
		if vaccine_mode == "threat" and not (k in ["wings", "veil", "ward", "regen", "split"]):
			continue
		var growth: float = float(TDGenome.average_genome(g.upcoming)[k]) - float(r["avg"][k])
		if vaccine_mode == "threat":
			growth = float(TDGenome.average_genome(g.upcoming)[k])
		if growth > best_growth and g.vaccine_problem(k) == "":
			best = k
			best_growth = growth
	if best != "" and g.buy_vaccine(best):
		vaccine_buys += 1


func _lure(g: TDGame) -> void:
	if lure_mode == "off":
		return
	var gene := lure_mode
	if lure_mode == "rotate":
		gene = TDConfig.LURE_GENES[g.lure_uses % TDConfig.LURE_GENES.size()]
	if g.lure_problem(gene) == "" and g.buy_lure(gene):
		lure_buys += 1


func _play(pick: Callable, seed_v: int, show: bool) -> int:
	var g := TDGame.new(seed_v, TDMap.generate(seed_v, family), {"difficulty": difficulty, "mode": mode})
	var cells := _coverage_cells(g)
	var perk_rng := TDRng.new(seed_v * 7919) # бот берёт случайный перк из предложенных
	var shown := 0
	while g.phase != "over" and g.wave <= max_wave:
		if g.phase == "build":
			if not g.offer.is_empty():
				g.choose_perk(g.offer[int(floor(perk_rng.next() * g.offer.size()))])
			if vaccine_mode != "surplus":
				_vaccinate(g)
			_lure(g)
			_build_phase(g, pick, cells)
			if vaccine_mode == "surplus":
				_vaccinate(g)
			g.start_wave()
		g.step(DT)
		if show and not g.reports.is_empty():
			var last: Dictionary = g.reports[g.reports.size() - 1]
			if last["wave"] % 5 == 0 and shown < last["wave"]:
				shown = last["wave"]
				var f: Dictionary = last["avg"]
				print("    волна %d: броня=%.2f огонь=%.2f лёд=%.2f полёт=%.2f невид=%.2f лечение=%.2f | прорвалось %d/%d | жизни %d" % [
					last["wave"], f["plated"], f["ember"], f["frost"], f["wings"], f["veil"], f["regen"], last["leaked"], last["size"], g.lives])
	return g.wave if g.phase == "over" else max_wave + 1
