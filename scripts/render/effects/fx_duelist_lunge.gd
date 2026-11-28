class_name FxDuelistLunge
extends RefCounted

## DUELIST_LUNGE (84): a fencer's fleche, drawn from where the Duelist set
## off (`pos`) to where the point lands (`target`). Four gilded afterimages
## of the lunging figure trail along the path while a tapered streak races
## to the strike. Then the point pierces: a needle of light punches through
## past the strike, a turning glint flares, a thin ring snaps out and steel
## chips spray forward. Two skid marks are left on the ground behind.

const GOLD := Color("f4d27a")
const IVORY := Color("fff6e0")
const STEEL := Color("c9d3de")
const SHADOW := Color("2a1c10")
const AFTERIMAGES := 4


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx)
	var span := to - from
	var dir := span.normalized() if span.length() > 1.0 else Vector2.RIGHT
	var size: float = clampf(fx["radius"], 24.0, 96.0)
	var fade := 1.0 - FxKit.phase(progress, 0.6, 1.0)
	_skids(canvas, from, to, dir, progress, fade)
	_afterimages(canvas, from, to, dir, progress)
	_streak(canvas, from, to, dir, progress, size)
	_pierce(canvas, fx, to, dir, size, progress)


## Two scuffed lines on the ground from the push-off, fading last.
static func _skids(canvas: CanvasItem, from: Vector2, to: Vector2, dir: Vector2, progress: float,
		fade: float) -> void:
	var side := dir.orthogonal() * 4.0
	var reach := from.lerp(to, FxKit.ease_out(FxKit.phase(progress, 0.0, 0.3)) * 0.85)
	for s: float in [-1.0, 1.0]:
		Fx.line(canvas, from + side * s, reach + side * s * 0.4, 2.0, Color(SHADOW, 0.35 * fade))


## Ghosts of the lunging figure, each a head and a forward-held blade,
## left behind at even steps and fading oldest first.
static func _afterimages(canvas: CanvasItem, from: Vector2, to: Vector2, dir: Vector2, progress: float) -> void:
	var travel := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.3))
	for i in AFTERIMAGES:
		var at_step := float(i + 1) / float(AFTERIMAGES + 1)
		if at_step > travel:
			break
		var age := FxKit.phase(progress, at_step * 0.3, at_step * 0.3 + 0.45)
		var alpha := (1.0 - age) * (0.35 + 0.15 * i)
		var body := from.lerp(to, at_step) - dir * 6.0
		Fx.dot(canvas, body - Vector2(0.0, 7.0), 7.0, Color(GOLD, alpha * 0.55))
		Fx.line(canvas, body + Vector2(0.0, -2.0), body + Vector2(0.0, 7.0), 6.0, Color(GOLD, alpha * 0.45))
		Fx.line(canvas, body, body + dir * 16.0, 1.5, Color(IVORY, alpha))


## The streak: a gold wedge thin at the head, racing to the strike in the
## first 30% and burning off after.
static func _streak(canvas: CanvasItem, from: Vector2, to: Vector2, dir: Vector2, progress: float,
		size: float) -> void:
	var head_t := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.3))
	var tail_t := FxKit.ease_in(FxKit.phase(progress, 0.15, 0.55))
	if head_t <= tail_t:
		return
	var head := from.lerp(to, head_t)
	var tail := from.lerp(to, tail_t)
	var width := size * 0.22
	FxKit.taper(canvas, tail, head, width, 0.0, Color(GOLD, 0.35))
	FxKit.taper(canvas, tail, head, width * 0.45, 0.0, Color(IVORY, 0.75))
	Fx.line(canvas, tail, head + dir * 4.0, 1.5, Color(Color.WHITE, 0.95))


## The touch: a needle through the strike, a turning glint, a ring and chips.
static func _pierce(canvas: CanvasItem, fx: Dictionary, at: Vector2, dir: Vector2, size: float,
		progress: float) -> void:
	var hit := FxKit.pulse(progress, 0.24, 0.32, 0.8)
	if hit <= 0.0:
		return
	var needle := FxKit.ease_out(FxKit.phase(progress, 0.24, 0.4))
	FxKit.glow_line(canvas, at - dir * size * 0.35, at + dir * size * (0.3 + 0.7 * needle), 3.0, GOLD, hit)
	var spin := progress * PI * 1.5
	FxKit.glint(canvas, at, size * (0.35 + 0.5 * hit), spin, IVORY, hit)
	var ring_t := FxKit.phase(progress, 0.28, 0.75)
	Fx.ring(canvas, at, size * (0.15 + 0.6 * FxKit.ease_out(ring_t)), 2.0, Color(GOLD, (1.0 - ring_t) * 0.8))
	FxKit.sparks(canvas, at, dir, 1.1, 7, size * 0.9, FxKit.phase(progress, 0.28, 0.85), 10.0, 1.5,
		STEEL, 1.0, FxKit.seed_of(fx))
