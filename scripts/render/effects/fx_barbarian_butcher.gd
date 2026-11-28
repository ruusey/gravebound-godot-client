class_name FxBarbarianButcher
extends RefCounted

## BARBARIAN_BUTCHER (75): a cleaver's crescent hacked across the strike
## point. A heavy crimson crescent with a bright steel edge sweeps about
## 160 degrees across the facing in the first third, smear wedges trailing
## its head; blood is flung off along the arc as it passes, and three
## crimson gashes are left across the ground where it bit (BLEEDING),
## lingering after the swing has burnt off.

const BLOOD := Color("8a1414")
const CRIMSON := Color("d02828")
const STEEL := Color("e8e4dc")
const DARK := Color("1a0806")
const SWEEP := 2.8
const SWING_END := 0.35


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var dir := Fx.facing(fx)
	var radius: float = maxf(fx["radius"], 32.0)
	var pivot := at - dir * radius * 0.55
	var reach := radius * 1.0
	var start := dir.angle() - SWEEP * 0.5
	var head := start + SWEEP * FxKit.ease_out(FxKit.phase(progress, 0.0, SWING_END))
	var tail := start + SWEEP * FxKit.ease_in_out(FxKit.phase(progress, 0.12, 0.6))
	_gashes(canvas, at, dir, radius, progress)
	if head > tail + 0.02:
		var fade := 1.0 - FxKit.phase(progress, 0.32, 0.5)
		_crescent(canvas, pivot, tail, head, reach + 4.0, radius * 0.52, Color(DARK, 0.55 * fade))
		_crescent(canvas, pivot, tail, head, reach, radius * 0.46, Color(BLOOD, 0.85 * fade))
		_crescent(canvas, pivot, tail, head, reach, radius * 0.18, Color(CRIMSON, 0.9 * fade))
		Fx.arc(canvas, pivot, maxf(tail, head - 1.2), head, reach, 12, 3.0, Color(STEEL, fade))
		_smears(canvas, pivot, head, reach, radius, fade)
	_blood(canvas, fx, pivot, start, reach, progress)


## A filled crescent between `tail` and `head` round `pivot`: thickest
## behind the head, coming to a point at both ends.
static func _crescent(canvas: CanvasItem, pivot: Vector2, tail: float, head: float, reach: float,
		thickness: float, colour: Color) -> void:
	if colour.a <= 0.001 or (head - tail) * reach < 4.0:
		return
	var steps := 18
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var f := float(i) / steps
		var angle := lerpf(tail, head, f)
		var width := thickness * pow(f, 0.8) * (1.0 - pow(f, 8.0))
		outer.append(Fx.polar(pivot, angle, reach))
		if i > 0 and i < steps:
			inner.append(Fx.polar(pivot, angle, reach - width))
	inner.reverse()
	outer.append_array(inner)
	canvas.draw_colored_polygon(outer, colour)


## Four motion-smear wedges trailing the head of the swing, outside the arc.
static func _smears(canvas: CanvasItem, pivot: Vector2, head: float, reach: float, radius: float,
		fade: float) -> void:
	for i in 4:
		var angle := head - 0.18 - i * 0.2
		var from := Fx.polar(pivot, angle, reach + 3.0 + i * 2.0)
		var tangent := Vector2(-sin(angle), cos(angle))
		FxKit.taper(canvas, from, from - tangent * radius * (0.5 - i * 0.08), 3.0, 0.0,
			Color(STEEL, fade * (0.55 - i * 0.1)))


## Blood flung along the arc's tangent from where the edge passed.
static func _blood(canvas: CanvasItem, fx: Dictionary, pivot: Vector2, start: float, reach: float,
		progress: float) -> void:
	var t := FxKit.phase(progress, 0.08, 0.85)
	if t <= 0.0 or t >= 1.0:
		return
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in 12:
		var angle := start + SWEEP * rng.randf_range(0.15, 0.95)
		var tangent := Vector2(-sin(angle), cos(angle)).rotated(rng.randf_range(-0.4, 0.2))
		var speed := reach * rng.randf_range(0.5, 1.1)
		var size := rng.randf_range(2.0, 4.5)
		var at := Fx.polar(pivot, angle, reach) + tangent * speed * FxKit.ease_out(t) + Vector2(0.0, 30.0 * t * t)
		Fx.dot(canvas, at, size + 1.5, Color(DARK, (1.0 - t) * 0.6))
		Fx.dot(canvas, at, size, Color(CRIMSON, 1.0 - t))


## Three parallel gashes across the strike, opening as the edge passes and
## lingering until the end.
static func _gashes(canvas: CanvasItem, at: Vector2, dir: Vector2, radius: float, progress: float) -> void:
	var open := FxKit.ease_out(FxKit.phase(progress, 0.15, 0.4))
	if open <= 0.0:
		return
	var fade := 1.0 - FxKit.phase(progress, 0.6, 1.0)
	var across := dir.orthogonal().rotated(-0.5)
	for i in 3:
		var centre := at + dir * (i - 1) * radius * 0.18
		var half := across * radius * (0.45 - absf(i - 1) * 0.1) * open
		Fx.line(canvas, centre - half, centre + half, 6.0, Color(DARK, 0.6 * fade))
		Fx.line(canvas, centre - half * 0.9, centre + half * 0.9, 3.0, Color(CRIMSON, 0.95 * fade))
		Fx.line(canvas, centre - half * 0.5, centre + half * 0.5, 1.0, Color(Color("ff9080"), 0.8 * fade))
