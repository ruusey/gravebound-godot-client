class_name FxPaladinFortify
extends RefCounted

## PALADIN_FORTIFY (94): a shield-wall forming round the Paladin, following
## them. Six hexagonal plates rise from the ground in turn and settle in a
## ring, struts lock them into a lattice, a gold pulse runs once round the
## locked wall, and the plates sink and fade at the end.

const GOLD := Color("f2c75a")
const IVORY := Color("fff4d8")
const STEEL := Color("8fa3bd")
const DARK := Color("1a1c26")
const PLATES := 6
const RISE := 0.12
const LOCK_START := 0.45


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 32.0)
	var ring := radius * 0.7
	var plate := radius * 0.2
	var fade := 1.0 - FxKit.phase(progress, 0.8, 1.0)
	var lock := FxKit.ease_out(FxKit.phase(progress, LOCK_START, LOCK_START + 0.15))
	Fx.dot(canvas, at, ring * 2.2, Color(GOLD, 0.08 * lock * fade))
	var spots: Array[Vector2] = []
	for i in PLATES:
		spots.append(Fx.polar(at, -PI * 0.5 + TAU * i / PLATES, ring))
	_lattice(canvas, at, spots, lock, fade)
	_pulse(canvas, at, ring, progress, fade)
	for i in PLATES:
		var t := FxKit.phase(progress, i * 0.05, i * 0.05 + RISE)
		if t <= 0.0:
			continue
		var lift := (1.0 - FxKit.ease_out(t)) * 14.0 + (1.0 - fade) * 6.0
		_plate(canvas, spots[i] + Vector2(0.0, lift), plate, FxKit.ease_out(t) * fade,
			FxKit.pulse(progress, i * 0.05 + RISE * 0.7, i * 0.05 + RISE, i * 0.05 + RISE + 0.1))


## One plate: a steel hexagon with a gold rim and a small cross boss, a
## flash as it settles.
static func _plate(canvas: CanvasItem, at: Vector2, size: float, alpha: float, settle: float) -> void:
	if alpha <= 0.0:
		return
	var hex := []
	for k in 6:
		hex.append(Fx.polar(at, TAU * k / 6.0, size))
	Fx.polygon(canvas, hex, Color(DARK, 0.45 * alpha))
	var inner := []
	for k in 6:
		inner.append(Fx.polar(at, TAU * k / 6.0, size * 0.8))
	Fx.polygon(canvas, inner, Color(STEEL, 0.55 * alpha))
	FxBladeShapes.outline(canvas, hex, 2.5, Color(GOLD, alpha))
	var arm := size * 0.35
	Fx.line(canvas, at + Vector2(0.0, -arm), at + Vector2(0.0, arm), 2.0, Color(IVORY, alpha))
	Fx.line(canvas, at + Vector2(-arm * 0.7, -arm * 0.2), at + Vector2(arm * 0.7, -arm * 0.2), 2.0,
		Color(IVORY, alpha))
	if settle > 0.0:
		Fx.dot(canvas, at, size * 3.0 * settle, Color(IVORY, 0.4 * settle))


## Struts between neighbouring plates and spokes to the centre, drawn out
## from each plate as the wall locks.
static func _lattice(canvas: CanvasItem, at: Vector2, spots: Array[Vector2], lock: float, fade: float) -> void:
	if lock <= 0.0:
		return
	for i in PLATES:
		var a := spots[i]
		var b := spots[(i + 1) % PLATES]
		var mid := a.lerp(b, 0.5)
		for end: Vector2 in [a, b]:
			Fx.line(canvas, end, end.lerp(mid, lock), 4.0, Color(DARK, 0.4 * fade))
			Fx.line(canvas, end, end.lerp(mid, lock), 2.0, Color(GOLD, 0.85 * fade))
		Fx.line(canvas, a, a.lerp(at, 0.55 * lock), 1.2, Color(GOLD, 0.35 * fade))


## A bright pulse running once round the locked wall.
static func _pulse(canvas: CanvasItem, at: Vector2, ring: float, progress: float, fade: float) -> void:
	var t := FxKit.phase(progress, LOCK_START + 0.1, LOCK_START + 0.4)
	if t <= 0.0 or t >= 1.0:
		return
	var head := -PI * 0.5 + TAU * FxKit.ease_in_out(t)
	var glow := sin(t * PI) * fade
	Fx.arc(canvas, at, head - 0.8, head, ring, 8, 6.0, Color(GOLD, 0.35 * glow))
	Fx.arc(canvas, at, head - 0.4, head, ring, 6, 2.5, Color(IVORY, 0.9 * glow))
	FxKit.glint(canvas, Fx.polar(at, head, ring), 14.0, head, IVORY, glow)
