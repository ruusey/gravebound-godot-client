class_name FxKit
extends RefCounted

## Timing and stroke helpers the class ability drawers share: windows of an
## effect's life, easing, tapered strokes, glowing lines and stars, sparks.
## Like Fx, everything here is pure: no state between frames.

## One generator reseeded per call, so a scatter allocates nothing per frame.
static var _rng := RandomNumberGenerator.new()


## How far through the window [start, end] `progress` is, 0 before and 1 after.
static func phase(progress: float, start: float, end: float) -> float:
	return clampf((progress - start) / maxf(0.0001, end - start), 0.0, 1.0)


## 1 inside [start, end], fading in over `edge` before it and out over `edge` after.
static func window(progress: float, start: float, end: float, edge := 0.08) -> float:
	return phase(progress, start - edge, start) * (1.0 - phase(progress, end, end + edge))


static func ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)


static func ease_in(t: float) -> float:
	return t * t * t


static func ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## A quick swell to 1 and a slower fall back to 0 over the window: a flash.
static func pulse(progress: float, start: float, peak: float, end: float) -> float:
	if progress <= start or progress >= end:
		return 0.0
	if progress < peak:
		return phase(progress, start, peak)
	return 1.0 - phase(progress, peak, end)


## A filled wedge from `from` (width_from across) to `to` (width_to across):
## a blade, a flame tongue, a brush stroke.
static func taper(canvas: CanvasItem, from: Vector2, to: Vector2, width_from: float, width_to: float,
		colour: Color) -> void:
	if colour.a <= 0.001 or from.distance_to(to) < 0.01:
		return
	var across := (to - from).normalized().orthogonal()
	var points := PackedVector2Array([from + across * width_from * 0.5, to + across * width_to * 0.5,
		to - across * width_to * 0.5, from - across * width_from * 0.5])
	if width_to <= 0.01:
		points = PackedVector2Array([from + across * width_from * 0.5, to, from - across * width_from * 0.5])
	canvas.draw_colored_polygon(points, colour)


## A line with a soft halo: a wide faint stroke, a mid stroke in colour, a white core.
static func glow_line(canvas: CanvasItem, from: Vector2, to: Vector2, width_px: float, colour: Color,
		alpha: float) -> void:
	Fx.line(canvas, from, to, width_px * 3.0, Color(colour, alpha * 0.18))
	Fx.line(canvas, from, to, width_px * 1.6, Color(colour, alpha * 0.55))
	Fx.line(canvas, from, to, width_px * 0.6, Color(Color.WHITE, alpha * 0.9))


## A polyline with the same soft halo as glow_line.
static func glow_path(canvas: CanvasItem, points: PackedVector2Array, width_px: float, colour: Color,
		alpha: float) -> void:
	Fx.polyline(canvas, points, width_px * 3.0, Color(colour, alpha * 0.18))
	Fx.polyline(canvas, points, width_px * 1.6, Color(colour, alpha * 0.55))
	Fx.polyline(canvas, points, width_px * 0.6, Color(Color.WHITE, alpha * 0.9))


## A glint: a four-point star `size` across with a halo disc behind it.
static func glint(canvas: CanvasItem, at: Vector2, size: float, angle: float, colour: Color, alpha: float) -> void:
	# Under a pixel the star's points collapse and the polygon will not triangulate.
	if alpha <= 0.001 or size < 1.0:
		return
	CircleStamp.disc(canvas, at, size * 0.45, Color(colour, alpha * 0.25))
	Fx.polygon(canvas, FxBladeShapes.star(at, angle, size), Color(colour, alpha * 0.8))
	Fx.polygon(canvas, FxBladeShapes.star(at, angle, size * 0.55), Color(Color.WHITE, alpha))


## `count` sparks flung from `at` within `spread` radians of `dir`, each
## flying `reach` as `t` runs 0..1 and dropping under `gravity`; a stable
## scatter seeded from `seed`.
static func sparks(canvas: CanvasItem, at: Vector2, dir: Vector2, spread: float, count: int, reach: float,
		t: float, gravity: float, width_px: float, colour: Color, alpha: float, seed: int) -> void:
	if alpha <= 0.001 or t <= 0.0 or t >= 1.0:
		return
	var rng := rng_seeded(seed)
	for i in count:
		var heading := dir.rotated(rng.randf_range(-spread, spread) * 0.5)
		var speed := reach * rng.randf_range(0.55, 1.0)
		var head := at + heading * speed * ease_out(t) + Vector2(0.0, gravity * t * t)
		var tail := at + heading * speed * ease_out(maxf(0.0, t - 0.18)) + Vector2(0.0, gravity * maxf(0.0, t - 0.18) * maxf(0.0, t - 0.18))
		Fx.line(canvas, tail, head, width_px, Color(colour, alpha * (1.0 - t)))
		Fx.dot(canvas, head, width_px * 0.8, Color(Color.WHITE, alpha * (1.0 - t)))


## The shared generator, reseeded: the same seed rolls the same numbers in the same order.
static func rng_seeded(seed: int) -> RandomNumberGenerator:
	_rng.seed = seed
	return _rng


## A stable per-effect seed: the same effect draws the same scatter every frame.
static func seed_of(fx: Dictionary) -> int:
	return hash([int(fx.get("started", 0)), fx.get("pos", Vector2.ZERO), int(fx.get("type", 0))])


## The far end of a LINE effect, or `pos` plus `fallback` along +X when it has none.
static func line_end(fx: Dictionary, fallback := 48.0) -> Vector2:
	var target: Vector2 = fx.get("target", Vector2.ZERO)
	return target if target != Vector2.ZERO else fx["pos"] + Vector2(fallback, 0.0)
