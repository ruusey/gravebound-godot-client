class_name FxAssassinRapidStrikes
extends RefCounted

## ASSASSIN_RAPID_STRIKES (79): an afterimage flurry riding the Assassin.
## Three shadow doubles flicker out to stations round the body, each
## lunging back through it in turn; every pass leaves a thin pale cut with a
## violet edge, seven cuts in all crossing at odd angles, so the space
## round the Assassin is crosshatched with strikes before they dissolve.

const VIOLET := Color("9a5cd8")
const SHADE := Color("24123a")
const PALE := Color("f2ecff")
const CUTS := 7
const GHOSTS := 3


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var seed := FxKit.seed_of(fx)
	var fade := 1.0 - FxKit.phase(progress, 0.8, 1.0)
	Fx.dot(canvas, at, radius * 1.8, Color(SHADE, 0.22 * fade))
	_ghosts(canvas, at, radius, progress, seed)
	_cuts(canvas, at, radius, progress, seed)


## Shadow doubles: each pops in at its station round the body and darts
## across it, a smear of shade left along the dash.
static func _ghosts(canvas: CanvasItem, at: Vector2, radius: float, progress: float, seed: int) -> void:
	var rng := FxKit.rng_seeded(seed)
	for i in GHOSTS:
		var start := 0.05 + 0.22 * i
		var t := FxKit.phase(progress, start, start + 0.3)
		if t <= 0.0 or t >= 1.0:
			continue
		var angle := TAU * i / GHOSTS + rng.randf_range(-0.4, 0.4)
		var station := Fx.polar(at, angle, radius * 1.1)
		var exit := Fx.polar(at, angle + PI + rng.randf_range(-0.3, 0.3), radius * 1.1)
		var dash := FxKit.ease_in_out(FxKit.phase(t, 0.25, 0.7))
		var body := station.lerp(exit, dash)
		var alpha := sin(PI * t)
		if dash > 0.0:
			FxKit.taper(canvas, station.lerp(exit, maxf(0.0, dash - 0.4)), body, 2.0, 12.0,
				Color(VIOLET, 0.35 * alpha))
		_silhouette(canvas, body, (exit - station).normalized(), alpha)


## A crouched shadow: a hooded head and a hunched body, an eye-glint of
## violet, a blade held out forward.
static func _silhouette(canvas: CanvasItem, at: Vector2, dir: Vector2, alpha: float) -> void:
	Fx.dot(canvas, at + Vector2(0.0, 2.0), 20.0, Color(VIOLET, 0.5 * alpha))
	Fx.dot(canvas, at + Vector2(0.0, -6.0), 14.0, Color(VIOLET, 0.5 * alpha))
	Fx.dot(canvas, at + Vector2(0.0, 2.0), 16.0, Color(SHADE, 0.9 * alpha))
	Fx.dot(canvas, at + Vector2(0.0, -6.0), 10.0, Color(SHADE, 0.95 * alpha))
	Fx.dot(canvas, at + Vector2(dir.x * 2.0, -6.5), 2.5, Color(VIOLET, alpha))
	Fx.line(canvas, at + dir * 3.0, at + dir * 13.0, 2.0, Color(PALE, 0.8 * alpha))


## Seven thin cuts crossing the body at scattered angles, each drawn fast
## (a lens that opens and narrows) on its own beat and lingering faintly.
static func _cuts(canvas: CanvasItem, at: Vector2, radius: float, progress: float, seed: int) -> void:
	var rng := FxKit.rng_seeded(seed + 7)
	for i in CUTS:
		var start := 0.08 + 0.09 * i
		var angle := rng.randf_range(0.0, PI) + i * 1.9
		var offset := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * radius
		var draw_t := FxKit.ease_out(FxKit.phase(progress, start, start + 0.07))
		if draw_t <= 0.0:
			continue
		var linger := 1.0 - FxKit.phase(progress, start + 0.1, minf(1.0, start + 0.45))
		var flash := 1.0 - FxKit.phase(progress, start + 0.05, start + 0.15)
		var along := Vector2(cos(angle), sin(angle))
		var half := radius * (0.9 + 0.3 * (i % 2))
		var a := at + offset - along * half
		var b := at + offset - along * half + along * half * 2.0 * draw_t
		Fx.line(canvas, a, b, 5.0 + 4.0 * flash, Color(VIOLET, (0.35 + 0.5 * flash) * maxf(linger, flash)))
		Fx.line(canvas, a, b, 1.5 + 1.0 * flash, Color(PALE, maxf(linger * 0.7, flash)))
		if flash > 0.0:
			FxKit.glint(canvas, b, 9.0 * flash, angle, PALE, flash)
