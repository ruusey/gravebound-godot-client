class_name FxDruidWildSurge
extends RefCounted

## DRUID_WILD_SURGE (61): the wild answering the Druid, following them. A
## sap-green shockwave rolls out, two rings of thorns burst from the ground
## one after the other and sink back, a vortex of leaves is flung spinning
## outward, and a pair of glowing spirit antlers grows from the Druid's head,
## branching tine by tine, and burns on until the surge fades.

const BARK := Color("3b2a17")
const MOSS := Color("2f7a2a")
const SAP := Color("7cf07a")
const LIME := Color("c8f55a")
const GOLD := Color("f2d36b")
const THORNS := 14
const LEAVES := 22
## Each tine: where on the beam it branches (0..1), its lean off the beam and its length.
const TINES: Array[Vector3] = [Vector3(0.3, -0.35, 0.55), Vector3(0.55, -0.2, 0.6), Vector3(0.78, -0.05, 0.45)]


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 48.0)
	var fade := 1.0 - FxKit.phase(progress, 0.8, 1.0)
	var floor_glow := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.25)) * fade
	Fx.dot(canvas, at, radius * 2.0 * floor_glow, Color(MOSS, 0.14 * floor_glow))
	_shockwave(canvas, at, radius, progress)
	for ring in 2:
		_thorns(canvas, fx, at, radius, progress, ring)
	_leaves(canvas, fx, at, radius, progress)
	_antlers(canvas, at, radius, progress, fade, elapsed_ms)


## How far ring `ring`'s thorns stand out of the ground, 0..1: the inner
## ring rises first, the outer a beat later, and each sinks back in turn.
static func thorn_height(progress: float, ring: int) -> float:
	var start := 0.06 + ring * 0.12
	var rise := FxKit.ease_out(FxKit.phase(progress, start, start + 0.12))
	var sink := FxKit.ease_in(FxKit.phase(progress, 0.5 + ring * 0.08, 0.78 + ring * 0.08))
	return rise * (1.0 - sink)


## A bright ring racing to the edge in the first beat, a darker echo behind it.
static func _shockwave(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var t := FxKit.phase(progress, 0.0, 0.3)
	if t <= 0.0 or t >= 1.0:
		return
	var reach := radius * FxKit.ease_out(t)
	Fx.ring(canvas, at, reach, 12.0, Color(SAP, 0.25 * (1.0 - t)))
	Fx.ring(canvas, at, reach, 3.0, Color(LIME, 0.9 * (1.0 - t)))
	Fx.ring(canvas, at, reach * 0.82, 2.0, Color(MOSS, 0.7 * (1.0 - t)))


## A ring of thorns erupting from the ground, leaning up and out like a
## crown, each a bark wedge with a mossy body and a bright tip. The second
## ring stands further out and a beat later; both sink back before the end.
static func _thorns(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float,
		ring: int) -> void:
	var height := thorn_height(progress, ring)
	if height <= 0.0:
		return
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx) + ring * 31)
	var distance := radius * (0.42 + 0.4 * ring)
	for i in THORNS:
		var angle := TAU * (i + 0.5 * ring) / THORNS + rng.randf_range(-0.12, 0.12)
		var out := Vector2(cos(angle), sin(angle))
		var base := at + out * distance * rng.randf_range(0.92, 1.06)
		var lean := (out * 0.55 + Vector2(0.0, -1.0)).normalized()
		var length := radius * rng.randf_range(0.2, 0.32) * height
		var tip := base + lean * length
		var width := radius * 0.09
		FxKit.taper(canvas, base, tip, width * 1.4, 0.0, Color(BARK, 0.85))
		FxKit.taper(canvas, base, tip, width, 0.0, Color(MOSS, 0.95))
		FxKit.taper(canvas, base.lerp(tip, 0.45), tip, width * 0.35, 0.0, Color(LIME, 0.9))
		Fx.dot(canvas, base, width * 2.2, Color(BARK, 0.35 * height))


## Leaves flung outward in a spinning vortex: each a lens with a vein,
## turning as it flies and thinning out at the edge.
static func _leaves(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx) + 97)
	for i in LEAVES:
		var born := rng.randf_range(0.02, 0.4)
		var a0 := rng.randf() * TAU
		var size := rng.randf_range(6.0, 10.0)
		var spin := rng.randf_range(4.0, 9.0) * (1.0 if i % 2 == 0 else -1.0)
		var t := FxKit.phase(progress, born, born + 0.5)
		if t <= 0.0 or t >= 1.0:
			continue
		var heading := a0 + t * 2.4
		var spot := Fx.polar(at, heading, radius * (0.12 + 0.95 * FxKit.ease_out(t)))
		var turn := heading + spin * t
		var alpha := sin(t * PI)
		var colour := LIME if i % 3 == 0 else SAP
		Fx.polygon(canvas, FxBladeShapes.lens(spot, turn, size, size * 0.42), Color(MOSS, 0.6 * alpha))
		Fx.polygon(canvas, FxBladeShapes.lens(spot, turn, size * 0.8, size * 0.3), Color(colour, 0.95 * alpha))
		Fx.line(canvas, Fx.polar(spot, turn, -size * 0.7), Fx.polar(spot, turn, size * 0.7), 1.0,
			Color(MOSS, alpha))


## Spirit antlers rising from the Druid's head: each beam sweeps up and out,
## its tines sprouting in turn as it grows, all glowing and flickering.
static func _antlers(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float,
		elapsed_ms: int) -> void:
	var grow := FxKit.ease_out(FxKit.phase(progress, 0.08, 0.45))
	if grow <= 0.0 or fade <= 0.0:
		return
	var size := clampf(radius * 0.3, 22.0, 40.0)
	var head := at + Vector2(0.0, -size * 0.55)
	var flicker := 0.85 + 0.15 * sin(elapsed_ms * 0.02)
	var alpha := fade * flicker
	Fx.dot(canvas, head + Vector2(0.0, -size * 0.5), size * 3.4 * grow, Color(SAP, 0.16 * alpha))
	for side: float in [-1.0, 1.0]:
		var root := head + Vector2(side * size * 0.18, 0.0)
		var beam := PackedVector2Array()
		var steps := 8
		for s in steps + 1:
			var f := float(s) / steps * grow
			beam.append(root + Vector2(side * size * (0.1 + 1.1 * f - 0.3 * f * f), -size * (0.55 * f + 0.6 * f * f)))
		Fx.polyline(canvas, beam, 7.0, Color(SAP, 0.3 * alpha))
		Fx.polyline(canvas, beam, 3.5, Color(LIME, 0.9 * alpha))
		Fx.polyline(canvas, beam, 1.2, Color(Color.WHITE, 0.8 * alpha))
		for tine: Vector3 in TINES:
			if grow < tine.x:
				continue
			var sprout := FxKit.ease_out(clampf((grow - tine.x) / 0.25, 0.0, 1.0))
			var on_beam := beam[int(round(tine.x / grow * steps))]
			var dir := Vector2(side * tine.y, -1.0).normalized()
			var tip := on_beam + dir * size * tine.z * sprout
			Fx.line(canvas, on_beam, tip, 7.0, Color(SAP, 0.3 * alpha))
			FxKit.taper(canvas, on_beam, tip, 3.0, 0.0, Color(LIME, 0.95 * alpha))
		FxKit.glint(canvas, beam[steps], size * 0.5 * grow, elapsed_ms * 0.003, GOLD, 0.8 * alpha)
