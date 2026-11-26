class_name FxDeathPactAura
extends RefCounted

## DEATH_PACT_AURA (43): a blood pact sealed round the caster. A dark
## crimson pool that beats like a heart -- a double thump every 900ms --
## inside a thick blood rim; a five-pointed sigil inscribed in a rune ring
## turning slowly within it and flaring on each beat; a pulse ring rippling
## out from the sigil with every beat; and ten blood wisps orbiting at their
## own distances. Fades in fast and out over the last 30%.

const BLOOD := Color("a00020")
const CRIMSON := Color("ff2a48")
const POOL := Color("300010")
const DEEP := Color("5a0010")
const BEAT_MS := 900.0
const SIGIL_POINTS := 5


## How far wisp `i` of the ten orbits: 40% to 100% of the radius.
static func wisp_orbit(radius: float, i: int) -> float:
	return radius * (0.4 + fmod(i * 0.671 * 7.0, 0.6))


## Where in its heartbeat the pact is, 0..1, from the first thump.
static func beat_phase(elapsed_ms: int) -> float:
	return fmod(float(elapsed_ms), BEAT_MS) / BEAT_MS


## The heartbeat's swell, 0..1: a strong thump at the start of the beat and
## a softer one a quarter of the way through.
static func heartbeat(elapsed_ms: int) -> float:
	var t := beat_phase(elapsed_ms)
	var first := maxf(0.0, 1.0 - t / 0.16)
	var second := maxf(0.0, 1.0 - absf(t - 0.25) / 0.10) * 0.7
	return maxf(first * first, second * second)


static func strength(progress: float) -> float:
	return clampf(progress / 0.08, 0.0, 1.0) * clampf((1.0 - progress) / 0.3, 0.0, 1.0)


## The sigil: a five-pointed star traced point to second point round, as
## one closed path.
static func sigil(at: Vector2, reach: float, turn: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in SIGIL_POINTS + 1:
		points.append(Fx.polar(at, turn - PI * 0.5 + (k * 2 % SIGIL_POINTS) * TAU / SIGIL_POINTS, reach))
	return points


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	var a := strength(progress)
	if a <= 0.001:
		return
	var beat := heartbeat(elapsed_ms)
	var swell := radius * (1.0 + 0.05 * beat)
	CircleStamp.disc(canvas, at, swell, Color(POOL, a * (0.5 + 0.15 * beat)))
	CircleStamp.disc(canvas, at, radius * 0.7, Color(BLOOD, a * (0.14 + 0.22 * beat)))
	Fx.ring(canvas, at, swell, 9.0, Color(DEEP, a))
	Fx.ring(canvas, at, swell, 3.5, Color(CRIMSON, a * (0.75 + 0.25 * beat)))
	var pulse := beat_phase(elapsed_ms)
	Fx.ring(canvas, at, radius * (0.72 + 0.45 * pulse), 6.0 * (1.0 - pulse) + 1.0,
		Color(CRIMSON, a * (1.0 - pulse) * 0.7))
	var sigil_reach := radius * 0.66
	var turn := elapsed_ms * 0.0006
	Fx.ring(canvas, at, sigil_reach, 3.0, Color(BLOOD, a * 0.9))
	Fx.ring(canvas, at, sigil_reach * 0.82, 1.5, Color(BLOOD, a * 0.7))
	var star := sigil(at, sigil_reach, turn)
	Fx.polyline(canvas, star, 6.0, Color(DEEP, a * 0.9))
	Fx.polyline(canvas, star, 2.5, Color(CRIMSON, a * (0.6 + 0.4 * beat)))
	for k in SIGIL_POINTS:
		Fx.dot(canvas, star[k], 4.0 + 2.0 * beat, Color(CRIMSON, a))
	for i in 10:
		var wisp := Fx.polar(at, i * 0.671 * TAU + elapsed_ms * 0.004, wisp_orbit(radius, i))
		Fx.dot(canvas, wisp, 8.0, Color("602030", a * 0.6))
		Fx.dot(canvas, wisp, 3.5, Color(CRIMSON, a))
	Fx.dot(canvas, at, 6.0 + 4.0 * beat, Color(CRIMSON, a * 0.9))
