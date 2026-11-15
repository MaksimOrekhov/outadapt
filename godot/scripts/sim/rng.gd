class_name TDRng
extends RefCounted
## mulberry32: детерминированный генератор, при одинаковом сиде даёт те же числа.

const M := 0xFFFFFFFF

var a: int


func _init(seed_value: int) -> void:
	a = seed_value & M


func next() -> float:
	a = (a + 0x6d2b79f5) & M
	var t: int = a
	t = ((t ^ (t >> 15)) * (t | 1)) & M
	var t2: int = ((t ^ (t >> 7)) * (t | 61)) & M
	t = (t ^ ((t + t2) & M)) & M
	return float((t ^ (t >> 14)) & M) / 4294967296.0


func gauss() -> float:
	var u: float = maxf(next(), 1e-9)
	var v: float = next()
	return sqrt(-2.0 * log(u)) * cos(2.0 * PI * v)
