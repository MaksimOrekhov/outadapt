class_name TDPath
extends RefCounted
## PRO-139: один маршрут — полилиния по центрам клеток от портала до замка.
## Карта с одним путём — это ровно один TDPath (TDMap.routes[0]); на карте с развилкой маршрутов несколько,
## и на общих участках их точки совпадают. Арифметика та же, что была в TDMap до PRO-139.

var id: int = 0
var waypoints: Array[Vector2i] = []
var points: Array[Vector2] = []
var seg_len: Array[float] = []
var length: float = 0.0
## Прямая «по воздуху» от входа этого маршрута до замка.
var fly_length: float = 0.0
## Клетки маршрута по порядку.
var order: Array[Vector2i] = []


static func from_waypoints(id_: int, wps: Array[Vector2i]) -> TDPath:
	var p := TDPath.new()
	p.id = id_
	p.waypoints = wps
	for w in wps:
		p.points.append(Vector2(w.x + 0.5, w.y + 0.5))
	for i in range(1, p.points.size()):
		var l: float = p.points[i].distance_to(p.points[i - 1])
		p.seg_len.append(l)
		p.length += l
	p.fly_length = p.points[0].distance_to(p.points[p.points.size() - 1])
	p.order = TDMap.rasterize(wps)
	return p


func pos_at(dist: float) -> Vector2:
	var d: float = maxf(0.0, minf(dist, length))
	for i in seg_len.size():
		if d <= seg_len[i]:
			var t: float = 0.0 if seg_len[i] == 0.0 else d / seg_len[i]
			return points[i].lerp(points[i + 1], t)
		d -= seg_len[i]
	return points[points.size() - 1]


## Позиция летающего: по прямой от входа к выходу.
func fly_pos_at(dist: float) -> Vector2:
	var t: float = 1.0 if fly_length == 0.0 else clampf(dist / fly_length, 0.0, 1.0)
	return points[0].lerp(points[points.size() - 1], t)


## Направление пути в точке. Для движения по воздуху используется прямая от входа к выходу.
func heading_at(dist: float, flying: bool = false) -> Vector2:
	if flying:
		return (points[points.size() - 1] - points[0]).normalized()
	var d := clampf(dist, 0.0, length)
	for i in seg_len.size():
		# На вершине используем следующий сегмент, как только враг начинает поворот.
		if d < seg_len[i]:
			return (points[i + 1] - points[i]).normalized()
		d -= seg_len[i]
	return (points[points.size() - 1] - points[points.size() - 2]).normalized()


## Сколько пути от начала маршрута до центра клетки c (-1 — клетки нет на маршруте).
func dist_to_cell(c: Vector2i) -> float:
	var acc := 0.0
	for i in range(1, waypoints.size()):
		var a: Vector2i = waypoints[i - 1]
		var b: Vector2i = waypoints[i]
		var on := (a.x == b.x and c.x == a.x and c.y >= mini(a.y, b.y) and c.y <= maxi(a.y, b.y)) \
			or (a.y == b.y and c.y == a.y and c.x >= mini(a.x, b.x) and c.x <= maxi(a.x, b.x))
		if on:
			return acc + Vector2(a).distance_to(Vector2(c))
		acc += seg_len[i - 1]
	return -1.0
