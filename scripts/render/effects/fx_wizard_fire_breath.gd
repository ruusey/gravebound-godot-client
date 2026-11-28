class_name FxWizardFireBreath
extends RefCounted

## WIZARD_FIRE_BREATH (81): a dragon's maw of flame from the Wizard (`pos`)
## toward `target`. Two fang-shaped jaws of fire snap open at the mouth,
## then a roaring cone pours out between them: layered flame tongues
## (smoke-red outside, orange body, white-gold core) that billow wider with
## distance and lick forward, embers spitting off the edges, and a curl of
## smoke rolling off the far end as it dies.

const SMOKE := Color("4a2018")
const RED := Color("d83a10")
const ORANGE := Color("ff8a20")
const GOLD := Color("ffd860")
const CORE := Color("fff8d8")
const TONGUES := 7
const EMBERS := 14
const SPREAD := 0.42


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx, 96.0)
	var span := to - from
	var dir := span.normalized() if span.length() > 1.0 else Vector2.RIGHT
	var width: float = maxf(fx["radius"], 16.0)
	# The aim can be the whole cast range away; the breath stays at the mouth.
	var length := clampf(span.length(), 32.0, width * 3.0)
	var reach := FxKit.ease_out(FxKit.phase(progress, 0.05, 0.35))
	var fade := 1.0 - FxKit.phase(progress, 0.6, 1.0)
	var seed := FxKit.seed_of(fx)
	_smoke(canvas, from, dir, length, width, progress, seed)
	_cone(canvas, from, dir, length * reach, width, fade, elapsed_ms)
	_jaws(canvas, from, dir, width, progress)
	_embers(canvas, from, dir, length, width, progress, seed)


## The roaring cone: tongues fanned across the spread, each a flame
## wedge that licks back and forth; three colour layers, widest outside.
static func _cone(canvas: CanvasItem, from: Vector2, dir: Vector2, length: float, width: float, fade: float,
		elapsed_ms: int) -> void:
	if length <= 2.0 or fade <= 0.0:
		return
	var time := elapsed_ms * 0.001
	var mouth := from + dir * 6.0
	var layers := [[SMOKE, 1.0, 1.0, 0.55], [RED, 0.92, 0.85, 0.8], [ORANGE, 0.78, 0.62, 0.9],
		[GOLD, 0.6, 0.4, 0.95], [CORE, 0.38, 0.2, 1.0]]
	for layer: Array in layers:
		var colour: Color = layer[0]
		var reach: float = layer[1]
		var fan: float = layer[2]
		var alpha: float = layer[3]
		for i in TONGUES:
			var f := (float(i) / (TONGUES - 1)) * 2.0 - 1.0
			var lick := sin(time * 17.0 + i * 1.9) * 0.08
			var heading := dir.rotated((f * SPREAD + lick) * fan)
			var tongue := length * reach * (0.85 + 0.15 * sin(time * 11.0 + i * 2.7)) * (1.0 - 0.25 * absf(f))
			var tip := mouth + heading * tongue
			FxKit.taper(canvas, mouth, mouth.lerp(tip, 0.55), width * 0.25 * fan, width * 0.55 * fan,
				Color(colour, alpha * fade))
			FxKit.taper(canvas, mouth.lerp(tip, 0.55), tip, width * 0.55 * fan, 0.0, Color(colour, alpha * fade))


## Two jaws of flame at the mouth: curved fangs that snap open, hold, and
## close as the breath ends.
static func _jaws(canvas: CanvasItem, from: Vector2, dir: Vector2, width: float, progress: float) -> void:
	var open := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.12)) * (1.0 - FxKit.ease_in(FxKit.phase(progress, 0.55, 0.8)))
	if open <= 0.0:
		return
	var across := dir.orthogonal()
	for s: float in [-1.0, 1.0]:
		var gape := (0.15 + 0.5 * open) * s
		var points := PackedVector2Array()
		for i in 7:
			var f := float(i) / 6.0
			var bend := dir.rotated(gape * (1.0 - f * 0.6))
			points.append(from + bend * width * 1.3 * f + across * s * width * 0.15 * sin(PI * f))
		Fx.polyline(canvas, points, 9.0, Color(RED, 0.8 * open))
		Fx.polyline(canvas, points, 4.0, Color(GOLD, open))
		var fang: Vector2 = points[points.size() - 1]
		var fang_dir := (points[points.size() - 1] - points[points.size() - 2]).normalized()
		FxKit.taper(canvas, fang, fang + fang_dir.rotated(-s * 1.2) * width * 0.35, 5.0, 0.0, Color(CORE, open))


## Embers spat off the cone's edges, drifting up as they cool.
static func _embers(canvas: CanvasItem, from: Vector2, dir: Vector2, length: float, width: float,
		progress: float, seed: int) -> void:
	var rng := FxKit.rng_seeded(seed)
	for i in EMBERS:
		var born := rng.randf_range(0.08, 0.5)
		var t := FxKit.phase(progress, born, born + 0.45)
		var heading := dir.rotated(rng.randf_range(-SPREAD, SPREAD) * 1.2)
		var travel := length * rng.randf_range(0.4, 1.1)
		if t <= 0.0 or t >= 1.0:
			continue
		var at := from + heading * travel * FxKit.ease_out(t) + Vector2(0.0, -width * 0.6 * t)
		var colour := GOLD.lerp(RED, t)
		Fx.dot(canvas, at, 4.0 * (1.0 - t) + 1.5, Color(colour, 1.0 - t))


## Smoke rolling off the far end as the flame dies: dark puffs swelling.
static func _smoke(canvas: CanvasItem, from: Vector2, dir: Vector2, length: float, width: float,
		progress: float, seed: int) -> void:
	var t := FxKit.phase(progress, 0.4, 1.0)
	if t <= 0.0 or t >= 1.0:
		return
	var rng := FxKit.rng_seeded(seed + 5)
	for i in 5:
		var at := from + dir.rotated(rng.randf_range(-SPREAD, SPREAD)) * length * rng.randf_range(0.6, 1.0)
		at += Vector2(0.0, -width * 0.8 * t)
		Fx.dot(canvas, at, width * (0.5 + 0.8 * t), Color(SMOKE, 0.45 * sin(PI * t)))
