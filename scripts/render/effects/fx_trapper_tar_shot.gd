class_name FxTrapperTarShot
extends RefCounted

## TRAPPER_TAR_SHOT (88): a glob of tar spat from the Trapper (`pos`) in a
## lobbed arc to `target`. The glob wobbles as it flies, stringy drips
## falling off behind it; it lands with a heavy splat -- an irregular black
## splash with a glossy amber sheen, droplets thrown out round it that
## land as spots -- and the sticky puddle lingers, a slow bubble rising in
## it, as everything sinks away.

const TAR := Color("16120e")
const PITCH := Color("2e241a")
const AMBER := Color("d89a3a")
const GLOSS := Color("fff0c8")
const FLIGHT := 0.4
const LOBES := 9


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx)
	var size: float = clampf(fx["radius"], 16.0, 48.0)
	var seed := FxKit.seed_of(fx)
	if progress < FLIGHT:
		_glob_flight(canvas, fx, from, to, size, progress / FLIGHT)
	else:
		_splat(canvas, to, size, (progress - FLIGHT) / (1.0 - FLIGHT), seed)


## A point on the lob, `f` 0..1 along it.
static func _lob(from: Vector2, to: Vector2, f: float) -> Vector2:
	var height := maxf(24.0, from.distance_to(to) * 0.3)
	return from.lerp(to, f) + Vector2(0.0, -height * 4.0 * f * (1.0 - f))


## In flight: a wobbling glob with a gloss fleck and drips stringing off.
static func _glob_flight(canvas: CanvasItem, fx: Dictionary, from: Vector2, to: Vector2, size: float,
		t: float) -> void:
	var at := _lob(from, to, t)
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in 5:
		var born := rng.randf_range(0.0, 0.8)
		var age := (t - born) * 2.5
		if age <= 0.0 or age >= 1.0:
			continue
		var drop := _lob(from, to, born) + Vector2(0.0, 30.0 * age * age)
		Fx.line(canvas, drop - Vector2(0.0, 4.0), drop, 2.5, Color(TAR, 1.0 - age))
		Fx.dot(canvas, drop, 4.0, Color(TAR, 1.0 - age))
	var wobble := sin(t * 30.0) * 0.2
	var glob := size * 0.35
	var points: Array = []
	for i in 12:
		var angle := TAU * i / 12.0
		var squish := 1.0 + wobble * cos(angle * 2.0)
		points.append(at + Vector2(cos(angle) * glob * squish, sin(angle) * glob / squish))
	Fx.polygon(canvas, points, Color(TAR, 1.0))
	Fx.dot(canvas, at + Vector2(-glob * 0.3, -glob * 0.35), glob * 0.6, Color(AMBER, 0.6))
	Fx.dot(canvas, at + Vector2(-glob * 0.35, -glob * 0.4), glob * 0.25, Color(GLOSS, 0.9))


## The splat: a lobed puddle that slaps out fast, droplets thrown out that
## land as spots, a gloss sheen, a bubble rising late, then sinking away.
static func _splat(canvas: CanvasItem, at: Vector2, size: float, t: float, seed: int) -> void:
	var slap := FxKit.ease_out(FxKit.phase(t, 0.0, 0.15))
	var fade := 1.0 - FxKit.phase(t, 0.7, 1.0)
	if slap < 0.05:
		return
	var rng := FxKit.rng_seeded(seed)
	var points: Array = []
	for i in LOBES * 2:
		var angle := TAU * i / (LOBES * 2)
		var reach := size * (1.0 if i % 2 == 0 else 0.7) * rng.randf_range(0.75, 1.15) * slap
		points.append(at + Vector2(cos(angle) * reach, sin(angle) * reach * 0.6))
	Fx.polygon(canvas, points, Color(PITCH, 0.9 * fade))
	var inner: Array = []
	for p: Vector2 in points:
		inner.append(at + (p - at) * 0.8)
	Fx.polygon(canvas, inner, Color(TAR, fade))
	Fx.arc(canvas, at + Vector2(-size * 0.1, -size * 0.08), PI * 1.1, PI * 1.6, size * 0.45 * slap, 6, 3.0,
		Color(AMBER, 0.7 * fade))
	Fx.dot(canvas, at + Vector2(-size * 0.3, -size * 0.2), 4.0 * slap, Color(GLOSS, 0.9 * fade))
	_droplets(canvas, at, size, t, fade, rng)
	var bubble := FxKit.phase(t, 0.4, 0.75)
	if bubble > 0.0 and bubble < 1.0:
		var spot := at + Vector2(size * 0.2, size * 0.05)
		if bubble < 0.8:
			Fx.dot(canvas, spot, 3.0 + 7.0 * bubble, Color(PITCH, fade))
			Fx.dot(canvas, spot + Vector2(-1.5, -2.0), 2.5, Color(GLOSS, 0.8 * fade))
		else:
			Fx.ring(canvas, spot, 6.0 + 6.0 * (bubble - 0.8) * 5.0, 2.0, Color(AMBER, (1.0 - bubble) * 5.0 * fade))
	var flash := 1.0 - FxKit.phase(t, 0.0, 0.2)
	Fx.ring(canvas, at, size * (0.4 + 0.9 * (1.0 - flash)), 3.0, Color(AMBER, flash * 0.6))


## Droplets thrown up out of the splat, landing as small spots that stay.
static func _droplets(canvas: CanvasItem, at: Vector2, size: float, t: float, fade: float,
		rng: RandomNumberGenerator) -> void:
	var fly := FxKit.phase(t, 0.0, 0.3)
	for i in 8:
		var angle := rng.randf_range(0.0, TAU)
		var dist := size * rng.randf_range(1.0, 1.6)
		var land := at + Vector2(cos(angle) * dist, sin(angle) * dist * 0.6)
		var pos := at.lerp(land, fly) + Vector2(0.0, -size * 0.5 * 4.0 * fly * (1.0 - fly))
		Fx.dot(canvas, pos, 5.0 if fly < 1.0 else 6.0, Color(TAR, fade))
