class_name FxTrapperShootdown
extends RefCounted

## TRAPPER_SHOOTDOWN (89): the marksman's sight, from the Trapper (`pos`)
## to the mark (`target`). A red laser sight flickers out to the mark and a
## reticle of four corner brackets swings in from wide, turning, to lock
## tight with a blink; then the shot -- a white-hot tracer snaps down the
## line, the reticle bursts outward, a punch of light and a ring mark the
## hit and the sight line burns off.

const LASER := Color("ff3a30")
const SIGHT := Color("ffd0a0")
const TRACER := Color("fff4d0")
const AMBER := Color("ffb040")
const LOCK := 0.42
const FIRE := 0.5


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx, 96.0)
	var span := to - from
	var dir := span.normalized() if span.length() > 1.0 else Vector2.RIGHT
	var size: float = clampf(fx["radius"], 16.0, 48.0)
	_laser(canvas, from, to, progress, elapsed_ms)
	_reticle(canvas, to, size, progress)
	_shot(canvas, fx, from, to, dir, size, progress)


## The laser sight: a thin red line drawn out to the mark with a dot on
## it, flickering, burnt off after the shot.
static func _laser(canvas: CanvasItem, from: Vector2, to: Vector2, progress: float, elapsed_ms: int) -> void:
	var out := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.15))
	var fade := 1.0 - FxKit.phase(progress, FIRE, FIRE + 0.15)
	if out <= 0.0 or fade <= 0.0:
		return
	var flicker := 0.75 + 0.25 * sin(elapsed_ms * 0.09)
	var end := from.lerp(to, out)
	Fx.line(canvas, from, end, 4.0, Color(LASER, 0.25 * fade * flicker))
	Fx.line(canvas, from, end, 1.5, Color(LASER, 0.9 * fade * flicker))
	Fx.dot(canvas, end, 5.0, Color(LASER, fade))
	Fx.dot(canvas, end, 2.5, Color(Color.WHITE, fade))


## The reticle: four corner brackets swinging in and turning to lock, a
## blink on the lock, then blown outward by the shot.
static func _reticle(canvas: CanvasItem, at: Vector2, size: float, progress: float) -> void:
	var close := FxKit.ease_out(FxKit.phase(progress, 0.05, LOCK))
	var burst := FxKit.ease_out(FxKit.phase(progress, FIRE, 0.85))
	var alpha := FxKit.phase(progress, 0.05, 0.15) * (1.0 - burst)
	if alpha <= 0.0:
		return
	var blink := FxKit.pulse(progress, LOCK - 0.02, LOCK, LOCK + 0.06)
	var spread := size * (2.2 - 1.3 * close + 1.6 * burst)
	var turn := (1.0 - close) * PI * 0.5
	var colour := SIGHT.lerp(LASER, close)
	for i in 4:
		var angle := turn + PI * 0.25 + i * PI * 0.5
		var corner := Fx.polar(at, angle, spread)
		var arm := size * 0.35
		var back_a := (at - corner).normalized().rotated(PI * 0.25) * arm
		var back_b := (at - corner).normalized().rotated(-PI * 0.25) * arm
		Fx.line(canvas, corner, corner + back_a, 3.0 + 3.0 * blink, Color(colour, alpha))
		Fx.line(canvas, corner, corner + back_b, 3.0 + 3.0 * blink, Color(colour, alpha))
	var hair := size * 0.25 * close
	if hair > 1.0:
		Fx.line(canvas, at - Vector2(hair, 0.0), at + Vector2(hair, 0.0), 1.5, Color(LASER, alpha))
		Fx.line(canvas, at - Vector2(0.0, hair), at + Vector2(0.0, hair), 1.5, Color(LASER, alpha))
	if blink > 0.0:
		Fx.ring(canvas, at, spread * 0.75, 2.0, Color(Color.WHITE, blink))


## The shot: a tracer snapping down the line, a punch of light at the mark,
## a ring and hot chips.
static func _shot(canvas: CanvasItem, fx: Dictionary, from: Vector2, to: Vector2, dir: Vector2, size: float,
		progress: float) -> void:
	var t := FxKit.phase(progress, FIRE, 1.0)
	if t <= 0.0:
		return
	var head := FxKit.ease_out(FxKit.phase(progress, FIRE, FIRE + 0.05))
	var tail := FxKit.ease_in(FxKit.phase(progress, FIRE, FIRE + 0.2))
	if head > tail:
		var a := from.lerp(to, tail)
		var b := from.lerp(to, head)
		FxKit.taper(canvas, b, a, 6.0, 0.0, Color(AMBER, 0.6))
		FxKit.glow_line(canvas, a, b, 2.5, TRACER, 1.0)
	var punch := FxKit.pulse(progress, FIRE + 0.03, FIRE + 0.06, FIRE + 0.25)
	FxKit.glint(canvas, to, size * 1.4 * punch, PI * 0.25, TRACER, punch)
	var ring_t := FxKit.phase(progress, FIRE + 0.04, 0.95)
	Fx.ring(canvas, to, size * (0.3 + 0.9 * FxKit.ease_out(ring_t)), 3.0, Color(AMBER, (1.0 - ring_t) * 0.85))
	FxKit.sparks(canvas, to, dir, 1.6, 8, size * 1.2, FxKit.phase(progress, FIRE + 0.04, 0.9), 8.0, 2.5,
		AMBER, 1.0, FxKit.seed_of(fx))
