class_name FxAssassinThrownDagger
extends RefCounted

## ASSASSIN_THROWN_DAGGER (78): a wrist flick, drawn from the Assassin
## (`pos`) to where the knife lands (`target`). A dagger tumbles end over
## end along a shallow arc, a thin violet slipstream peeling off behind it
## with two whistle lines; it bites in at the end with a glint and a small
## violet puff, and the slipstream thins away.

const VIOLET := Color("9a5cd8")
const SHADE := Color("3a1c58")
const STEEL := Color("dfe4ee")
const HILT := Color("6a4028")
const FLIGHT := 0.55


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx)
	var span := to - from
	var dir := span.normalized() if span.length() > 1.0 else Vector2.RIGHT
	var lift := span.length() * 0.12
	var flight := FxKit.ease_out(FxKit.phase(progress, 0.0, FLIGHT))
	_slipstream(canvas, from, to, dir, lift, flight, progress)
	if progress < FLIGHT:
		var at := _arc_point(from, to, dir, lift, flight)
		var spin := progress * TAU * 3.0
		_dagger(canvas, at, spin, 1.0)
	else:
		_dagger(canvas, to - dir * 3.0, dir.angle() + PI, 1.0 - FxKit.phase(progress, 0.75, 1.0))
		_bite(canvas, fx, to, dir, progress)


## A point on the shallow throwing arc, `f` 0..1 along it.
static func _arc_point(from: Vector2, to: Vector2, dir: Vector2, lift: float, f: float) -> Vector2:
	var bow := -dir.orthogonal() if dir.x >= 0.0 else dir.orthogonal()
	return from.lerp(to, f) + bow * lift * 4.0 * f * (1.0 - f)


## The knife: a steel blade one way, a short hilt and guard the other.
static func _dagger(canvas: CanvasItem, at: Vector2, angle: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var along := Vector2(cos(angle), sin(angle))
	var across := along.orthogonal()
	var tip := at + along * 12.0
	var guard := at - along * 2.0
	Fx.polygon(canvas, [tip, guard + across * 3.0, guard - across * 3.0], Color(STEEL, alpha))
	Fx.line(canvas, guard + across * 3.5, guard - across * 3.5, 3.0, Color(VIOLET, alpha))
	Fx.line(canvas, guard, guard - along * 6.0, 5.0, Color(HILT, alpha))
	Fx.line(canvas, at, tip, 1.0, Color(Color.WHITE, alpha * 0.9))


## The violet wake along the travelled arc, with two whistle lines either
## side of its newest stretch; thinning after the knife lands.
static func _slipstream(canvas: CanvasItem, from: Vector2, to: Vector2, dir: Vector2, lift: float,
		flight: float, progress: float) -> void:
	var tail := FxKit.ease_in(FxKit.phase(progress, 0.2, 0.85))
	if flight <= tail:
		return
	var points := PackedVector2Array()
	var steps := 14
	for i in steps + 1:
		points.append(_arc_point(from, to, dir, lift, lerpf(tail, flight, float(i) / steps)))
	var fade := 1.0 - FxKit.phase(progress, 0.6, 1.0)
	Fx.polyline(canvas, points, 6.0, Color(SHADE, 0.45 * fade))
	Fx.polyline(canvas, points, 2.5, Color(VIOLET, 0.8 * fade))
	if progress < FLIGHT:
		var head := _arc_point(from, to, dir, lift, flight)
		var back := _arc_point(from, to, dir, lift, maxf(tail, flight - 0.25))
		var side := (head - back).normalized().orthogonal() * 5.0
		for s: float in [-1.0, 1.0]:
			Fx.line(canvas, back + side * s, head - (head - back) * 0.3 + side * s, 1.5, Color(STEEL, 0.6))


## The knife biting home: a glint, a small ring and a violet puff.
static func _bite(canvas: CanvasItem, fx: Dictionary, at: Vector2, dir: Vector2, progress: float) -> void:
	var t := FxKit.phase(progress, FLIGHT, 0.95)
	var flash := 1.0 - FxKit.phase(progress, FLIGHT, FLIGHT + 0.2)
	FxKit.glint(canvas, at, 14.0 * flash, 0.4, STEEL, flash)
	Fx.ring(canvas, at, 4.0 + 10.0 * FxKit.ease_out(t), 2.0, Color(VIOLET, (1.0 - t) * 0.8))
	FxKit.sparks(canvas, at, -dir, 2.4, 6, 14.0, t, 4.0, 2.0, VIOLET, 0.9, FxKit.seed_of(fx))
