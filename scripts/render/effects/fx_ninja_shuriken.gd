class_name FxNinjaShuriken
extends RefCounted

## NINJA_SHURIKEN (102): a throwing star loosed as one stroke of a calligraphy
## brush, from the Ninja (`pos`) to where it flies (`target`). A swelling ink
## stroke on a pale wash races out with a thin crimson vein down its middle,
## dry-brush bristle streaks trailing off its edges, and at its head the
## outline of a four-point star spins in ink and white. The stroke dries
## from the tail and flicks ink droplets, some crimson, off its far end.

const INK := Color("16111c")
const WASH := Color("ece6da")
const CRIMSON := Color("d02040")
const TRAVEL := 0.35


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx)
	var span := to - from
	var dir := span.normalized() if span.length() > 1.0 else Vector2.RIGHT
	var size: float = clampf(fx["radius"], 12.0, 48.0)
	var head_t := FxKit.ease_out(FxKit.phase(progress, 0.0, TRAVEL))
	var tail_t := FxKit.ease_in(FxKit.phase(progress, 0.25, 0.95))
	var fade := 1.0 - FxKit.phase(progress, 0.6, 0.88)
	_stroke(canvas, from, span, dir, size, head_t, tail_t, fade)
	_droplets(canvas, to, dir, size, progress, FxKit.seed_of(fx))
	_star(canvas, from + span * head_t, size, progress, fade)


## Where the stroke runs `f` of the way along: a shallow S-curve across.
static func _along(from: Vector2, span: Vector2, dir: Vector2, size: float, f: float) -> Vector2:
	return from + span * f + dir.orthogonal() * sin(f * TAU) * size * 0.18


## The brush stroke: a pale wash under a swelling ink body, bristle streaks
## off its edges and a crimson vein down its spine.
static func _stroke(canvas: CanvasItem, from: Vector2, span: Vector2, dir: Vector2, size: float, head_t: float,
		tail_t: float, fade: float) -> void:
	if head_t <= tail_t or fade <= 0.0:
		return
	var steps := 14
	var wash := PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in steps + 1:
		var f := lerpf(tail_t, head_t, float(k) / steps)
		var centre := _along(from, span, dir, size, f)
		var swell := sin(clampf((f - tail_t) / maxf(0.001, head_t - tail_t), 0.0, 1.0) * PI)
		var half := size * (0.08 + 0.32 * swell)
		var across := dir.orthogonal()
		left.append(centre + across * half)
		right.append(centre - across * half)
		wash.append(centre)
	var outline := left.duplicate()
	var back := right.duplicate()
	back.reverse()
	outline.append_array(back)
	Fx.polyline(canvas, wash, size * 1.25, Color(WASH, 0.3 * fade))
	canvas.draw_colored_polygon(outline, Color(INK, 0.92 * fade))
	Fx.polyline(canvas, left, 2.0, Color(WASH, 0.55 * fade))
	Fx.polyline(canvas, wash, 3.0, Color(CRIMSON, 0.9 * fade))
	for s: float in [-1.0, 1.0]:
		var bristle := PackedVector2Array()
		for k in 6:
			var f := lerpf(tail_t, tail_t + (head_t - tail_t) * 0.45, float(k) / 5.0)
			bristle.append(_along(from, span, dir, size, f) + dir.orthogonal() * s * size * (0.42 + 0.05 * k))
		Fx.polyline(canvas, bristle, 2.0, Color(INK, 0.6 * fade))


## The star at the stroke's head: an ink outline and a white one inside it,
## spinning hard, gone once the stroke has landed.
static func _star(canvas: CanvasItem, at: Vector2, size: float, progress: float, fade: float) -> void:
	var alpha := (1.0 - FxKit.phase(progress, TRAVEL, TRAVEL + 0.25)) * fade
	if alpha <= 0.0:
		return
	var spin := progress * 26.0
	var star := size * 1.4
	Fx.polygon(canvas, FxBladeShapes.star(at, spin, star * 1.15), Color(INK, alpha * 0.85))
	FxBladeShapes.outline(canvas, FxBladeShapes.star(at, spin, star), 3.0, Color(Color.WHITE, alpha))
	CircleStamp.disc(canvas, at, star * 0.08, Color(CRIMSON, alpha))


## Ink flicked off the far end as the stroke lands: droplets flung forward
## and falling, every third one crimson, each leaving a small blot.
static func _droplets(canvas: CanvasItem, at: Vector2, dir: Vector2, size: float, progress: float,
		seed: int) -> void:
	var t := FxKit.phase(progress, TRAVEL - 0.05, 0.9)
	if t <= 0.0 or t >= 1.0:
		return
	var rng := FxKit.rng_seeded(seed)
	for i in 9:
		var heading := dir.rotated(rng.randf_range(-0.9, 0.9))
		var reach := size * rng.randf_range(0.6, 1.8)
		var drop := size * rng.randf_range(0.06, 0.14)
		var spot := at + heading * reach * FxKit.ease_out(t) + Vector2(0.0, size * 0.5 * t * t)
		var colour := CRIMSON if i % 3 == 0 else INK
		CircleStamp.disc(canvas, spot, drop + 1.0, Color(WASH, (1.0 - t) * 0.35))
		CircleStamp.disc(canvas, spot, drop, Color(colour, 1.0 - t * t))
