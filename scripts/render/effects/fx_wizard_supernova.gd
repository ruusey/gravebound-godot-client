class_name FxWizardSupernova
extends RefCounted

## WIZARD_SUPERNOVA (83): a stellar collapse. First the light falls in:
## motes spiral down into the centre along curved paths while a violet
## shell contracts and the core brightens to a white point. Then it
## detonates -- a blinding flash, a hot shell of gold and magenta racing
## to the rim with long radial rays and a flattened shock disc -- and a
## drifting nebula of violet and teal glows on where the star died.

const VOID := Color("1a0a30")
const VIOLET := Color("8a48e8")
const MAGENTA := Color("ff4ab0")
const GOLD := Color("ffd27a")
const TEAL := Color("40e0d0")
const WHITE := Color(1.0, 1.0, 1.0)
const COLLAPSE := 0.38
const MOTES := 18
const RAYS := 14


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 48.0)
	var seed := FxKit.seed_of(fx)
	if progress < COLLAPSE:
		_infall(canvas, at, radius, progress / COLLAPSE, seed)
	else:
		var t := (progress - COLLAPSE) / (1.0 - COLLAPSE)
		_nebula(canvas, at, radius, t, seed, elapsed_ms)
		_rays(canvas, at, radius, t, seed)
		_shell(canvas, at, radius, t)
		var flash := 1.0 - FxKit.phase(t, 0.0, 0.18)
		Fx.dot(canvas, at, radius * 1.3 * flash, Color(WHITE, 0.6 * flash))
		Fx.dot(canvas, at, radius * 0.5 * (0.4 + flash), Color(WHITE, flash))


## The infall: a contracting violet shell, motes spiralling in, and a core
## that tightens and brightens.
static func _infall(canvas: CanvasItem, at: Vector2, radius: float, t: float, seed: int) -> void:
	var shrink := FxKit.ease_in(t)
	var shell := radius * (1.0 - 0.85 * shrink)
	Fx.dot(canvas, at, shell * 2.0, Color(VOID, 0.12 + 0.16 * t))
	Fx.ring(canvas, at, shell, 8.0, Color(VIOLET, 0.2 + 0.2 * t))
	Fx.ring(canvas, at, shell, 2.5, Color(MAGENTA, 0.45 + 0.45 * t))
	var rng := FxKit.rng_seeded(seed)
	for i in MOTES:
		var start_angle := rng.randf_range(0.0, TAU)
		var start_dist := radius * rng.randf_range(0.8, 1.25)
		var delay := rng.randf_range(0.0, 0.4)
		var m := FxKit.phase(t, delay, minf(1.0, delay + 0.6))
		if m <= 0.0 or m >= 1.0:
			continue
		var points := PackedVector2Array()
		for s in 5:
			var f := maxf(0.0, m - 0.12 * (4 - s) / 4.0)
			var fall := FxKit.ease_in(f)
			points.append(Fx.polar(at, start_angle + fall * 2.2, start_dist * (1.0 - fall)))
		Fx.polyline(canvas, points, 3.0, Color(TEAL if i % 3 == 0 else GOLD, 0.8 * sin(PI * m)))
		Fx.dot(canvas, points[4], 3.0, Color(WHITE, sin(PI * m)))
	var core := 4.0 + 14.0 * shrink
	Fx.dot(canvas, at, core * 2.0, Color(VIOLET, 0.5))
	Fx.dot(canvas, at, core, Color(WHITE, 0.4 + 0.6 * shrink))
	FxKit.glint(canvas, at, core * 1.6, t * PI, WHITE, shrink)


## The blast shell racing to the rim: a fat gold front with a magenta
## inner edge and a flattened shock disc on the ground.
static func _shell(canvas: CanvasItem, at: Vector2, radius: float, t: float) -> void:
	var grow := FxKit.ease_out(FxKit.phase(t, 0.0, 0.5))
	var fade := 1.0 - FxKit.phase(t, 0.3, 0.7)
	if fade <= 0.0:
		return
	var reach := radius * grow
	Fx.ring(canvas, at, reach, 26.0 * fade + 4.0, Color(GOLD, 0.35 * fade))
	Fx.ring(canvas, at, reach, 6.0, Color(WHITE, 0.9 * fade))
	Fx.ring(canvas, at, reach * 0.9, 4.0, Color(MAGENTA, 0.8 * fade))
	Fx.ring(canvas, at, reach * 0.72, 2.0, Color(VIOLET, 0.6 * fade))


## Long radial rays flaring out from the core and burning down.
static func _rays(canvas: CanvasItem, at: Vector2, radius: float, t: float, seed: int) -> void:
	var fade := 1.0 - FxKit.phase(t, 0.1, 0.55)
	if fade <= 0.0:
		return
	var rng := FxKit.rng_seeded(seed + 4)
	var out := FxKit.ease_out(FxKit.phase(t, 0.0, 0.25))
	for i in RAYS:
		var angle := TAU * i / RAYS + rng.randf_range(-0.1, 0.1)
		var length := radius * rng.randf_range(0.6, 1.15) * out
		var width := rng.randf_range(5.0, 10.0)
		var dir := Vector2(cos(angle), sin(angle))
		FxKit.taper(canvas, at, at + dir * length, width, 0.0, Color(GOLD if i % 2 == 0 else MAGENTA, 0.55 * fade))
		FxKit.taper(canvas, at, at + dir * length * 0.6, width * 0.4, 0.0, Color(WHITE, 0.8 * fade))


## The nebula left behind: soft violet and teal clouds drifting slowly out
## and dimming, a few new stars twinkling in them.
static func _nebula(canvas: CanvasItem, at: Vector2, radius: float, t: float, seed: int, elapsed_ms: int) -> void:
	var swell := FxKit.ease_out(FxKit.phase(t, 0.1, 0.7))
	var fade := sin(PI * FxKit.phase(t, 0.1, 1.0))
	if fade <= 0.0:
		return
	var rng := FxKit.rng_seeded(seed + 8)
	for i in 7:
		var angle := rng.randf_range(0.0, TAU)
		var dist := radius * rng.randf_range(0.15, 0.6) * (0.6 + 0.4 * swell)
		var size := radius * rng.randf_range(0.35, 0.6)
		Fx.dot(canvas, Fx.polar(at, angle, dist), size * (1.0 + 0.4 * swell),
			Color(VIOLET if i % 2 == 0 else TEAL, 0.16 * fade))
	for i in 9:
		var star := Fx.polar(at, rng.randf_range(0.0, TAU), radius * rng.randf_range(0.1, 0.75) * swell)
		var twinkle := 0.5 + 0.5 * sin(elapsed_ms * 0.012 + i * 2.1)
		FxKit.glint(canvas, star, 7.0 * twinkle, 0.0, WHITE, fade * twinkle)
