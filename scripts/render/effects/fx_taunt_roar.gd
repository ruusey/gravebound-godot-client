class_name FxTauntRoar
extends RefCounted

## TAUNT_ROAR (17): a roar bellowed out from the caster. Three shout
## waves burst out one after another, each a broken ring of four thick
## sound-wave arcs -- deep red under a bright red stroke with a hot pink
## core -- thinning and fading as it spreads past the radius, each wave's
## gaps turned from the last's; a ring of short shout streaks flicks out
## with the first wave, and a brief white-red burst marks the mouth. It is
## all outline, never a filled zone, and it ignores the tier colour.

const WAVES := 3
const WAVE_GAP := 0.18
const ARCS := 4
const ARC_SEGMENTS := 8
const STREAKS := 12
const DEEP := Color("8a0814")
const RED := Color("ff3040")
const HOT := Color("ffb0b0")


## How far out a wave `wave` of the way through its life has spread:
## bursting out from a quarter of the radius to 1.3 of it, fast at first.
static func wave_radius(radius: float, wave: float) -> float:
	return radius * (0.25 + 1.05 * (1.0 - (1.0 - wave) * (1.0 - wave)))


## All of one wave's arcs as segment pairs, for one draw_multiline: four
## arcs of 70 degrees, a quarter turn apart, turned by `turn`.
static func wave_arcs(at: Vector2, reach: float, turn: float) -> PackedVector2Array:
	var pairs := PackedVector2Array()
	var span := deg_to_rad(70.0)
	for arc in ARCS:
		var start := turn + arc * TAU / ARCS - span * 0.5
		for k in ARC_SEGMENTS:
			pairs.append(Fx.polar(at, start + span * k / ARC_SEGMENTS, reach))
			pairs.append(Fx.polar(at, start + span * (k + 1) / ARC_SEGMENTS, reach))
	return pairs


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	for w in WAVES:
		var wave := Fx.wave(progress, w * WAVE_GAP)
		if wave < 0.0:
			continue
		var fade := 1.0 - wave
		var arcs := wave_arcs(at, wave_radius(radius, wave), PI * 0.25 + w * PI * 0.25)
		canvas.draw_multiline(arcs, Color(DEEP, fade * 0.6), (16.0 * fade + 4.0) * Fx.S)
		canvas.draw_multiline(arcs, Color(RED, fade), (9.0 * fade + 2.0) * Fx.S)
		canvas.draw_multiline(arcs, Color(HOT, fade * 0.9), (3.0 * fade + 1.0) * Fx.S)
	_streaks(canvas, at, radius, progress)
	if progress < 0.2:
		var burst := 1.0 - progress / 0.2
		Fx.ring(canvas, at, radius * (0.15 + 0.2 * progress / 0.2), 6.0 * burst + 2.0, Color(RED, burst))
		CircleStamp.disc(canvas, at, radius * 0.14, Color(Color.WHITE, burst * 0.85))


## Short radial streaks riding just outside the first wave, flicking out
## and gone by the time it is halfway.
static func _streaks(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var t := progress / 0.5
	if t <= 0.0 or t >= 1.0:
		return
	var reach := wave_radius(radius, Fx.wave(progress, 0.0))
	var lines := PackedVector2Array()
	for i in STREAKS:
		var angle := i * TAU / STREAKS
		lines.append(Fx.polar(at, angle, reach * 1.08))
		lines.append(Fx.polar(at, angle, reach * (1.08 + 0.3 * (1.0 - t))))
	canvas.draw_multiline(lines, Color(HOT, (1.0 - t) * 0.9), 3.0 * Fx.S)
