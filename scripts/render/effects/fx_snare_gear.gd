class_name FxSnareGear
extends RefCounted

## SNARE_GEAR (34): a toothed iron snare clamping shut. A heavy iron gear
## -- a thick band with twelve square cog teeth round its outside, edged
## dark, and six sharp jaws reaching in from it over a dark trap pit --
## turns as it closes in by 30%, slow at first then snapping shut by 60%.
## As it bites, a white flash rings the band and sparks fly off the teeth;
## then it holds and fades.

const COGS := 12
const JAWS := 6
const IRON := Color("8a949e")
const DARK := Color("1c2228")
const PIT := Color("10141a")
const SNAP_AT := 0.6


## How far it has clamped, 0..1: accelerating in, shut at SNAP_AT.
static func clamp_t(progress: float) -> float:
	var t := clampf(progress / SNAP_AT, 0.0, 1.0)
	return t * t


## The band's outer radius: closing in by 30% as it clamps.
static func gear_radius(radius: float, progress: float) -> float:
	return radius * (1.0 - clamp_t(progress) * 0.30)


## The cog teeth's height: an eighth of the radius, never under 4 units.
static func tooth(radius: float) -> float:
	return maxf(4.0, radius * 0.14)


## Full until 75%, then fading out.
static func strength(progress: float) -> float:
	return clampf((1.0 - progress) / 0.25, 0.0, 1.0)


## The gear's outline: the band's rim with a square tooth standing out
## every twelfth of a turn, as one star-shaped polygon.
static func cog_outline(at: Vector2, gear: float, height: float, turn: float) -> Array:
	var points: Array = []
	var step := TAU / COGS
	for i in COGS:
		var a := turn + i * step
		points.append(Fx.polar(at, a - step * 0.30, gear))
		points.append(Fx.polar(at, a - step * 0.20, gear + height))
		points.append(Fx.polar(at, a + step * 0.20, gear + height))
		points.append(Fx.polar(at, a + step * 0.30, gear))
	return points


## The pit inside the band, cut into by the jaws: a circle `inner` out,
## dented in to `tip` at each jaw.
static func pit_outline(at: Vector2, inner: float, tip: float, turn: float) -> Array:
	var points: Array = []
	var step := TAU / JAWS
	for i in JAWS:
		var a := turn + i * step
		points.append(Fx.polar(at, a - step * 0.16, inner))
		points.append(Fx.polar(at, a, tip))
		points.append(Fx.polar(at, a + step * 0.16, inner))
		for k in 3:
			points.append(Fx.polar(at, a + step * (0.16 + 0.17 * (k + 1)), inner))
	return points


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	var a := strength(progress)
	if a <= 0.001:
		return
	var gear := gear_radius(radius, progress)
	var height := tooth(radius)
	var turn := elapsed_ms * 0.0012 + clamp_t(progress) * 0.6
	var inner := gear * 0.78
	CircleStamp.disc(canvas, at, gear + height + 3.0, Color(Color.BLACK, a * 0.22))
	Fx.polygon(canvas, cog_outline(at, gear + 1.5, height + 1.5, turn), Color(DARK, a))
	Fx.polygon(canvas, cog_outline(at, gear, height, turn), Color(IRON, a))
	Fx.ring(canvas, at, gear - 2.0 * Fx.S, 2.0, Color(Color.WHITE, a * 0.55))
	Fx.polygon(canvas, pit_outline(at, inner + 1.0, gear * 0.4 - 1.5, turn), Color(DARK, a))
	Fx.polygon(canvas, pit_outline(at, inner, gear * 0.4, turn), Color(PIT, a * 0.82))
	Fx.dot(canvas, at, 5.0, Color(DARK, a * 0.9))
	_bite(canvas, at, gear, height, turn, progress, a)


## The snap: a white flash round the band and sparks off the cog tips, for
## a fifth of the effect from the moment it shuts.
static func _bite(canvas: CanvasItem, at: Vector2, gear: float, height: float, turn: float,
		progress: float, a: float) -> void:
	var t := (progress - SNAP_AT * 0.85) / 0.2
	if t <= 0.0 or t >= 1.0:
		return
	var flash := (1.0 - t) * a
	Fx.ring(canvas, at, gear + height * 0.5, 4.0 + 10.0 * (1.0 - t), Color(Color.WHITE, flash * 0.8))
	for i in COGS:
		var angle := turn + i * TAU / COGS
		Fx.dot(canvas, Fx.polar(at, angle, gear + height * (1.2 + 1.6 * t)), 4.5, Color("fff0c0", flash))
