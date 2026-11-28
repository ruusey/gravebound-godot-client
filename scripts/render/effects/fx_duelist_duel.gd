class_name FxDuelistDuel
extends RefCounted

## DUELIST_DUEL (86): the challenge, drawn from the Duelist (`pos`) to the
## enemy they call out (`target`). A gold thread unspools between them with
## a spark running along it. Over the foe two rapiers swing in and cross
## with a clash of light, and a crimson dueling circle draws itself round it,
## tick-marked like a fencing piste, before everything fades but the circle.

const GOLD := Color("f4d27a")
const IVORY := Color("fff6e0")
const CRIMSON := Color("c8283c")
const STEEL := Color("c9d3de")
const TICKS := 12


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var foe := FxKit.line_end(fx, 96.0)
	var radius: float = clampf(fx["radius"], 20.0, 80.0)
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	_thread(canvas, from, foe, progress)
	_circle(canvas, foe, radius, progress, fade)
	_blades(canvas, foe + Vector2(0.0, -radius * 0.55), radius * 0.6, progress, fade)


## A gold thread from the Duelist to the foe, laid down in the first
## quarter with a gentle wave, a spark riding it, gone by two thirds.
static func _thread(canvas: CanvasItem, from: Vector2, to: Vector2, progress: float) -> void:
	var laid := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.25))
	var fade := 1.0 - FxKit.phase(progress, 0.45, 0.7)
	if laid <= 0.0 or fade <= 0.0:
		return
	var across := (to - from).normalized().orthogonal()
	var points := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var f := float(i) / steps * laid
		var wave := sin(f * TAU * 1.5 + progress * 10.0) * 3.0 * (1.0 - f)
		points.append(from.lerp(to, f) + across * wave)
	FxKit.glow_path(canvas, points, 1.5, GOLD, fade * 0.9)
	FxKit.glint(canvas, points[points.size() - 1], 9.0, progress * 6.0, IVORY, fade)


## The dueling circle round the foe: an arc that sweeps closed, then holds
## with tick marks while the rest fades.
static func _circle(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var drawn := FxKit.ease_in_out(FxKit.phase(progress, 0.15, 0.45))
	if drawn <= 0.0:
		return
	var start := -PI * 0.5
	Fx.arc(canvas, at, start, start + TAU * drawn, radius, maxi(4, int(48 * drawn)), 6.0, Color(CRIMSON, 0.35 * fade))
	Fx.arc(canvas, at, start, start + TAU * drawn, radius, maxi(4, int(48 * drawn)), 2.0, Color(CRIMSON, 0.95 * fade))
	for i in TICKS:
		var angle := start + TAU * i / TICKS
		if float(i) / TICKS > drawn:
			break
		var out := Vector2(cos(angle), sin(angle))
		var long := 6.0 if i % 3 == 0 else 3.0
		Fx.line(canvas, at + out * radius, at + out * (radius + long), 1.5, Color(GOLD, fade * 0.9))


## Two rapiers swinging in from either side to cross point-up over the foe,
## a clash of light as they meet.
static func _blades(canvas: CanvasItem, at: Vector2, size: float, progress: float, fade: float) -> void:
	var swing := FxKit.ease_out(FxKit.phase(progress, 0.2, 0.42))
	if swing <= 0.0:
		return
	for s: float in [-1.0, 1.0]:
		var lean := lerpf(PI * 0.55, PI * 0.22, swing) * s
		var dir := Vector2.UP.rotated(lean)
		var pommel := at - dir * size * 0.55 + Vector2(-s * size * 0.15, 0.0)
		var tip := pommel + dir * size * 1.4
		Fx.line(canvas, pommel, tip, 5.0, Color(Color.BLACK, 0.55 * fade))
		Fx.line(canvas, pommel, tip, 3.0, Color(STEEL, fade))
		Fx.line(canvas, pommel.lerp(tip, 0.6), tip, 1.5, Color(Color.WHITE, fade))
		var guard := pommel.lerp(tip, 0.2)
		var across := dir.orthogonal() * size * 0.16
		Fx.line(canvas, guard - across, guard + across, 3.5, Color(GOLD, fade))
	var clash := FxKit.pulse(progress, 0.4, 0.45, 0.7)
	FxKit.glint(canvas, at, size * 1.3 * clash, progress * 3.0, IVORY, clash)
