class_name FxTrapperBolas
extends RefCounted

## TRAPPER_BOLAS (87): whirling bolas from the Trapper (`pos`) to `target`.
## Two stone weights on a rope spin round their middle as they fly, the
## weights' paths leaving faint looping trails; at the target the rope
## wraps tight -- the weights spiral in round the foe in a shrinking coil --
## and a few rope coils hold there, cinched, with a little dust kicked up.

const ROPE := Color("c8a060")
const DARK := Color("4a3018")
const STONE := Color("8a8478")
const LIGHT := Color("e8dcc0")
const FLIGHT := 0.45


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx)
	var size: float = clampf(fx["radius"], 16.0, 40.0)
	if progress < FLIGHT:
		_flying(canvas, from, to, size, progress / FLIGHT)
	else:
		_wrap(canvas, fx, to, size, (progress - FLIGHT) / (1.0 - FLIGHT))


## In flight: the pair whirling round their middle, the trail of each
## weight's last half-turn behind it.
static func _flying(canvas: CanvasItem, from: Vector2, to: Vector2, size: float, t: float) -> void:
	var centre := from.lerp(to, FxKit.ease_out(t))
	var spin := t * TAU * 3.0
	var half := size * 0.55
	for w in 2:
		var trail := PackedVector2Array()
		for s in 7:
			var back := float(s) / 6.0
			var tt := maxf(0.0, t - back * 0.12)
			var c := from.lerp(to, FxKit.ease_out(tt))
			trail.append(Fx.polar(c, tt * TAU * 3.0 + w * PI, half))
		Fx.polyline(canvas, trail, 2.0, Color(LIGHT, 0.4))
	var a := Fx.polar(centre, spin, half)
	var b := Fx.polar(centre, spin + PI, half)
	_rope(canvas, a, b)
	_weight(canvas, a, 1.0)
	_weight(canvas, b, 1.0)


## Wrapping: the weights spiral in round the target, the rope following,
## then the cinched coils hold and fade.
static func _wrap(canvas: CanvasItem, fx: Dictionary, at: Vector2, size: float, t: float) -> void:
	var cinch := FxKit.ease_out(FxKit.phase(t, 0.0, 0.35))
	var fade := 1.0 - FxKit.phase(t, 0.6, 1.0)
	var loop := size * (0.9 - 0.45 * cinch)
	var coils := PackedVector2Array()
	var turns := 1.0 + 1.5 * cinch
	var steps := 36
	var spin := cinch * TAU * 2.0
	for i in steps + 1:
		var f := float(i) / steps
		var angle := spin - f * TAU * turns
		var r := loop * (1.0 + 0.25 * (1.0 - f))
		coils.append(at + Vector2(cos(angle) * r, sin(angle) * r * 0.45 + (f - 0.5) * size * 0.35))
	Fx.polyline(canvas, coils, 5.0, Color(DARK, 0.7 * fade))
	Fx.polyline(canvas, coils, 2.5, Color(ROPE, fade))
	if fade > 0.0:
		_weight(canvas, coils[0], fade)
		_weight(canvas, coils[steps], fade)
	var snap := FxKit.pulse(t, 0.25, 0.32, 0.5)
	Fx.ring(canvas, at, size * (0.6 + 0.4 * snap), 2.0, Color(LIGHT, snap))
	FxKit.sparks(canvas, at + Vector2(0.0, size * 0.3), Vector2.UP, PI * 1.4, 6, size * 0.8,
		FxKit.phase(t, 0.25, 0.8), 6.0, 2.5, Color("b09070"), 0.8, FxKit.seed_of(fx))


static func _rope(canvas: CanvasItem, a: Vector2, b: Vector2) -> void:
	var sag := (b - a).orthogonal().normalized() * 3.0
	var points := PackedVector2Array([a, a.lerp(b, 0.5) + sag, b])
	Fx.polyline(canvas, points, 4.0, Color(DARK, 0.8))
	Fx.polyline(canvas, points, 2.0, Color(ROPE, 1.0))


## A round stone weight with a dark rim and a lit cap.
static func _weight(canvas: CanvasItem, at: Vector2, alpha: float) -> void:
	Fx.dot(canvas, at, 9.0, Color(DARK, alpha))
	Fx.dot(canvas, at, 7.0, Color(STONE, alpha))
	Fx.dot(canvas, at + Vector2(-1.0, -1.5), 3.0, Color(LIGHT, alpha))
