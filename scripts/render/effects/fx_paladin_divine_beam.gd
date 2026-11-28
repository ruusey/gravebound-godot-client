class_name FxPaladinDivineBeam
extends RefCounted

## PALADIN_DIVINE_BEAM (93): judgement from above. A needle of light drops
## out of the sky onto the spot, then swells into a column flared wide at
## the top. Where it lands a cross flare blazes, a flattened halo ripples
## out across the ground, and motes rise up the column as it narrows away.

const GOLD := Color("f6cf5c")
const IVORY := Color("fff6dc")
const AMBER := Color("e09a2c")
const DROP_END := 0.14
const SWELL_END := 0.35
const SQUASH := 0.42
const MOTES := 12


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 32.0)
	_halo(canvas, at, radius, progress)
	_column(canvas, at, radius, progress)
	_motes(canvas, fx, at, radius, progress)
	_flare(canvas, at, radius, progress)


## The light: a thin needle falling from the top, then a trapezoid column
## fading into the sky, widening to full and narrowing to nothing.
static func _column(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var height := radius * 2.4
	var top := at - Vector2(0.0, height)
	var drop := FxKit.ease_in(FxKit.phase(progress, 0.0, DROP_END))
	if progress < DROP_END:
		var head := top.lerp(at, drop)
		FxKit.glow_line(canvas, top, head, 3.0, GOLD, 0.9)
		return
	var swell := FxKit.ease_out(FxKit.phase(progress, DROP_END, SWELL_END))
	var narrow := FxKit.ease_in(FxKit.phase(progress, 0.55, 1.0))
	var width := radius * 0.32 * swell * (1.0 - narrow) + 2.0
	var alpha := 1.0 - narrow
	var layers: Array[float] = [1.6, 1.0, 0.35]
	var colours: Array[Color] = [Color(AMBER, 0.2), Color(GOLD, 0.45), Color(IVORY, 0.85)]
	for layer in 3:
		var w := width * layers[layer]
		var colour := colours[layer]
		var points := PackedVector2Array([top + Vector2(-w * 0.9, 0.0), top + Vector2(w * 0.9, 0.0),
			at + Vector2(w * 0.5, 0.0), at + Vector2(-w * 0.5, 0.0)])
		var lit := Color(colour, colour.a * alpha)
		var sky := Color(colour, 0.0)
		canvas.draw_polygon(points, PackedColorArray([sky, sky, lit, lit]))
	var spine := PackedVector2Array([top + Vector2(-1.0, 0.0), top + Vector2(1.0, 0.0), at + Vector2(1.0, 0.0),
		at + Vector2(-1.0, 0.0)])
	canvas.draw_polygon(spine, PackedColorArray([Color(Color.WHITE, 0.0), Color(Color.WHITE, 0.0),
		Color(Color.WHITE, alpha), Color(Color.WHITE, alpha)]))


## The ground halo: a flattened gold ellipse at the foot of the column and
## a ripple running out from it to the radius.
static func _halo(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var t := FxKit.phase(progress, DROP_END, 1.0)
	if t <= 0.0:
		return
	var hold := 1.0 - FxKit.phase(progress, 0.6, 1.0)
	_ellipse(canvas, at, radius * 0.35, 8.0, Color(GOLD, 0.3 * hold))
	_ellipse(canvas, at, radius * 0.35, 2.5, Color(IVORY, 0.9 * hold))
	for k in 2:
		var w := FxKit.phase(t, k * 0.2, 0.7 + k * 0.2)
		if w <= 0.0 or w >= 1.0:
			continue
		var r := radius * (0.35 + 0.65 * FxKit.ease_out(w))
		_ellipse(canvas, at, r, 3.0, Color(GOLD, 0.8 * (1.0 - w)))


## Motes lifting up the column after it lands.
static func _motes(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in MOTES:
		var born := DROP_END + rng.randf_range(0.0, 0.45)
		var t := FxKit.phase(progress, born, born + 0.45)
		var offset := rng.randf_range(-0.2, 0.2) * radius
		var climb := radius * rng.randf_range(1.2, 2.2)
		if t <= 0.0 or t >= 1.0:
			continue
		var mote := at + Vector2(offset * (1.0 - 0.5 * t), -climb * FxKit.ease_out(t))
		Fx.dot(canvas, mote, 4.0, Color(GOLD, 0.5 * (1.0 - t)))
		Fx.dot(canvas, mote, 2.0, Color(IVORY, 1.0 - t))


## The strike: a long cross flare -- tall vertical, wide horizontal -- and a
## round flash, at the moment the needle hits.
static func _flare(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var hit := FxKit.pulse(progress, DROP_END - 0.01, DROP_END + 0.04, 0.5)
	if hit <= 0.0:
		return
	var tall := radius * 0.9 * hit
	var wide := radius * 1.2 * hit
	var arms: Array[Vector2] = [Vector2(0.0, -tall), Vector2(0.0, tall * 0.5), Vector2(-wide, 0.0), Vector2(wide, 0.0)]
	for arm: Vector2 in arms:
		FxKit.taper(canvas, at, at + arm, 6.0, 0.0, Color(GOLD, 0.5 * hit))
		FxKit.taper(canvas, at, at + arm * 0.8, 2.5, 0.0, Color(Color.WHITE, 0.95 * hit))
	Fx.dot(canvas, at, radius * 0.5 * hit, Color(IVORY, 0.6 * hit))


## A ring squashed to lie flat on the ground.
static func _ellipse(canvas: CanvasItem, at: Vector2, radius: float, width_px: float, colour: Color) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		points.append(at + Vector2(cos(a) * radius, sin(a) * radius * SQUASH))
	Fx.polyline(canvas, points, width_px, colour)
