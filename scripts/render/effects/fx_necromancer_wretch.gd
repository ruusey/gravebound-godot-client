class_name FxNecromancerWretch
extends RefCounted

## NECROMANCER_WRETCH (91): a skeletal arm lunging from the Necromancer
## (`pos`) to the target (`target`). A spine of vertebrae unrolls along the
## line, a bony hand at its head with four splayed two-jointed fingers that
## clench shut on arrival with a burst of green miasma, then the arm
## crumbles back while the miasma drifts.

const BONE := Color("e8e0c8")
const DARK := Color("1c1410")
const MIASMA := Color("6fd46a")
const PALE := Color("c8ffb0")
const FINGERS: Array[float] = [-0.95, -0.35, 0.3, 0.9]
const REACH_END := 0.38
const CLENCH_END := 0.55


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx, 64.0)
	var span := to - from
	var dir := span.normalized() if span.length() > 1.0 else Vector2.RIGHT
	var size: float = clampf(fx["radius"], 16.0, 48.0)
	var reach := FxKit.ease_out(FxKit.phase(progress, 0.0, REACH_END))
	var crumble := FxKit.ease_in(FxKit.phase(progress, 0.6, 1.0))
	var head := from.lerp(to, reach * (1.0 - 0.3 * crumble))
	_miasma(canvas, fx, from, to, dir, size, progress)
	_spine(canvas, from, head, dir, progress, 1.0 - crumble)
	var clench := FxKit.ease_in_out(FxKit.phase(progress, REACH_END - 0.04, CLENCH_END))
	_hand(canvas, head, dir, size * 0.55, clench, 1.0 - crumble)


## Vertebrae every few pixels from the caster to the hand, the arm
## wavering slightly as it reaches.
static func _spine(canvas: CanvasItem, from: Vector2, head: Vector2, dir: Vector2, progress: float,
		alpha: float) -> void:
	var length := from.distance_to(head)
	if length < 2.0 or alpha <= 0.0:
		return
	var across := dir.orthogonal()
	var points := PackedVector2Array()
	var count := maxi(2, int(length / 5.0))
	for i in count + 1:
		var f := float(i) / count
		points.append(from.lerp(head, f) + across * sin(f * TAU + progress * 12.0) * 2.0 * (1.0 - f))
	Fx.polyline(canvas, points, 5.0, Color(DARK, 0.6 * alpha))
	Fx.polyline(canvas, points, 2.0, Color(BONE, 0.7 * alpha))
	for i in range(1, points.size() - 1):
		var k := float(i) / points.size()
		Fx.dot(canvas, points[i], 3.0 + 2.0 * k, Color(BONE, alpha * (0.5 + 0.5 * k)))


## The hand: a palm knuckle and four fingers, each two bones; clenching
## folds the first joint in toward the axis and the second back on itself.
static func _hand(canvas: CanvasItem, at: Vector2, dir: Vector2, size: float, clench: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var base := dir.angle()
	Fx.dot(canvas, at, size * 1.1, Color(DARK, 0.5 * alpha))
	Fx.dot(canvas, at, size * 0.7, Color(BONE, alpha))
	for spread: float in FINGERS:
		var root := Fx.polar(at, base + spread * 1.2, size * 0.25)
		var a1 := base + spread * (1.0 - 0.75 * clench)
		var knuckle := Fx.polar(root, a1, size * 0.55)
		var a2 := a1 - signf(spread) * clench * 1.9
		var tip := Fx.polar(knuckle, a2, size * 0.45)
		for layer in 2:
			var width := 4.5 if layer == 0 else 2.0
			var colour := Color(DARK, 0.6 * alpha) if layer == 0 else Color(BONE, alpha)
			Fx.line(canvas, root, knuckle, width, colour)
			Fx.line(canvas, knuckle, tip, width * 0.85, colour)
		Fx.dot(canvas, knuckle, 2.5, Color(BONE, alpha))
		FxKit.taper(canvas, tip, Fx.polar(tip, a2, size * 0.2), 2.0, 0.0, Color(BONE, alpha))


## Green miasma: a cloud trailing along the arm, a burst where the hand
## closes, and wisps drifting up and off.
static func _miasma(canvas: CanvasItem, fx: Dictionary, from: Vector2, to: Vector2, dir: Vector2,
		size: float, progress: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	var fade := 1.0 - FxKit.phase(progress, 0.5, 1.0)
	for i in 10:
		var f := rng.randf_range(0.1, 1.0)
		var shown := FxKit.phase(progress, f * REACH_END, f * REACH_END + 0.1)
		var drift := Vector2(rng.randf_range(-6.0, 6.0), -rng.randf_range(4.0, 14.0)) * progress
		var puff := from.lerp(to, f) + dir.orthogonal() * rng.randf_range(-5.0, 5.0) + drift
		Fx.dot(canvas, puff, rng.randf_range(6.0, 11.0) * (0.6 + progress), Color(MIASMA, 0.22 * shown * fade))
	var burst := FxKit.phase(progress, CLENCH_END - 0.05, 0.95)
	if burst > 0.0 and burst < 1.0:
		var reach := size * (0.4 + 1.2 * FxKit.ease_out(burst))
		Fx.dot(canvas, to, reach * 2.4, Color(MIASMA, 0.25 * (1.0 - burst)))
		Fx.ring(canvas, to, reach, 3.0, Color(PALE, 0.7 * (1.0 - burst)))
		FxKit.sparks(canvas, to, Vector2.UP, TAU, 8, size * 1.2, burst, -10.0, 1.5, MIASMA, 0.9, FxKit.seed_of(fx) + 1)
