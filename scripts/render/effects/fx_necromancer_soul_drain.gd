class_name FxNecromancerSoulDrain
extends RefCounted

## NECROMANCER_SOUL_DRAIN (90): souls torn from everything in range and
## pulled into the Necromancer. A violet boundary contracts in three pulses,
## fourteen pale wisps -- a head with two hollow eyes and a trailing tail --
## spiral in from the edge, staggered, and the caster flares sickly green,
## brighter as each soul is swallowed.

const VIOLET := Color("8a4fd8")
const SOUL := Color("d8ffe6")
const GREEN := Color("7cf0a0")
const DARK := Color("1a0f2a")
const WISPS := 14
const TAIL := 8
const SPIN := 2.4
const TRAVEL := 0.5


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 40.0)
	var fade := 1.0 - FxKit.phase(progress, 0.85, 1.0)
	_boundary(canvas, at, radius, progress)
	_wisps(canvas, fx, at, radius, progress)
	_flare(canvas, at, radius, progress, fade)


## A faint violet edge at the range and three rings pulling in from it.
static func _boundary(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var hold := FxKit.window(progress, 0.0, 0.7, 0.1)
	Fx.dot(canvas, at, radius * 2.0, Color(DARK, 0.18 * hold))
	Fx.ring(canvas, at, radius, 6.0, Color(VIOLET, 0.25 * hold))
	Fx.ring(canvas, at, radius, 2.0, Color(VIOLET, 0.7 * hold))
	for k in 3:
		var w := Fx.wave(progress, k * 0.16)
		if w < 0.0 or w > 0.75:
			continue
		var t := w / 0.75
		Fx.ring(canvas, at, radius * (1.0 - 0.85 * FxKit.ease_in(t)), 3.0, Color(VIOLET, 0.8 * sin(t * PI)))


## The souls: each spirals in from its own spot on the edge, its tail
## sampled from where it was a moment ago.
static func _wisps(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in WISPS:
		var start := rng.randf_range(0.0, 0.35)
		var a0 := TAU * i / WISPS + rng.randf_range(-0.25, 0.25)
		var reach := radius * rng.randf_range(0.8, 1.0)
		var t := FxKit.phase(progress, start, start + TRAVEL)
		if t <= 0.0 or t >= 1.0:
			continue
		var tail := PackedVector2Array()
		for j in TAIL:
			var s := maxf(0.0, t - 0.22 * float(TAIL - 1 - j) / (TAIL - 1))
			tail.append(_spiral(at, a0, reach, s))
		var alpha := FxKit.window(t, 0.0, 1.0, 0.15)
		Fx.polyline(canvas, tail, 12.0, Color(GREEN, 0.16 * alpha))
		Fx.polyline(canvas, tail, 5.0, Color(SOUL, 0.5 * alpha))
		var head := tail[TAIL - 1]
		var heading := (head - tail[TAIL - 2]).normalized()
		Fx.dot(canvas, head, 16.0, Color(GREEN, 0.3 * alpha))
		Fx.dot(canvas, head, 9.0, Color(SOUL, 0.95 * alpha))
		var across := heading.orthogonal() * 1.8
		Fx.dot(canvas, head + heading * 1.0 + across, 2.6, Color(DARK, alpha))
		Fx.dot(canvas, head + heading * 1.0 - across, 2.6, Color(DARK, alpha))


## Where a soul is `t` of the way in: the radius closing faster at the
## end, the angle turning as it falls.
static func _spiral(at: Vector2, a0: float, reach: float, t: float) -> Vector2:
	return Fx.polar(at, a0 + SPIN * t, reach * (1.0 - FxKit.ease_in(t)))


## The caster swelling green as the souls arrive, a glint at the peak.
static func _flare(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var fed := FxKit.ease_in(FxKit.phase(progress, 0.2, 0.85))
	var beat := 0.85 + 0.15 * sin(progress * 40.0)
	var size := radius * 0.12 * (0.4 + fed) * beat
	Fx.dot(canvas, at, size * 6.0, Color(GREEN, 0.2 * fade))
	Fx.dot(canvas, at, size * 3.0, Color(GREEN, 0.45 * fade))
	Fx.dot(canvas, at, size * 1.4, Color(SOUL, 0.9 * fade))
	Fx.ring(canvas, at, size * 1.6, 2.0, Color(VIOLET, 0.6 * fade))
	var burst := FxKit.pulse(progress, 0.8, 0.86, 1.0)
	FxKit.glint(canvas, at, radius * 0.4 * burst, PI * 0.25, GREEN, burst)
