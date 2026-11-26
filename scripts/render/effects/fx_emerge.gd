class_name FxEmerge
extends RefCounted

## EMERGE (73): the ground heaving open for something to climb out. A dark
## pit widens over the first 30% with cracks splitting out from it, dirt
## clods are thrown up and fall back on arcs, and a mound of churned earth
## rings the hole and settles as dust drifts off it.

const PIT := Color("100804")
const EARTH := Color("5a3e24")
const CLOD := Color("7a5634")
const DUST := Color("b89870")
const OPEN_END := 0.3
const CLODS := 10
const CRACKS := 6


static func pit_radius(radius: float, progress: float) -> float:
	return radius * 0.55 * ease(minf(1.0, progress / OPEN_END), 0.4)


## A clod's lift off the ground: one arc up and back down over its flight.
static func lift(flight: float, height: float) -> float:
	return height * 4.0 * flight * (1.0 - flight)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var alpha := 1.0 - clampf((progress - 0.7) / 0.3, 0.0, 1.0)
	var pit := pit_radius(radius, progress)
	var rng := Fx.rng_for(fx, 0)
	for i in CRACKS:
		var angle := i * TAU / CRACKS + rng.randf_range(-0.3, 0.3)
		var bend := angle + rng.randf_range(-0.4, 0.4)
		var reach := radius * minf(1.0, progress / OPEN_END) * rng.randf_range(0.7, 1.0)
		var mid := Fx.polar(at, angle, reach * 0.5)
		Fx.polyline(canvas, PackedVector2Array([at, mid, Fx.polar(mid, bend, reach * 0.5)]), 3.0, Color(PIT, alpha * 0.8))
	CircleStamp.disc(canvas, at, pit * 1.45, Color(EARTH, alpha * 0.85))
	CircleStamp.disc(canvas, at, pit * 1.2, Color(CLOD, alpha * 0.6))
	CircleStamp.disc(canvas, at, pit, Color(PIT, alpha))
	for i in CLODS:
		var flight := clampf((progress - 0.05 - i * 0.012) / 0.55, 0.0, 1.0)
		if flight <= 0.0 or flight >= 1.0:
			continue
		var angle := i * TAU / CLODS + rng.randf_range(-0.25, 0.25)
		var ground := Fx.polar(at, angle, pit + radius * 0.6 * flight)
		var clod := ground - Vector2(0.0, lift(flight, radius * 0.9))
		var size := (3.0 + (i % 3)) * Fx.S * 2.8
		var turn := elapsed_ms * 0.01 + i
		Fx.polygon(canvas, [clod + Vector2(cos(turn), sin(turn)) * size, clod + Vector2(cos(turn + 2.1), sin(turn + 2.1)) * size,
			clod + Vector2(cos(turn + 4.2), sin(turn + 4.2)) * size], Color(CLOD, alpha))
	if progress > 0.4:
		var drift := (progress - 0.4) / 0.6
		for i in 8:
			var puff := Fx.polar(at, i * TAU / 8.0 + 0.3, pit * 1.5) - Vector2(0.0, drift * radius * 0.4)
			CircleStamp.disc(canvas, puff, radius * 0.18 * (1.0 + drift), Color(DUST, (1.0 - drift) * 0.35))
