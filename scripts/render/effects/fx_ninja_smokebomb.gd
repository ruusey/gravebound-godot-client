class_name FxNinjaSmokebomb
extends RefCounted

## NINJA_SMOKEBOMB (104): the Ninja vanishes in a smokebomb, left where it
## burst. A black bomb with a fizzing fuse drops at the feet and pops in a
## white-and-pink flash; a ring of plum-grey smoke billows out from it,
## every puff shaded dark below and lit on top, swirling round as it
## spreads; and a flurry of sakura petals is flung out on a spiral,
## fluttering as they drift down, long after the smoke has thinned.

const SMOKE_DARK := Color("2e2a3c")
const SMOKE := Color("5e5672")
const SMOKE_LIT := Color("a89cbc")
const PETAL := Color("ffb7c8")
const PETAL_LIT := Color("fff0f4")
const INK := Color("121016")
const SPARK := Color("ffd27a")
const PUFFS := 14
const PETALS := 11
const POP := 0.08


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	_bomb(canvas, at, radius, progress, elapsed_ms)
	_smoke(canvas, at, radius, progress, elapsed_ms)
	_pop(canvas, at, radius, progress)
	_petals(canvas, at, radius, progress, elapsed_ms, FxKit.seed_of(fx))


## The bomb: a black ball with a highlight and a spitting fuse, there only
## until it pops.
static func _bomb(canvas: CanvasItem, at: Vector2, radius: float, progress: float, elapsed_ms: int) -> void:
	if progress >= POP:
		return
	var size := clampf(radius * 0.16, 5.0, 12.0)
	var drop := at + Vector2(0.0, -size * 3.0 * (1.0 - FxKit.ease_in(progress / POP)))
	CircleStamp.disc(canvas, drop, size, Color(INK, 1.0))
	CircleStamp.disc(canvas, drop + Vector2(-size * 0.35, -size * 0.35), size * 0.3, Color(SMOKE_LIT, 0.9))
	var fuse := drop + Vector2(size * 0.6, -size * 1.1)
	Fx.line(canvas, drop + Vector2(size * 0.4, -size * 0.8), fuse, 3.0, Color("8a6a40", 1.0))
	FxKit.glint(canvas, fuse, size * (1.4 + 0.5 * sin(elapsed_ms * 0.08)), elapsed_ms * 0.02, SPARK, 1.0)


## The pop: a white core in a pink bloom and a thin bright ring.
static func _pop(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var flash := FxKit.pulse(progress, POP - 0.01, POP + 0.03, 0.3)
	if flash <= 0.0:
		return
	var t := FxKit.phase(progress, POP, 0.3)
	CircleStamp.disc(canvas, at, radius * 0.8 * flash, Color(PETAL, flash * 0.35))
	CircleStamp.disc(canvas, at, radius * 0.4 * flash, Color(Color.WHITE, flash * 0.85))
	Fx.ring(canvas, at, radius * (0.3 + 0.9 * FxKit.ease_out(t)), 5.0 * (1.0 - t) + 1.0, Color(PETAL_LIT, 1.0 - t))


## The smoke ring: fourteen puffs thrown out and swirling round, each a dark
## base, a body and a lit top, swelling and thinning; a dim haze fills the
## middle.
static func _smoke(canvas: CanvasItem, at: Vector2, radius: float, progress: float, elapsed_ms: int) -> void:
	var t := FxKit.phase(progress, POP, 1.0)
	if t <= 0.0:
		return
	var spread := FxKit.ease_out(FxKit.phase(progress, POP, 0.55))
	var alpha := FxKit.phase(progress, POP, POP + 0.06) * (1.0 - FxKit.phase(progress, 0.55, 1.0))
	var swirl := t * 2.2 + elapsed_ms * 0.0006
	CircleStamp.disc(canvas, at, radius * (0.4 + 0.6 * spread), Color(SMOKE_DARK, alpha * 0.35))
	for i in PUFFS:
		var lane := 0.7 + 0.3 * float(i % 3) / 2.0
		var angle := TAU * i / PUFFS + swirl * (1.15 - lane * 0.3)
		var centre := Fx.polar(at, angle, radius * (0.15 + 0.75 * spread) * lane) + Vector2(0.0, -radius * 0.12 * t)
		var size := radius * (0.18 + 0.2 * spread) * (0.85 + 0.15 * sin(i * 2.3))
		CircleStamp.disc(canvas, centre + Vector2(0.0, size * 0.2), size, Color(SMOKE_DARK, alpha * 0.8))
		CircleStamp.disc(canvas, centre, size * 0.85, Color(SMOKE, alpha * 0.75))
		CircleStamp.disc(canvas, centre + Vector2(-size * 0.25, -size * 0.3), size * 0.45, Color(SMOKE_LIT, alpha * 0.55))


## Sakura petals flung out on a spiral from the pop, then drifting down and
## swaying, each a pink lens that flutters thin and wide as it turns.
static func _petals(canvas: CanvasItem, at: Vector2, radius: float, progress: float, elapsed_ms: int,
		seed: int) -> void:
	var t := FxKit.phase(progress, POP, 1.0)
	if t <= 0.0:
		return
	var rng := FxKit.rng_seeded(seed)
	var size := clampf(radius * 0.14, 4.0, 11.0)
	for i in PETALS:
		var angle := TAU * i / PETALS + rng.randf_range(-0.3, 0.3)
		var reach := radius * rng.randf_range(0.7, 1.35)
		var delay := rng.randf_range(0.0, 0.12)
		var flight := FxKit.ease_out(FxKit.phase(t, delay, delay + 0.5))
		var sway := sin(elapsed_ms * 0.006 + i * 1.7) * size * 1.2 * t
		var spot := Fx.polar(at, angle + flight * 1.2, reach * flight) + Vector2(sway, radius * 0.5 * t * t - radius * 0.3 * flight)
		var alpha := FxKit.phase(t, delay, delay + 0.05) * (1.0 - FxKit.phase(progress, 0.8, 1.0))
		var turn := elapsed_ms * 0.007 * (1.0 if i % 2 == 0 else -1.0) + i
		var flutter := 0.35 + 0.65 * absf(sin(elapsed_ms * 0.009 + i))
		Fx.polygon(canvas, FxBladeShapes.lens(spot, turn, size, size * 0.55 * flutter), Color(PETAL, alpha))
		Fx.polygon(canvas, FxBladeShapes.lens(spot, turn, size * 0.5, size * 0.22 * flutter), Color(PETAL_LIT, alpha * 0.9))
