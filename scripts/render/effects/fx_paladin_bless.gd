class_name FxPaladinBless
extends RefCounted

## PALADIN_BLESS (95): a sun sigil laid on the ground. An inscription ring
## of tick marks draws itself round the range while a second dashed band
## turns against it, twelve tapered rays -- long and short -- unfold from a
## bright sun disc and turn slowly, and white feathers drift down swaying
## through it all.

const GOLD := Color("f5c84c")
const AMBER := Color("e8902a")
const IVORY := Color("fffbea")
const RAYS := 12
const TICKS := 36
const DASHES := 18
const FEATHERS := 9


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 40.0)
	var grow := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.25))
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	var turn := elapsed_ms * 0.0006
	Fx.dot(canvas, at, radius * 2.0 * grow, Color(GOLD, 0.08 * fade))
	_inscription(canvas, at, radius, progress, turn, fade)
	_sun(canvas, at, radius * 0.6 * grow, turn, fade)
	_feathers(canvas, fx, at, radius, progress, fade)


## The outer ring: ticks drawn round clockwise, every third one long, and
## a dashed band inside turning the other way.
static func _inscription(canvas: CanvasItem, at: Vector2, radius: float, progress: float, turn: float,
		fade: float) -> void:
	var drawn := FxKit.ease_in_out(FxKit.phase(progress, 0.05, 0.35))
	if drawn <= 0.0:
		return
	var start := -PI * 0.5
	var segs := maxi(4, int(64 * drawn))
	Fx.arc(canvas, at, start, start + TAU * drawn, radius, segs, 6.0, Color(AMBER, 0.3 * fade))
	Fx.arc(canvas, at, start, start + TAU * drawn, radius, segs, 2.0, Color(GOLD, 0.95 * fade))
	for i in TICKS:
		if float(i) / TICKS > drawn:
			break
		var angle := start + TAU * i / TICKS
		var long := 8.0 if i % 3 == 0 else 4.0
		var out := Vector2(cos(angle), sin(angle))
		Fx.line(canvas, at + out * (radius - long), at + out * radius, 1.5, Color(IVORY, 0.85 * fade))
	var band := radius * 0.82
	for i in DASHES:
		var a := -turn * 2.0 + TAU * i / DASHES
		Fx.arc(canvas, at, a, a + TAU / DASHES * 0.55, band, 3, 2.0, Color(GOLD, 0.6 * drawn * fade))


## The sun: a glowing disc ringed in white, and tapered rays turning
## slowly, alternating long and short.
static func _sun(canvas: CanvasItem, at: Vector2, reach: float, turn: float, fade: float) -> void:
	if reach <= 1.0:
		return
	var core := reach * 0.3
	for i in RAYS:
		var angle := turn + TAU * i / RAYS
		var out := Vector2(cos(angle), sin(angle))
		var length := reach * (1.0 if i % 2 == 0 else 0.68)
		var root := at + out * core * 1.05
		FxKit.taper(canvas, root, at + out * length, 7.0, 0.0, Color(AMBER, 0.45 * fade))
		FxKit.taper(canvas, root, at + out * length * 0.9, 3.0, 0.0, Color(IVORY, 0.9 * fade))
	Fx.dot(canvas, at, core * 3.2, Color(GOLD, 0.4 * fade))
	Fx.dot(canvas, at, core * 2.0, Color(IVORY, 0.9 * fade))
	Fx.ring(canvas, at, core, 2.0, Color(AMBER, 0.9 * fade))


## Feathers drifting down, each a pale vane on a quill, rocking side to side.
static func _feathers(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float,
		fade: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in FEATHERS:
		var born := rng.randf_range(0.05, 0.4)
		var x := rng.randf_range(-0.85, 0.85) * radius
		var top := -rng.randf_range(0.4, 0.9) * radius
		var sway_phase := rng.randf() * TAU
		var t := FxKit.phase(progress, born, born + 0.55)
		if t <= 0.0 or t >= 1.0:
			continue
		var rock := sin(t * 7.0 + sway_phase)
		var spot := at + Vector2(x + rock * 6.0, top + t * radius * 0.7)
		var angle := -PI * 0.5 + rock * 0.6
		var alpha := FxKit.window(t, 0.0, 1.0, 0.2) * fade
		Fx.polygon(canvas, FxBladeShapes.lens(spot, angle, 9.0, 3.4), Color(IVORY, 0.9 * alpha))
		var spine := Vector2(cos(angle), sin(angle))
		Fx.line(canvas, spot - spine * 11.0, spot + spine * 7.5, 1.5, Color(GOLD, alpha))
