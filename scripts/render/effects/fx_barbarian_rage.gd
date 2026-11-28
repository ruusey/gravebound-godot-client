class_name FxBarbarianRage
extends RefCounted

## BARBARIAN_RAGE (77): blood fury, riding the Barbarian. A roar bursts off
## the body first -- a crimson shock ring with short burst lines -- then
## blood-red flame tongues lick up round the feet and a heart-beat aura
## throbs twice, steam wisps curling off the shoulders, until the fury
## settles into the body at the end.

const BLOOD := Color("9a1010")
const CRIMSON := Color("e83020")
const EMBER := Color("ffb060")
const STEAM := Color("f0d8d0")
const TONGUES := 9
const WISPS := 4


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var swell := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.15))
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	_roar(canvas, at, radius, progress)
	_heartbeat(canvas, at, radius, progress, fade)
	_flames(canvas, at, radius, swell * fade, elapsed_ms)
	_steam(canvas, fx, at, radius, progress, fade)


## The roar: a crimson ring and burst lines punched out in the first fifth.
static func _roar(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var t := FxKit.phase(progress, 0.0, 0.22)
	if t <= 0.0 or t >= 1.0:
		return
	var reach := radius * (0.6 + 1.4 * FxKit.ease_out(t))
	Fx.ring(canvas, at, reach, 10.0 * (1.0 - t), Color(CRIMSON, (1.0 - t) * 0.8))
	Fx.ring(canvas, at, reach * 0.85, 2.0, Color(EMBER, (1.0 - t) * 0.7))
	for i in 12:
		var angle := TAU * i / 12.0 + 0.13
		var inner := reach * (1.05 + 0.1 * (i % 2))
		Fx.line(canvas, Fx.polar(at, angle, inner), Fx.polar(at, angle, inner + radius * 0.35 * (1.0 - t)), 3.0,
			Color(CRIMSON, 1.0 - t))


## Two quick heart-beats (lub-dub) of a red aura, then a slower hold.
static func _heartbeat(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var beat := maxf(FxKit.pulse(progress, 0.12, 0.17, 0.3), FxKit.pulse(progress, 0.42, 0.47, 0.6))
	var hold := 0.35 + 0.65 * beat
	Fx.dot(canvas, at, radius * (1.7 + 0.5 * beat), Color(BLOOD, 0.18 * hold * fade))
	Fx.dot(canvas, at, radius * (1.2 + 0.3 * beat), Color(CRIMSON, 0.14 * hold * fade))
	Fx.ring(canvas, at, radius * (0.9 + 0.35 * beat), 3.0 + 4.0 * beat, Color(CRIMSON, (0.3 + 0.6 * beat) * fade))


## Flame tongues licking up from an ellipse round the feet, each flickering
## on its own phase and bending as it sways: dark blood outer, crimson body,
## ember heart. The back row is drawn first and shorter.
static func _flames(canvas: CanvasItem, at: Vector2, radius: float, alpha: float, elapsed_ms: int) -> void:
	if alpha <= 0.0:
		return
	var feet := at + Vector2(0.0, radius * 0.45)
	var time := elapsed_ms * 0.001
	for row: int in [0, 1]:
		for i in TONGUES:
			var angle := TAU * (i + 0.5 * row) / TONGUES
			if (sin(angle) > 0.0) != (row == 1):
				continue
			var base := feet + Vector2(cos(angle) * radius * 0.85, sin(angle) * radius * 0.3)
			var flicker := 0.5 + 0.5 * sin(time * 13.0 + i * 2.3) * sin(time * 7.0 + i * 1.7)
			var height := radius * (0.7 + 0.9 * flicker) * (0.8 if row == 0 else 1.0)
			var sway := sin(time * 6.0 + i * 1.3) * radius * 0.3
			var width := radius * (0.38 + 0.12 * sin(i * 3.1))
			var a := alpha * (0.75 if row == 0 else 1.0)
			_tongue(canvas, base, height, width, sway, Color(BLOOD, 0.8 * a))
			_tongue(canvas, base, height * 0.72, width * 0.62, sway * 0.7, Color(CRIMSON, 0.9 * a))
			_tongue(canvas, base, height * 0.4, width * 0.3, sway * 0.4, Color(EMBER, a))


## One flame tongue: a bulb at the base narrowing to a tip that bends with
## `sway`, the bend lagging up its length like a real flicker.
static func _tongue(canvas: CanvasItem, base: Vector2, height: float, width: float, sway: float,
		colour: Color) -> void:
	var half := width * 0.5
	var points: Array = [base + Vector2(-half, 0.0),
		base + Vector2(-half * 1.1 + sway * 0.15, -height * 0.3),
		base + Vector2(-half * 0.45 + sway * 0.55, -height * 0.65),
		base + Vector2(sway, -height),
		base + Vector2(half * 0.45 + sway * 0.55, -height * 0.65),
		base + Vector2(half * 1.1 + sway * 0.15, -height * 0.3),
		base + Vector2(half, 0.0)]
	Fx.polygon(canvas, points, colour)


## Steam wisps curling off the shoulders, rising and fading.
static func _steam(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float,
		fade: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in WISPS:
		var offset := rng.randf_range(0.0, 1.0)
		var t := fposmod(progress * 2.2 + offset, 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var base := at + Vector2(side * radius * 0.45, -radius * 0.5)
		var points := PackedVector2Array()
		for s in 5:
			var f := t * float(s + 1) / 5.0
			points.append(base + Vector2(side * radius * 0.4 * f + sin(f * 9.0 + i) * 3.0, -radius * 1.4 * f))
		Fx.polyline(canvas, points, 3.0, Color(STEAM, (1.0 - t) * 0.5 * fade))
