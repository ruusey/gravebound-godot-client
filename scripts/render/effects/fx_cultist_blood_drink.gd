class_name FxCultistBloodDrink
extends RefCounted

## CULTIST_BLOOD_DRINK (107): the Cultist drinks deep, following them. A
## dark pool of blood spreads at their feet, rippling, and a blood-red
## crescent moon rises over their head in a crimson haze. Five streams of
## blood spiral in from far out, each a dark ribbon with a bright head,
## and pour into the body; as the last arrives the body glows and a pale
## crimson pulse rings out -- the drink taken -- before it all fades.

const BLOOD := Color("9a0c1c")
const BLOOD_DARK := Color("2a0008")
const HOT := Color("ff4058")
const MOON := Color("e8384e")
const MOON_LIT := Color("ffd6dc")
const STREAMS := 5
const ARRIVE := 0.7


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var fade := 1.0 - FxKit.phase(progress, 0.82, 1.0)
	_pool(canvas, at + Vector2(0.0, radius * 0.3), radius, progress, fade, elapsed_ms)
	_streams(canvas, at, radius, progress)
	_drink(canvas, at, radius, progress)
	_moon(canvas, at + Vector2(0.0, -radius * 1.05), radius, progress, fade)


## A flat dark pool spreading under the feet, a crimson sheen on its rim
## and a ripple running out of it every so often.
static func _pool(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float,
		elapsed_ms: int) -> void:
	var spread := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.35))
	if spread <= 0.0:
		return
	var size := radius * 0.75 * spread
	canvas.draw_set_transform(at, 0.0, Vector2(1.0, 0.42))
	CircleStamp.disc(canvas, Vector2.ZERO, size * 1.1, Color(BLOOD, fade * 0.45))
	CircleStamp.disc(canvas, Vector2.ZERO, size, Color(BLOOD_DARK, fade * 0.9))
	var ripple := fmod(elapsed_ms * 0.0012, 1.0)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_ellipse_ring(canvas, at, size * (0.3 + 0.7 * ripple), 0.42, 3.0, Color(HOT, fade * 0.6 * (1.0 - ripple)))
	_ellipse_ring(canvas, at, size * 0.95, 0.42, 2.0, Color(BLOOD, fade * 0.9))


static func _ellipse_ring(canvas: CanvasItem, at: Vector2, size: float, squash: float, width_px: float,
		colour: Color) -> void:
	if colour.a <= 0.001 or size <= 0.5:
		return
	var points := PackedVector2Array()
	for k in 25:
		var angle := TAU * k / 24.0
		points.append(at + Vector2(cos(angle) * size, sin(angle) * size * squash))
	Fx.polyline(canvas, points, width_px, colour)


## Five streams spiralling in from far out to the body, each laid down from
## its outer end, head bright, the tail draining in behind it.
static func _streams(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	for i in STREAMS:
		var start := 0.08 + i * 0.05
		var head_t := FxKit.ease_in_out(FxKit.phase(progress, start, start + 0.4))
		var tail_t := FxKit.ease_in(FxKit.phase(progress, start + 0.12, ARRIVE + 0.04))
		if head_t <= tail_t:
			continue
		var origin := TAU * i / STREAMS - PI * 0.3
		var points := PackedVector2Array()
		var steps := 12
		for k in steps + 1:
			var f := lerpf(tail_t, head_t, float(k) / steps)
			points.append(_spiral(at, radius, origin, f))
		Fx.polyline(canvas, points, 9.0, Color(BLOOD_DARK, 0.7))
		Fx.polyline(canvas, points, 5.0, Color(BLOOD, 1.0))
		Fx.polyline(canvas, points, 1.5, Color(HOT, 0.9))
		var head := points[points.size() - 1]
		CircleStamp.disc(canvas, head, 4.0, Color(HOT, 1.0))
		CircleStamp.disc(canvas, head, 1.8, Color(MOON_LIT, 1.0))


## A point `f` of the way along a stream: starting 1.7 radii out at
## `origin` and winding three quarters of a turn into the body.
static func _spiral(at: Vector2, radius: float, origin: float, f: float) -> Vector2:
	return Fx.polar(at, origin + f * PI * 1.5, radius * 1.7 * (1.0 - f) + radius * 0.08)


## The drink taken: the body swells with a crimson glow as the streams pour
## in, and a pale pulse rings out when the last arrives.
static func _drink(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var fill := FxKit.phase(progress, 0.3, ARRIVE) * (1.0 - FxKit.phase(progress, 0.85, 1.0))
	CircleStamp.disc(canvas, at, radius * (0.25 + 0.25 * fill), Color(HOT, fill * 0.45))
	var t := FxKit.phase(progress, ARRIVE, 0.98)
	if t <= 0.0 or t >= 1.0:
		return
	Fx.ring(canvas, at, radius * (0.3 + 1.0 * FxKit.ease_out(t)), 10.0 * (1.0 - t) + 2.0, Color(MOON_LIT, (1.0 - t) * 0.9))
	Fx.ring(canvas, at, radius * (0.25 + 0.8 * FxKit.ease_out(t)), 4.0, Color(HOT, 1.0 - t))


## The crescent: rising and fading in over the first quarter, a crimson
## haze behind it, horns tilted up and to the left.
static func _moon(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var rise := FxKit.ease_out(FxKit.phase(progress, 0.05, 0.3))
	if rise <= 0.0:
		return
	var size := clampf(radius * 0.38, 9.0, 22.0)
	var centre := at + Vector2(0.0, size * 0.8 * (1.0 - rise))
	var alpha := rise * fade
	CircleStamp.disc(canvas, centre, size * 1.5, Color(MOON, alpha * 0.2))
	var outer: Array = []
	var inner: Array = []
	var tilt := -0.5
	for k in 13:
		var angle := -PI * 0.5 + PI * k / 12.0
		outer.append(centre + Vector2(cos(angle) * size, sin(angle) * size).rotated(tilt))
		inner.append(centre + Vector2(cos(angle) * size * 0.35, sin(angle) * size * 0.92).rotated(tilt))
	inner.reverse()
	var shape: Array = outer + inner
	Fx.polygon(canvas, shape, Color(MOON, alpha))
	Fx.polyline(canvas, PackedVector2Array(outer), 2.5, Color(MOON_LIT, alpha * 0.9))
