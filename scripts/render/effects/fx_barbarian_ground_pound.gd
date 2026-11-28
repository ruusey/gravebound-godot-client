class_name FxBarbarianGroundPound
extends RefCounted

## BARBARIAN_GROUND_POUND (76): the earth ruptures under the blow. A dark
## crater punches in at the centre and jagged fissures race out to the rim,
## glowing molten-orange at their roots; broken slabs heave up round the
## crater and drop back, rock chunks are thrown up and fall, and a squat dust
## shock rolls out along the ground (the STUN wave) before the cracks cool.

const EARTH := Color("5a3e26")
const OCHRE := Color("b08850")
const DUST := Color("c8b090")
const DARK := Color("1c120a")
const MAGMA := Color("ff8a2a")
const FISSURES := 7
const SLABS := 6
const CHUNKS := 10


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 32.0)
	var seed := FxKit.seed_of(fx)
	var fade := 1.0 - FxKit.phase(progress, 0.65, 1.0)
	_dust(canvas, at, radius, progress)
	_crater(canvas, at, radius, progress, fade)
	_fissures(canvas, at, radius, progress, fade, seed)
	_slabs(canvas, at, radius, progress, fade, seed)
	_chunks(canvas, at, radius, progress, seed)
	var flash := FxKit.pulse(progress, 0.0, 0.04, 0.2)
	Fx.dot(canvas, at, radius * 0.9 * flash, Color(Color("fff0d0"), flash * 0.5))


## A low dust wall rolling out: a flattened ring (ground perspective) with a
## soft fill behind its front, thinning as it goes.
static func _dust(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var t := FxKit.phase(progress, 0.02, 0.75)
	if t <= 0.0 or t >= 1.0:
		return
	var reach := radius * (0.25 + 0.85 * FxKit.ease_out(t))
	var alpha := 1.0 - t
	Fx.polyline(canvas, _ellipse(at, reach), 22.0 * (1.0 - t) + 4.0, Color(DUST, 0.35 * alpha))
	Fx.polyline(canvas, _ellipse(at, reach), 4.0, Color(DUST, 0.8 * alpha))
	Fx.polyline(canvas, _ellipse(at, reach * 0.8), 3.0, Color(OCHRE, 0.4 * alpha))


## A closed ellipse squashed to 60% height: a ring lying on the ground.
static func _ellipse(at: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 33:
		var angle := TAU * i / 32.0
		points.append(at + Vector2(cos(angle) * radius, sin(angle) * radius * 0.6))
	return points


## The punched-in crater: a dark bowl with a lit lip.
static func _crater(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var open := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.12))
	var size := radius * 0.28 * open
	if size <= 0.5:
		return
	Fx.dot(canvas, at, size * 2.4, Color(DARK, 0.45 * fade))
	Fx.dot(canvas, at, size * 1.7, Color(DARK, 0.8 * fade))
	Fx.ring(canvas, at, size * 1.1, 3.0, Color(OCHRE, 0.7 * fade))
	Fx.dot(canvas, at, size * 0.8, Color(MAGMA, 0.5 * fade * (1.0 - FxKit.phase(progress, 0.2, 0.7))))


## Jagged fissures racing from the crater to the rim; molten at the root,
## cooling to dark as the effect ends.
static func _fissures(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float,
		seed: int) -> void:
	var run := FxKit.ease_out(FxKit.phase(progress, 0.02, 0.3))
	if run <= 0.0:
		return
	var heat := 1.0 - FxKit.phase(progress, 0.25, 0.8)
	var rng := FxKit.rng_seeded(seed)
	for i in FISSURES:
		var angle := TAU * i / FISSURES + rng.randf_range(-0.3, 0.3)
		var length := radius * rng.randf_range(0.7, 1.0) * run
		var points := PackedVector2Array([at])
		var steps := 5
		for s in steps:
			var f := float(s + 1) / steps
			var wobble := rng.randf_range(-0.35, 0.35) * (1.0 - f * 0.5)
			points.append(Fx.polar(at, angle + wobble * 0.5, length * f))
		Fx.polyline(canvas, points, 6.0, Color(DARK, 0.85 * fade))
		Fx.polyline(canvas, points.slice(0, 4), 3.0, Color(MAGMA, heat * fade))
		Fx.polyline(canvas, points.slice(0, 2), 1.5, Color(Color("fff0a0"), heat * fade))
		if rng.randf() < 0.6:
			var fork_from: Vector2 = points[3]
			var fork_to := Fx.polar(fork_from, angle + rng.randf_range(0.5, 0.9) * (1.0 if i % 2 == 0 else -1.0),
				length * 0.3)
			Fx.line(canvas, fork_from, fork_to, 3.0, Color(DARK, 0.7 * fade))


## Broken slabs round the crater, heaved up (lifted and tilted) then
## dropped back, a shadow under each while it is up.
static func _slabs(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float,
		seed: int) -> void:
	var rng := FxKit.rng_seeded(seed + 11)
	var heave := sin(PI * FxKit.phase(progress, 0.03, 0.4))
	for i in SLABS:
		var angle := TAU * (i + 0.5) / SLABS + rng.randf_range(-0.2, 0.2)
		var centre := Fx.polar(at, angle, radius * rng.randf_range(0.38, 0.55))
		var size := radius * rng.randf_range(0.1, 0.15)
		var lift := heave * size * 1.2
		var tilt := angle + PI * 0.5 + heave * 0.5
		var corners: Array = []
		for c in 4:
			corners.append(centre + Vector2(size, size * 0.6).rotated(tilt + c * PI * 0.5 + (c % 2) * 0.3)
				* Vector2(1.0, 0.7) - Vector2(0.0, lift))
		if lift > 0.5:
			Fx.dot(canvas, centre, size * 2.0, Color(DARK, 0.4 * heave * fade))
		Fx.polygon(canvas, corners, Color(EARTH, fade))
		Fx.line(canvas, corners[0], corners[1], 2.0, Color(OCHRE, fade))


## Rock chunks thrown up out of the crater and falling back with a bounce of
## gravity, tumbling as they go.
static func _chunks(canvas: CanvasItem, at: Vector2, radius: float, progress: float, seed: int) -> void:
	var t := FxKit.phase(progress, 0.02, 0.6)
	if t <= 0.0 or t >= 1.0:
		return
	var rng := FxKit.rng_seeded(seed + 23)
	for i in CHUNKS:
		var angle := rng.randf_range(0.0, TAU)
		var out := radius * rng.randf_range(0.3, 0.8) * t
		var rise := radius * rng.randf_range(0.4, 0.8) * 4.0 * t * (1.0 - t)
		var size := rng.randf_range(2.0, 4.0)
		var spin := rng.randf_range(-8.0, 8.0) * t
		var centre := Fx.polar(at, angle, out) * Vector2(1.0, 1.0) - Vector2(0.0, rise)
		var rock: Array = []
		for c in 4:
			rock.append(centre + Vector2(size, 0.0).rotated(spin + c * PI * 0.5 + (0.3 if c == 1 else 0.0)))
		Fx.polygon(canvas, rock, Color(EARTH.lerp(OCHRE, 0.3), 1.0 - FxKit.phase(t, 0.8, 1.0)))
