class_name FxCultistFrenzy
extends RefCounted

## CULTIST_FRENZY (105): the Cultist's blood quickening, following them.
## The heart pounds twice, lub-dub, lub-dub: each beat throbs a dark red
## core and throws a crimson ring, the second of each pair smaller. Seven
## forked veins crawl out from the body and flare bright with every beat,
## and over the head a heartbeat trace races across, spiking on the beats.

const BLOOD := Color("a0101e")
const BLOOD_DARK := Color("3c0008")
const HOT := Color("ff3a4a")
const PALE := Color("ffd0d4")
const VEINS := 7
const BEATS := [0.04, 0.16, 0.48, 0.6]


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var fade := FxKit.phase(progress, 0.0, 0.04) * (1.0 - FxKit.phase(progress, 0.8, 1.0))
	var throb := _throb(progress)
	CircleStamp.disc(canvas, at, radius * (0.8 + 0.25 * throb), Color(BLOOD_DARK, fade * (0.3 + 0.25 * throb)))
	_veins(canvas, at, radius, progress, throb, fade, FxKit.seed_of(fx))
	CircleStamp.disc(canvas, at, radius * (0.3 + 0.15 * throb), Color(HOT, fade * 0.35 * throb))
	_rings(canvas, at, radius, progress)
	_trace(canvas, at + Vector2(0.0, -radius * 1.15), radius, progress, fade)


## How hard the heart is beating now, 0..1: a sharp spike on each beat,
## the dub of each pair two thirds the lub.
static func _throb(progress: float) -> float:
	var beat := 0.0
	for i in BEATS.size():
		var at: float = BEATS[i]
		beat = maxf(beat, FxKit.pulse(progress, at - 0.01, at + 0.02, at + 0.14) * (1.0 if i % 2 == 0 else 0.7))
	return beat


## A crimson ring thrown out on each beat: thick dark band, hot edge.
static func _rings(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	for i in BEATS.size():
		var start: float = BEATS[i]
		var t := FxKit.phase(progress, start, start + 0.3)
		if t <= 0.0 or t >= 1.0:
			continue
		var scale := 1.0 if i % 2 == 0 else 0.75
		var reach := radius * (0.4 + 1.1 * scale * FxKit.ease_out(t))
		Fx.ring(canvas, at, reach, 14.0 * (1.0 - t) * scale + 2.0, Color(BLOOD, (1.0 - t) * 0.7))
		Fx.ring(canvas, at, reach, 3.0, Color(HOT, (1.0 - t) * 0.95))


## Seven veins crawling out from the body over the first third, each a
## jagged line with a fork two thirds along, flaring on every beat.
static func _veins(canvas: CanvasItem, at: Vector2, radius: float, progress: float, throb: float, fade: float,
		seed: int) -> void:
	var grow := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.35))
	if grow <= 0.0 or fade <= 0.0:
		return
	var rng := FxKit.rng_seeded(seed)
	for i in VEINS:
		var heading := TAU * i / VEINS + rng.randf_range(-0.3, 0.3)
		var length := radius * rng.randf_range(0.9, 1.3) * grow
		var vein := PackedVector2Array()
		var steps := 5
		var fork_at := Vector2.ZERO
		for k in steps + 1:
			var f := float(k) / steps
			var wobble := rng.randf_range(-0.35, 0.35) if k > 0 else 0.0
			var spot := Fx.polar(at, heading + wobble * 0.4, radius * 0.25 + length * f)
			vein.append(spot)
			if k == 3:
				fork_at = spot
		var fork := Fx.polar(fork_at, heading + (0.7 if i % 2 == 0 else -0.7), length * 0.35)
		var colour := BLOOD.lerp(HOT, throb)
		Fx.polyline(canvas, vein, 6.0, Color(BLOOD_DARK, fade * 0.7))
		Fx.polyline(canvas, vein, 3.0, Color(colour, fade))
		Fx.line(canvas, fork_at, fork, 2.0, Color(colour, fade * 0.85))
		CircleStamp.disc(canvas, vein[steps], 2.0 + 2.0 * throb, Color(PALE, fade * throb))


## The heartbeat trace above the head: a flat line drawn left to right with
## the classic spike wherever a beat falls, a bright point at its head.
static func _trace(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var drawn := FxKit.phase(progress, 0.0, 0.75)
	if drawn <= 0.0 or fade <= 0.0:
		return
	var width := radius * 1.4
	var height := clampf(radius * 0.45, 8.0, 22.0)
	var left := at - Vector2(width * 0.5, 0.0)
	var points := PackedVector2Array()
	var steps := 60
	for k in int(steps * drawn) + 1:
		var f := float(k) / steps
		var y := 0.0
		for i in BEATS.size():
			var beat: float = BEATS[i] / 0.75
			var d := (f - beat) * 20.0
			if absf(d) < 1.0:
				y = -height * (1.0 if i % 2 == 0 else 0.6) * (1.0 - absf(d)) * (1.0 if d < 0.5 else -0.6)
		points.append(left + Vector2(width * f, y))
	if points.size() < 2:
		return
	Fx.polyline(canvas, points, 6.0, Color(BLOOD, fade * 0.5))
	Fx.polyline(canvas, points, 2.5, Color(HOT, fade))
	CircleStamp.disc(canvas, points[points.size() - 1], 3.0, Color(PALE, fade))
