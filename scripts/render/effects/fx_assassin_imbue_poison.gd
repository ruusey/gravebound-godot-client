class_name FxAssassinImbuePoison
extends RefCounted

## ASSASSIN_IMBUE_POISON (80): a venom coat riding the Assassin. Two green
## venom strands coil up round the body as a double helix (the front strand
## over, the back strand dimmer), a sickly pool spreads at the feet with
## bubbles welling up and popping, and fat drops gather at the blade hand
## and fall, each splashing a tiny ring in the pool.

const VENOM := Color("7cf040")
const BILE := Color("3a9a20")
const DEEP := Color("123a10")
const FOAM := Color("e4ffc0")
const COILS := 1.4
const BUBBLES := 6
const DROPS := 3


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var grow := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.25))
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	var feet := at + Vector2(0.0, radius * 0.5)
	_pool(canvas, feet, radius, grow * fade, elapsed_ms)
	_helix(canvas, feet, radius, progress, grow, fade, elapsed_ms, false)
	_bubbles(canvas, fx, feet, radius, progress, fade)
	_drops(canvas, at, feet, radius, progress, fade)
	_helix(canvas, feet, radius, progress, grow, fade, elapsed_ms, true)


## The pool at the feet: a dark flattened disc with a lit green rim that
## wobbles.
static func _pool(canvas: CanvasItem, feet: Vector2, radius: float, alpha: float, elapsed_ms: int) -> void:
	if alpha <= 0.0:
		return
	var points: Array = []
	var rim := PackedVector2Array()
	for i in 24:
		var angle := TAU * i / 24.0
		var wobble := 1.0 + 0.08 * sin(angle * 3.0 + elapsed_ms * 0.006)
		var p := feet + Vector2(cos(angle) * radius * 0.9, sin(angle) * radius * 0.35) * wobble
		points.append(p)
		rim.append(p)
	rim.append(rim[0])
	Fx.polygon(canvas, points, Color(DEEP, 0.7 * alpha))
	Fx.polyline(canvas, rim, 3.0, Color(BILE, 0.9 * alpha))


## One half of the helix: points round an ellipse climbing the body, only
## the stretches on this side (front or back) drawn.
static func _helix(canvas: CanvasItem, feet: Vector2, radius: float, progress: float, grow: float,
		fade: float, elapsed_ms: int, front: bool) -> void:
	var spin := elapsed_ms * 0.006
	var height := radius * 1.7 * grow
	for strand in 2:
		var run := PackedVector2Array()
		var steps := 24
		for i in steps + 1:
			var f := float(i) / steps
			var angle := spin + f * TAU * COILS + strand * PI
			var is_front := sin(angle) > 0.0
			var p := feet + Vector2(cos(angle) * radius * 0.75 * (1.0 - 0.3 * f), sin(angle) * radius * 0.25
				- height * f)
			if is_front == front:
				run.append(p)
			elif run.size() > 0:
				_strand(canvas, run, front, fade)
				run = PackedVector2Array()
		_strand(canvas, run, front, fade)


static func _strand(canvas: CanvasItem, run: PackedVector2Array, front: bool, fade: float) -> void:
	if run.size() < 2:
		return
	var a := fade * (1.0 if front else 0.45)
	Fx.polyline(canvas, run, 8.0, Color(BILE, 0.6 * a))
	Fx.polyline(canvas, run, 3.5, Color(VENOM, a))
	if front:
		Fx.polyline(canvas, run, 1.0, Color(FOAM, 0.7 * a))


## Bubbles welling up in the pool, swelling, then popping into a ring.
static func _bubbles(canvas: CanvasItem, fx: Dictionary, feet: Vector2, radius: float, progress: float,
		fade: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in BUBBLES:
		var spot := feet + Vector2(rng.randf_range(-0.7, 0.7) * radius, rng.randf_range(-0.2, 0.2) * radius)
		var t := fposmod(progress * 3.0 + rng.randf(), 1.0)
		if t < 0.75:
			var size := 2.0 + 6.0 * t
			Fx.dot(canvas, spot - Vector2(0.0, size * 0.25), size, Color(VENOM, 0.75 * fade))
			Fx.dot(canvas, spot - Vector2(size * 0.15, size * 0.4), size * 0.35, Color(FOAM, 0.9 * fade))
		else:
			var pop := (t - 0.75) / 0.25
			Fx.ring(canvas, spot, 3.0 + 4.0 * pop, 1.5, Color(FOAM, (1.0 - pop) * fade))


## Venom gathering at the blade hand and dropping into the pool in turn,
## a splash ring where each lands.
static func _drops(canvas: CanvasItem, at: Vector2, feet: Vector2, radius: float, progress: float,
		fade: float) -> void:
	var hand := at + Vector2(radius * 0.55, -radius * 0.1)
	var floor_y := feet.y
	for i in DROPS:
		var t := fposmod(progress * 2.0 - i / float(DROPS), 1.0)
		if t < 0.45:
			var swell := t / 0.45
			Fx.dot(canvas, hand + Vector2(0.0, swell * 2.0), 4.0 + 4.0 * swell, Color(VENOM, fade))
		elif t < 0.75:
			var fall := (t - 0.45) / 0.3
			var drop := Vector2(hand.x, lerpf(hand.y, floor_y, fall * fall))
			Fx.line(canvas, drop - Vector2(0.0, 5.0), drop, 3.0, Color(VENOM, 0.6 * fade))
			Fx.dot(canvas, drop, 7.0, Color(VENOM, fade))
		else:
			var splash := (t - 0.75) / 0.25
			var spot := Vector2(hand.x, floor_y)
			Fx.ring(canvas, spot, 2.0 + 7.0 * splash, 2.0, Color(VENOM, (1.0 - splash) * fade))
