class_name FxPriestHealingTouch
extends RefCounted

## PRIEST_HEALING_TOUCH (97): a lotus blooming on the spot. Eight outer
## petals unfold from a closed bud pointing up into a full ring, eight
## inner petals open after them between, the centre glows warm white, and
## green-white motes lift off the open flower before it closes and fades.

const LEAF := Color("5fcf86")
const MINT := Color("b8f5cc")
const BLUSH := Color("fff0f4")
const DARK := Color("12301e")
const PETALS := 8
const MOTES := 12


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 24.0)
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	var outer := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.4))
	var inner := FxKit.ease_out(FxKit.phase(progress, 0.15, 0.5))
	var breathe := 1.0 + 0.04 * sin(elapsed_ms * 0.01)
	Fx.dot(canvas, at, radius * 2.0 * outer, Color(LEAF, 0.1 * fade))
	Fx.ring(canvas, at, radius * outer, 2.0, Color(MINT, 0.4 * fade))
	_petals(canvas, at, radius * 0.75 * breathe, outer, 0.0, LEAF, MINT, fade)
	_petals(canvas, at, radius * 0.48 * breathe, inner, PI / PETALS, MINT, BLUSH, fade)
	var glow := FxKit.ease_out(FxKit.phase(progress, 0.2, 0.5)) * fade
	Fx.dot(canvas, at, radius * 0.5 * glow, Color(MINT, 0.5 * glow))
	Fx.dot(canvas, at, radius * 0.25 * glow, Color(BLUSH, glow))
	FxKit.glint(canvas, at, radius * 0.35 * glow, elapsed_ms * 0.002, BLUSH, glow)
	_motes(canvas, fx, at, radius, progress)


## A whorl of petals: each a rounded petal from the centre, swinging from
## straight up (the bud) to its place in the ring and lengthening as it opens.
static func _petals(canvas: CanvasItem, at: Vector2, length: float, open: float, offset: float,
		fill: Color, edge: Color, fade: float) -> void:
	if open <= 0.0:
		return
	for i in PETALS:
		var settled := -PI * 0.5 + offset + TAU * i / PETALS
		var angle := lerp_angle(-PI * 0.5, settled, open)
		var reach := length * (0.35 + 0.65 * open)
		var shape := _petal(at, angle, reach, reach * 0.26)
		Fx.polygon(canvas, _petal(at, angle, reach * 1.08, reach * 0.31), Color(DARK, 0.35 * fade))
		Fx.polygon(canvas, shape, Color(fill, 0.75 * fade))
		FxBladeShapes.outline(canvas, shape, 1.5, Color(edge, 0.9 * fade))
		Fx.line(canvas, at, Fx.polar(at, angle, reach * 0.8), 1.0, Color(edge, 0.5 * fade))


## A petal from `at` along `angle`: narrow at the base, broadest past the
## middle, closing to a soft point at the tip.
static func _petal(at: Vector2, angle: float, length: float, width: float) -> Array:
	var along := Vector2(cos(angle), sin(angle))
	var across := along.orthogonal()
	var left: Array = []
	var right: Array = []
	for i in 9:
		var f := float(i) / 8.0
		var half := width * pow(sin(PI * pow(f, 0.8)), 0.7)
		left.append(at + along * length * f + across * half)
		right.push_front(at + along * length * f - across * half)
	return left + right


## Motes lifting from the open flower, swaying a little.
static func _motes(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in MOTES:
		var born := rng.randf_range(0.3, 0.6)
		var spot := Fx.polar(at, rng.randf() * TAU, rng.randf() * radius * 0.7)
		var rise := rng.randf_range(16.0, 32.0)
		var sway := rng.randf() * TAU
		var t := FxKit.phase(progress, born, born + 0.4)
		if t <= 0.0 or t >= 1.0:
			continue
		var mote := spot + Vector2(sin(t * 5.0 + sway) * 3.0, -rise * t)
		Fx.dot(canvas, mote, 4.0, Color(LEAF, 0.45 * (1.0 - t)))
		Fx.dot(canvas, mote, 2.0, Color(BLUSH, 1.0 - t))
