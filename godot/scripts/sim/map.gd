class_name TDMap
extends RefCounted
## Карта: путь по клеткам, скалы, позиции вдоль дороги.

var seed_value: int = 0
var map_name: String = ""
var waypoints: Array[Vector2i] = []
## Центры клеток вдоль пути.
var points: Array[Vector2] = []
var seg_len: Array[float] = []
var length: float = 0.0
## Длина прямой «по воздуху» от входа до выхода.
var fly_length: float = 0.0
## Клетки дороги по порядку и как множество.
var order: Array[Vector2i] = []
var cells: Dictionary = {}
## Скалы: клетки, на которых нельзя строить.
var blocked: Dictionary = {}
## PRO-139: маршруты от портала к замку. routes[0] — основной; waypoints, points, seg_len, length, fly_length и order
## выше — его поля (на карте с одним путём так было всегда). cells — объединение клеток всех маршрутов.
var routes: Array[TDPath] = []
## Распределение врагов по маршрутам: k-й выпущенный враг волны идёт по маршруту route_plan[k % size].
## Фиксированный шаблон, без случайности и без реакции на оборону (адаптивный выбор — PRO-140).
var route_plan: Array[int] = [0]

const CLASSIC_WAYPOINTS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(13, 1), Vector2i(13, 4), Vector2i(2, 4), Vector2i(2, 7), Vector2i(15, 7),
]


## Клетки пути по порядку или пустой массив, если путь касается сам себя.
static func rasterize(wps: Array[Vector2i]) -> Array[Vector2i]:
	var order_: Array[Vector2i] = []
	for i in wps.size():
		var p: Vector2i = wps[i]
		if i == 0:
			order_.append(p)
			continue
		var q: Vector2i = wps[i - 1]
		var dx: int = signi(p.x - q.x)
		var dy: int = signi(p.y - q.y)
		var x: int = q.x
		var y: int = q.y
		while x != p.x or y != p.y:
			x += dx
			y += dy
			order_.append(Vector2i(x, y))
	var index := {}
	for i in order_.size():
		if index.has(order_[i]):
			return []
		index[order_[i]] = i
	# между соседними кусками дороги должна оставаться хотя бы одна клетка для башен
	for i in order_.size():
		var c: Vector2i = order_[i]
		for n in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
			if index.has(n) and absi(int(index[n]) - i) != 1:
				return []
	return order_


static func build(seed_v: int, name_: String, wps: Array[Vector2i], blocked_: Dictionary = {}) -> TDMap:
	return build_routes(seed_v, name_, [wps], blocked_)


## PRO-139: карта из нескольких маршрутов (у каждого — свои вершины от портала до замка; общие участки совпадают).
## Один маршрут — ровно прежняя карта. plan пустой — враги идут по маршрутам по кругу 0, 1, …
static func build_routes(seed_v: int, name_: String, route_wps: Array, blocked_: Dictionary = {}, plan: Array[int] = []) -> TDMap:
	var m := TDMap.new()
	m.seed_value = seed_v
	m.map_name = name_
	for i in route_wps.size():
		var wps: Array[Vector2i] = []
		wps.assign(route_wps[i])
		m.routes.append(TDPath.from_waypoints(i, wps))
	var main: TDPath = m.routes[0]
	m.waypoints = main.waypoints
	m.points = main.points
	m.seg_len = main.seg_len
	m.length = main.length
	m.fly_length = main.fly_length
	m.order = main.order
	for r in m.routes:
		for c in r.order:
			m.cells[c] = true
	m.blocked = blocked_
	if not plan.is_empty():
		m.route_plan = plan
	elif m.routes.size() > 1:
		m.route_plan.assign(range(m.routes.size()))
	return m


func pos_at(dist: float) -> Vector2:
	return routes[0].pos_at(dist)


## Позиция летающего: по прямой от входа к выходу.
func fly_pos_at(dist: float) -> Vector2:
	return routes[0].fly_pos_at(dist)


## Направление пути в точке. Для движения по воздуху используется прямая от входа к выходу.
func heading_at(dist: float, flying: bool = false) -> Vector2:
	return routes[0].heading_at(dist, flying)


# ── PRO-139: несколько маршрутов ─────────────────────────────────

func is_multi() -> bool:
	return routes.size() > 1


## Маршрут по номеру (неизвестный номер — основной маршрут).
func route(i: int) -> TDPath:
	return routes[i] if i >= 0 and i < routes.size() else routes[0]


## Маршрут k-го врага волны по фиксированному шаблону.
func route_for(k: int) -> int:
	return route_plan[k % route_plan.size()]


## Длина самого длинного наземного маршрута: общая шкала «кто ближе к замку» для целей башен.
func ref_length() -> float:
	var l := 0.0
	for r in routes:
		l = maxf(l, r.length)
	return l


## Клетки дороги без повторов: основной маршрут по порядку, затем клетки других маршрутов, которых на нём нет.
## На карте с одним путём — ровно order.
func road_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = order.duplicate()
	if not is_multi():
		return out
	var seen := {}
	for c in order:
		seen[c] = true
	for r in routes:
		for c in r.order:
			if not seen.has(c):
				seen[c] = true
				out.append(c)
	return out


## Маршруты, проходящие через клетку.
func routes_at(c: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for r in routes:
		if r.order.has(c):
			out.append(r.id)
	return out


## Версия геометрии для рекордов и журналов (PRO-147): совпадает, только если совпадают все маршруты и скалы.
func geometry_key() -> String:
	var parts: Array[String] = []
	for r in routes:
		parts.append(str(r.waypoints))
	var b: Array = blocked.keys()
	b.sort()
	parts.append(str(b))
	return "%08x" % hash("|".join(parts))


## Инварианты сети маршрутов (PRO-139, первый MVP). Пустой список — карта корректна.
##   все маршруты растеризуются; один вход (общая первая клетка на левом краю), один замок (общая последняя на правом);
##   последний участок горизонтальный, ≥ 3 клеток (портал, замок, castle_layout);
##   разные маршруты не касаются друг друга вне общих участков (между дорогами остаётся место под башню);
##   на общих клетках маршруты идут в одну сторону, сеть ацикличная, тупиков нет;
##   у каждого маршрута есть свои клетки (нет дублей); длины в пределах и отношение длинного к короткому ≤ max_ratio;
##   вход не ближе min_fly к замку по прямой (нет спавна у замка); мест под башни ≥ min_build.
func route_problems(min_len: int = MIN_PATH, max_len: int = MAX_PATH, max_ratio: float = 1.5, min_fly: float = 8.0, min_build: int = 40) -> Array[String]:
	var bad: Array[String] = []
	if routes.is_empty():
		return ["нет маршрутов"]
	for r in routes:
		if r.order.is_empty():
			bad.append("маршрут %d не растеризуется (касается сам себя)" % r.id)
	if not bad.is_empty():
		return bad
	var start: Vector2i = routes[0].order[0]
	var finish: Vector2i = routes[0].order.back()
	var min_l := INF
	var max_l := 0.0
	for r in routes:
		var w := r.waypoints
		if r.order[0] != start:
			bad.append("маршрут %d начинается не у портала" % r.id)
		if r.order.back() != finish:
			bad.append("маршрут %d заканчивается не у замка" % r.id)
		if w[0].x != 0 or w[0].y < 1:
			bad.append("маршрут %d: вход не на левом краю (строка ≥ 1)" % r.id)
		if w.back().x != TDConfig.COLS - 1 or w.back().y < 2:
			bad.append("маршрут %d: замок не на правом краю (строка ≥ 2)" % r.id)
		if w.size() >= 2 and (w[w.size() - 2].y != w.back().y or w.back().x - w[w.size() - 2].x < 3):
			bad.append("маршрут %d: последний участок не горизонтальный ≥ 3" % r.id)
		if r.order.size() < min_len or r.order.size() > max_len:
			bad.append("маршрут %d: длина %d вне [%d; %d]" % [r.id, r.order.size(), min_len, max_len])
		if r.fly_length < min_fly:
			bad.append("маршрут %d: вход в %.1f клетки от замка (< %.1f)" % [r.id, r.fly_length, min_fly])
		min_l = minf(min_l, r.length)
		max_l = maxf(max_l, r.length)
	if min_l > 0.0 and max_l / min_l > max_ratio:
		bad.append("отношение длин маршрутов %.2f > %.2f" % [max_l / min_l, max_ratio])
	# касания: соседняя клетка дороги должна быть соседом по порядку хоть в одном маршруте
	var nb := {}
	var edges := {}
	for r in routes:
		for i in range(1, r.order.size()):
			var a: Vector2i = r.order[i - 1]
			var b: Vector2i = r.order[i]
			nb[[a, b]] = true
			nb[[b, a]] = true
			edges[[a, b]] = true
	for c in cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if cells.has(n) and not nb.has([c, n]) and c < n:
				bad.append("дороги касаются в %s–%s" % [c, n])
	# направления, циклы, тупики
	var out := {}
	var indeg := {}
	for c in cells:
		indeg[c] = 0
		out[c] = []
	for e in edges:
		if edges.has([e[1], e[0]]) and e[0] < e[1]:
			bad.append("встречное движение в %s–%s" % [e[0], e[1]])
		out[e[0]].append(e[1])
		indeg[e[1]] += 1
	var queue: Array = [start] if indeg[start] == 0 else []
	var seen := 0
	while not queue.is_empty():
		var c = queue.pop_back()
		seen += 1
		for n in out[c]:
			indeg[n] -= 1
			if indeg[n] == 0:
				queue.append(n)
	if seen != cells.size():
		bad.append("в сети маршрутов есть цикл или недостижимые клетки")
	for c in cells:
		if c != finish and out[c].is_empty():
			bad.append("тупик в %s" % c)
	# каждый маршрут отличается от остальных
	if routes.size() > 1:
		for r in routes:
			var own := 0
			for c in r.order:
				if routes_at(c).size() == 1:
					own += 1
			if own == 0:
				bad.append("маршрут %d повторяет другие" % r.id)
	var free := 0
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if not cells.has(Vector2i(x, y)) and not blocked.has(Vector2i(x, y)):
				free += 1
	if free < min_build:
		bad.append("мест под башни %d < %d" % [free, min_build])
	return bad


## Изолированные технические карты прототипа развилки (в обычные забеги не попадают):
##   fork        — один портал, развилка в (3,4), две равные ветки (север и юг, по 21 клетке), слияние в (11,4) перед замком;
##   fork_uneven — короткая северная ветка (19 клеток) и длинная южная (23), слияние в (12,4).
## Скал нет: геометрия задана целиком. Враги идут по веткам по очереди (0, 1, 0, 1, …), если не задан другой план.
const FORK_MAPS := {
	"fork": [
		[Vector2i(0, 4), Vector2i(3, 4), Vector2i(3, 1), Vector2i(11, 1), Vector2i(11, 4), Vector2i(15, 4)],
		[Vector2i(0, 4), Vector2i(3, 4), Vector2i(3, 7), Vector2i(11, 7), Vector2i(11, 4), Vector2i(15, 4)],
	],
	"fork_uneven": [
		[Vector2i(0, 4), Vector2i(5, 4), Vector2i(5, 2), Vector2i(9, 2), Vector2i(9, 4), Vector2i(15, 4)],
		[Vector2i(0, 4), Vector2i(3, 4), Vector2i(3, 8), Vector2i(12, 8), Vector2i(12, 4), Vector2i(15, 4)],
	],
}


static func fork_test(variant: String = "fork", plan: Array[int] = []) -> TDMap:
	var routes_: Array = FORK_MAPS.get(variant, FORK_MAPS["fork"])
	var m := build_routes(0, "Развилка · прототип" if variant != "fork_uneven" else "Развилка · разные длины", routes_, {}, plan)
	m.family = variant if FORK_MAPS.has(variant) else "fork"
	return m


func is_path(x: int, y: int) -> bool:
	return cells.has(Vector2i(x, y))


func is_blocked(x: int, y: int) -> bool:
	return blocked.has(Vector2i(x, y))


## The foundation stays on the final road centreline; never move it vertically to fit.
func castle_layout(field_size: Vector2) -> Dictionary:
	var cell := minf(field_size.x / TDConfig.COLS, field_size.y / TDConfig.ROWS)
	var end: Vector2 = points.back() * cell
	var base := end + Vector2(0.0, cell * 0.05)
	var side := minf(cell * 1.8, base.y - 1.0)
	base.x = clampf(base.x, side * 0.52 + 2.0, field_size.x - side * 0.52 - 2.0)
	var road_end := Vector2(base.x + side * 0.48, end.y)
	return {"base": base, "side": side, "road_end": road_end, "end": end}


static func classic() -> TDMap:
	return build(0, "Классика", CLASSIC_WAYPOINTS)


## Семейства карт: доля и название. Вход всегда на левом краю (строка ≥ 1 под портал), выход на правом (строка ≥ 2 под замок),
## последний участок горизонтальный: от этого зависят портал, замок (`castle_layout`) и путь летающих.
const FAMILIES := [
	{"id": "snake", "name": "", "weight": 0.40},
	{"id": "vsnake", "name": "вертикальная змейка", "weight": 0.20},
	{"id": "stairs", "name": "лесенка", "weight": 0.20},
	{"id": "hooks", "name": "крюки", "weight": 0.20},
]
const MIN_PATH := 36
const MAX_PATH := 90
## Лесенка по геометрии короче; нижняя граница ниже, баланс проверяется ботами (tests/map_check.gd, tests/bot.gd).
const STAIRS_MIN_PATH := 36

var family: String = "snake"


## Семейство карты для сида. Отдельный генератор случайных чисел, чтобы выбор семейства не сдвигал основной поток.
static func family_for(seed_v: int) -> String:
	var r := TDRng.new(seed_v ^ 0x2f6e2b1d).next()
	var acc := 0.0
	for f in FAMILIES:
		acc += float(f["weight"])
		if r < acc:
			return f["id"]
	return "snake"


## Случайная карта по сиду с валидацией (`rasterize`) и скалами. Семейство выбирается по сиду.
static func generate(seed_v: int, forced_family: String = "") -> TDMap:
	var fam := forced_family if forced_family != "" else family_for(seed_v)
	var rng := TDRng.new(seed_v ^ 0x5bd1e995)
	if fam != "snake":
		var m := _generate_family(seed_v, fam, rng)
		if m != null:
			return m
		# не вышло за лимит попыток: прежний путь, детерминированно
		rng = TDRng.new(seed_v ^ 0x5bd1e995)
	var snake := _generate_snake(seed_v, rng)
	snake.family = "snake"
	return snake


static func _generate_family(seed_v: int, fam: String, rng: TDRng) -> TDMap:
	var cols := TDConfig.COLS
	var rows := TDConfig.ROWS
	var label := ""
	for f in FAMILIES:
		if f["id"] == fam:
			label = f["name"]
	var min_len: int = STAIRS_MIN_PATH if fam == "stairs" else MIN_PATH
	for _attempt in 4000:
		var wps: Array[Vector2i] = []
		match fam:
			"vsnake":
				wps = _vsnake(rng, cols, rows)
			"stairs":
				wps = _stairs(rng, cols, rows)
			"hooks":
				wps = _hooks(rng, cols, rows)
		if wps.size() < 2:
			continue
		if wps[0].y < 1 or wps[wps.size() - 1].y < 2 or wps[wps.size() - 1].x != cols - 1:
			continue
		# последний участок горизонтальный, длиной ≥ 3, предыдущая вершина не правее колонки 12
		var prev: Vector2i = wps[wps.size() - 2]
		if prev.y != wps[wps.size() - 1].y or wps[wps.size() - 1].x - prev.x < 3 or prev.x > cols - 4:
			continue
		# и первый участок горизонтальный
		if wps[1].y != wps[0].y or wps[1].x - wps[0].x < 2:
			continue
		var ord := rasterize(wps)
		if ord.is_empty() or ord.size() < min_len or ord.size() > MAX_PATH:
			continue
		var path := {}
		for c in ord:
			path[c] = true
		var m := build(seed_v, "Карта %03d · %s" % [seed_v % 1000, label], wps, _rocks(rng, path, cols, rows))
		m.family = fam
		return m
	return null


## Скалы: 7–13 клеток вне дороги.
static func _rocks(rng: TDRng, path: Dictionary, cols: int, rows: int) -> Dictionary:
	var blocked_ := {}
	var want := _ri(rng, 7, 13)
	var t2 := 0
	while t2 < 200 and blocked_.size() < want:
		var k := Vector2i(_ri(rng, 0, cols - 1), _ri(rng, 0, rows - 1))
		if not path.has(k):
			blocked_[k] = true
		t2 += 1
	return blocked_


## Вертикальная змейка: 3–4 колонки-прохода, вход и выход горизонтальные.
static func _vsnake(rng: TDRng, cols: int, rows: int) -> Array[Vector2i]:
	var lanes: int = 3 if rng.next() < 0.5 else 4
	var xs: Array[int] = [_ri(rng, 2, 4)]
	for _i in range(1, lanes):
		xs.append(xs[xs.size() - 1] + _ri(rng, 2, 4))
	if xs[xs.size() - 1] > cols - 4:
		return []
	var y0 := _ri(rng, 1, rows - 1)
	var wps: Array[Vector2i] = [Vector2i(0, y0)]
	var y := y0
	var down: bool = rng.next() < 0.5 if y0 > 2 and y0 < rows - 3 else y0 <= rows / 2
	for i in lanes:
		wps.append(Vector2i(xs[i], y))
		var ny: int
		if i == lanes - 1:
			# выход: последний проход заканчивается на строке ≥ 2
			ny = _ri(rng, 2, rows - 1)
		elif down:
			ny = _ri(rng, rows - 3, rows - 1)
		else:
			ny = _ri(rng, 0, 2)
		wps.append(Vector2i(xs[i], ny))
		y = ny
		down = not down
	wps.append(Vector2i(cols - 1, y))
	return wps


## Лесенка: ступени вниз, затем вверх (до трёх разворотов); вход сверху.
static func _stairs(rng: TDRng, cols: int, rows: int) -> Array[Vector2i]:
	var y := _ri(rng, 1, 2)
	var wps: Array[Vector2i] = [Vector2i(0, y)]
	var x := _ri(rng, 2, 3)
	var down := true
	var flips := 0
	var max_flips: int = _ri(rng, 2, 3)
	while true:
		wps.append(Vector2i(x, y))
		var b: int = _ri(rng, 2, 4)
		var ny: int = y + (b if down else -b)
		if ny > rows - 1 or ny < 1:
			if flips >= max_flips:
				break
			down = not down
			flips += 1
			ny = clampi(y + (b if down else -b), 1, rows - 1)
		if ny == y:
			break
		wps.append(Vector2i(x, ny))
		y = ny
		var a: int = _ri(rng, 2, 3)
		if x + a > cols - 4:
			break
		x += a
	if y < 2:
		return []
	wps.append(Vector2i(cols - 1, y))
	return wps


## Крюки: почти прямая дорога с тремя U-образными заходами вверх и вниз по очереди.
static func _hooks(rng: TDRng, cols: int, rows: int) -> Array[Vector2i]:
	var y := _ri(rng, 4, 5)
	var wps: Array[Vector2i] = [Vector2i(0, y)]
	var n := 3
	var x: int = _ri(rng, 2, 3)
	var up: bool = rng.next() < 0.5
	for _i in n:
		var h := 4
		var ty: int = y - h if up else y + h
		if ty < 0 or ty > rows - 1:
			return []
		wps.append(Vector2i(x, y))
		wps.append(Vector2i(x, ty))
		wps.append(Vector2i(x + 2, ty))
		wps.append(Vector2i(x + 2, y))
		x += 2 + _ri(rng, 1, 2)
		up = not up
	wps.append(Vector2i(cols - 1, y))
	return wps


## Семейство «змейка»: горизонтальная змейка из 3–5 проходов. Поток rng и результат те же, что у генератора до появления семейств,
## поэтому карты сидов, попавших в это семейство, не изменились.
static func _generate_snake(seed_v: int, rng: TDRng) -> TDMap:
	var cols := TDConfig.COLS
	var rows := TDConfig.ROWS
	var map_name_ := "Карта %03d" % (seed_v % 1000)
	for _attempt in 800:
		var lanes: int = 5 if rng.next() < 0.3 else 3
		var ys: Array[int] = [_ri(rng, 0, rows - 1)]
		var ok := true
		var i := 1
		while i < lanes and ok:
			var y := -1
			var t := 0
			while t < 20 and y < 0:
				var c := _ri(rng, 0, rows - 1)
				if absi(c - ys[i - 1]) >= 2:
					y = c
				t += 1
			if y < 0:
				ok = false
			else:
				ys.append(y)
			i += 1
		if not ok:
			continue
		# The portal sprite needs a row above its road lane, otherwise it is pushed off the lane.
		if ys[0] < 1:
			continue
		# Reserve headroom for the keep rather than moving its entrance off the road.
		if ys.back() < 2:
			continue

		var wps: Array[Vector2i] = [Vector2i(0, ys[0])]
		var x := 0
		for li in lanes:
			var right: bool = li % 2 == 0
			var last: bool = li == lanes - 1
			var nx: int
			if last:
				nx = cols - 1
			elif right:
				nx = _ri(rng, maxi(x + 3, 8), cols - 2)
			else:
				nx = _ri(rng, 1, mini(x - 3, 7))
			wps.append(Vector2i(nx, ys[li]))
			if not last:
				wps.append(Vector2i(nx, ys[li + 1]))
			x = nx

		var ord := rasterize(wps)
		if ord.is_empty() or ord.size() < 36 or ord.size() > 90:
			continue

		var path := {}
		for c in ord:
			path[c] = true
		var blocked_ := {}
		var want := _ri(rng, 7, 13)
		var t2 := 0
		while t2 < 200 and blocked_.size() < want:
			var k := Vector2i(_ri(rng, 0, cols - 1), _ri(rng, 0, rows - 1))
			if not path.has(k):
				blocked_[k] = true
			t2 += 1
		return build(seed_v, map_name_, wps, blocked_)
	return build(seed_v, map_name_ + " (классика)", CLASSIC_WAYPOINTS)


static func _ri(rng: TDRng, a: int, b: int) -> int:
	return a + int(floor(rng.next() * (b - a + 1)))
