class_name FxNinjaCaltrops
extends RefCounted

## NINJA_CALTROPS (103): a handful of caltrops sown in a fan, from the Ninja
## (`pos`) toward `target`. Twelve iron caltrops -- three-armed spikes with a
## bright upturned point -- hop out tumbling in three staggered arcs, near,
## middle and far, each leaving a faint flight trace. Each lands with a puff
## of dust and a tiny bounce, a few catch the light with a glint, and the
## whole spread lies glinting before it fades.

const IRON := Color("9aa3b4")
const INK := Color("15131a")
const SHINE := Color("e6ecf5")
const DUST := Color("9a8e7c")
const ROWS := [3, 4, 5]
const ROW_REACH := [0.72, 0.9, 1.08]
const FAN := 0.42


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var from: Vector2 = fx["pos"]
	var to := FxKit.line_end(fx)
	var span := to - from
	var length := maxf(span.length(), 24.0)
	var heading := span.angle() if span.length() > 1.0 else 0.0
	var size: float = clampf(fx["radius"] * 0.36, 5.0, 14.0)
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	var index := 0
	for row in ROWS.size():
		var count: int = ROWS[row]
		for k in count:
			var across := (float(k) / maxf(1.0, count - 1) - 0.5) * 2.0
			var angle := heading + across * FAN + rng.randf_range(-0.06, 0.06)
			var reach: float = ROW_REACH[row]
			var land := Fx.polar(from, angle, length * reach * rng.randf_range(0.94, 1.06))
			var spin := rng.randf_range(0.0, TAU)
			_caltrop_life(canvas, from, land, size, spin, index, progress, fade)
			index += 1


## One caltrop: a hop out with a trace behind it, a landing puff and a
## settle bounce, then a glint on every third.
static func _caltrop_life(canvas: CanvasItem, from: Vector2, land: Vector2, size: float, spin: float,
		index: int, progress: float, fade: float) -> void:
	var start := index * 0.018
	var t := FxKit.phase(progress, start, start + 0.26)
	if t <= 0.0:
		return
	var hop := from.distance_to(land) * 0.22
	var spot := _hop(from, land, hop, FxKit.ease_out(t))
	if t < 1.0:
		var trace := PackedVector2Array()
		for k in 5:
			trace.append(_hop(from, land, hop, FxKit.ease_out(maxf(0.0, t - 0.25 * (1.0 - k / 4.0)))))
		Fx.polyline(canvas, trace, 2.0, Color(SHINE, 0.35 * (1.0 - t)))
	var settle := FxKit.phase(progress, start + 0.26, start + 0.4)
	spot += Vector2(0.0, -sin(settle * PI) * size * 0.6)
	_caltrop(canvas, spot, size, spin + (1.0 - t) * 9.0, fade)
	if settle > 0.0 and settle < 1.0:
		CircleStamp.disc(canvas, land + Vector2(0.0, size * 0.3), size * (0.8 + 1.4 * settle),
			Color(DUST, (1.0 - settle) * 0.45))
	if index % 3 == 1:
		var glint := FxKit.pulse(progress, 0.5 + index * 0.012, 0.56 + index * 0.012, 0.7 + index * 0.012)
		FxKit.glint(canvas, spot + Vector2(0.0, -size * 0.5), size * 2.2 * glint, 0.4, SHINE, glint * fade)


## `f` of the way along the hop from `from` to `land`, arcing `hop` high.
static func _hop(from: Vector2, land: Vector2, hop: float, f: float) -> Vector2:
	return from.lerp(land, f) + Vector2(0.0, -hop * 4.0 * f * (1.0 - f))


## A caltrop seen from above: three iron arms 120 degrees apart, inked
## round, and the fourth point standing up as a bright dot.
static func _caltrop(canvas: CanvasItem, at: Vector2, size: float, turn: float, alpha: float) -> void:
	if alpha <= 0.001:
		return
	var arms: Array = []
	for k in 3:
		arms.append(Fx.polar(at, turn + k * TAU / 3.0, size))
	for arm: Vector2 in arms:
		Fx.line(canvas, at, arm, 5.0, Color(INK, alpha * 0.9))
	for arm: Vector2 in arms:
		FxKit.taper(canvas, at, arm, size * 0.32, 0.0, Color(IRON, alpha))
	CircleStamp.disc(canvas, at, size * 0.18, Color(SHINE, alpha))
