class_name FxDuelistRiposte
extends RefCounted

## DUELIST_RIPOSTE (85): the counter-slash once the guard drops. The blade's
## point traces one full circle round the Duelist -- a fencer's circular
## parry -- its bright head chased by a gilded trail. When the circle closes
## it blazes into a ring that bursts outward, eight counter-cuts flick out
## from it, alternating long and short, and steel sparks scatter.

const GOLD := Color("f4d27a")
const IVORY := Color("fff6e0")
const CRIMSON := Color("c8283c")
const STEEL := Color("c9d3de")
const TRAIL := 10
const CUTS := 8
const DRAW_END := 0.42


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 24.0)
	var start := Fx.facing(fx).angle() - PI * 0.5
	_circle(canvas, at, radius, start, progress)
	_blaze(canvas, at, radius, progress)
	_cuts(canvas, at, radius, start, progress)
	FxKit.sparks(canvas, at, Vector2.UP, TAU, 10, radius * 1.1, FxKit.phase(progress, DRAW_END, 0.95), 14.0,
		1.5, STEEL, 0.9, FxKit.seed_of(fx))


## The point sweeping round: a head of light and a trail of segments that
## dim and thin behind it, the drawn circle left faint in gold.
static func _circle(canvas: CanvasItem, at: Vector2, radius: float, start: float, progress: float) -> void:
	var drawn := FxKit.ease_in_out(FxKit.phase(progress, 0.0, DRAW_END))
	var fade := 1.0 - FxKit.phase(progress, DRAW_END, DRAW_END + 0.15)
	if drawn <= 0.0 or fade <= 0.0:
		return
	var head := start + TAU * drawn
	Fx.arc(canvas, at, start, head, radius, maxi(4, int(48 * drawn)), 5.0, Color(GOLD, 0.25 * fade))
	Fx.arc(canvas, at, start, head, radius, maxi(4, int(48 * drawn)), 2.0, Color(GOLD, 0.7 * fade))
	var step := 0.09
	for i in TRAIL:
		var a1 := head - i * step
		var a0 := a1 - step
		if a0 < start:
			break
		var k := 1.0 - float(i) / TRAIL
		Fx.arc(canvas, at, a0, a1, radius, 2, 2.0 + 5.0 * k, Color(IVORY.lerp(GOLD, 1.0 - k), k * fade))
	var tip := Fx.polar(at, head, radius)
	FxKit.glint(canvas, tip, 14.0, head, IVORY, fade)


## The closed circle flaring into a ring that bursts outward, with a
## crimson echo just inside it.
static func _blaze(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var t := FxKit.phase(progress, DRAW_END, 1.0)
	if t <= 0.0:
		return
	var flash := FxKit.pulse(progress, DRAW_END, DRAW_END + 0.06, 0.7)
	var grow := radius * (1.0 + 0.35 * FxKit.ease_out(t))
	Fx.ring(canvas, at, grow, 10.0 * flash + 3.0, Color(GOLD, (1.0 - t) * 0.9))
	Fx.ring(canvas, at, grow, 2.0, Color(Color.WHITE, (1.0 - t)))
	Fx.ring(canvas, at, grow * 0.82, 2.0, Color(CRIMSON, (1.0 - t) * 0.7))
	Fx.dot(canvas, at, radius * 0.9 * flash, Color(IVORY, flash * 0.25))


## Eight short slashes flicked out from the ring, long and short in turn,
## each a thin blade that grows then slides off outward.
static func _cuts(canvas: CanvasItem, at: Vector2, radius: float, start: float, progress: float) -> void:
	var t := FxKit.phase(progress, DRAW_END + 0.02, 0.85)
	if t <= 0.0 or t >= 1.0:
		return
	for i in CUTS:
		var angle := start + TAU * i / CUTS + 0.2
		var out := Vector2(cos(angle), sin(angle))
		var length := radius * (0.55 if i % 2 == 0 else 0.32)
		var base := at + out * radius * (1.0 + 0.4 * FxKit.ease_out(t))
		var tilt := out.rotated(0.35)
		FxKit.taper(canvas, base, base + tilt * length * (0.4 + 0.6 * FxKit.ease_out(t)), 4.0, 0.0,
			Color(IVORY, 1.0 - t))
