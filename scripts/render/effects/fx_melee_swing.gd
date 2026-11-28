class_name FxMeleeSwing
extends RefCounted

## MELEE_SWING (62): the weapon's strike, drawn where it lands. The server
## sends that point as `pos` -- the cursor, pulled in to the weapon's reach,
## the same spot the melee reticle marks -- and the wielder as `target`, so
## the strike is centred on the reticle and faces away from the player. The
## tier is the weapon: 1 sword, 2 axe, 3 hammer, 10 dagger. The size comes
## from the effect's radius (the weapon's projectile size), never from how
## far the cursor is.
##
## Sword: a steel-blue crescent slashed across the point. Axe: a heavier
## ember cleave that throws sparks when it bites. Hammer: the head arcs
## over and down onto the point, then a flash, two shockwaves, cracks and
## debris. Dagger: two quick violet cuts
## crossing in an X. Each swing picks its direction from its start time,
## so consecutive swings alternate at random.

const SWORD := 1
const AXE := 2
const HAMMER := 3
const DAGGER := 10
## Least time each strike stays on screen. The server's window is just the
## swing; this keeps the afterglow long enough to read.
const HOLD_MS := {SWORD: 300, AXE: 340, HAMMER: 560, DAGGER: 260}
const SEGMENTS := 20


## The strike's width across, in world px.
static func span(radius: float) -> float:
	return clampf(radius * 3.0, 64.0, 120.0)


static func hold_ms(tier: int, sent_ms: int) -> int:
	return maxi(sent_ms, int(HOLD_MS.get(tier, HOLD_MS[SWORD])))


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var from: Vector2 = fx["target"]
	var angle := (at - from).angle() if at.distance_squared_to(from) > 1.0 else 0.0
	var size := span(fx["radius"])
	var turn := 1.0 if int(fx.get("started", 0)) % 2 == 0 else -1.0
	match int(fx.get("tier", 0)):
		AXE: _axe(canvas, fx, at, angle, size, progress, turn)
		HAMMER: _hammer(canvas, fx, at, angle, size, progress, turn)
		DAGGER: _dagger(canvas, at, angle, size, progress, turn)
		_: _sword(canvas, at, angle, size, progress, turn)


## A crescent along the circle round `centre`, from angle `tail` to `head`:
## pointed at both ends and thickest near the head, `width` at most.
static func crescent(canvas: CanvasItem, centre: Vector2, radius: float, tail: float, head: float,
		width: float, colour: Color) -> void:
	if colour.a <= 0.001 or absf(head - tail) < 0.01:
		return
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		var a := lerpf(tail, head, u)
		var w := width * pow(sin(PI * u), 0.7) * (0.3 + 0.7 * u)
		outer.append(Fx.polar(centre, a, radius + w * 0.5))
		inner.append(Fx.polar(centre, a, radius - w * 0.5))
	strip(canvas, outer, inner, colour)


## Fills between two matching edges as a strip of triangles. Indexed straight
## to the renderer, so a hairline sliver can't fail triangulation the way a
## polygon outline can.
static func strip(canvas: CanvasItem, left: PackedVector2Array, right: PackedVector2Array, colour: Color) -> void:
	var count := left.size()
	var indices := PackedInt32Array()
	for i in count - 1:
		indices.append_array([i, i + 1, count + i, count + i, i + 1, count + i + 1])
	var colours := PackedColorArray()
	colours.resize(count * 2)
	colours.fill(colour)
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, left + right, colours)


## The bright leading rim of a crescent, fading in toward the head.
static func rim(canvas: CanvasItem, centre: Vector2, radius: float, tail: float, head: float,
		width_px: float, colour: Color) -> void:
	if colour.a <= 0.001 or absf(head - tail) < 0.01:
		return
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		points.append(Fx.polar(centre, lerpf(tail, head, u), radius))
		colours.append(Color(colour, colour.a * u))
	canvas.draw_polyline_colors(points, colours, width_px * Fx.S)


## A four-point glint.
static func glint(canvas: CanvasItem, at: Vector2, length: float, colour: Color) -> void:
	if colour.a <= 0.001 or length <= 0.0:
		return
	var thin := length * 0.16
	Fx.polygon(canvas, [at + Vector2(-length, 0), at + Vector2(0, -thin), at + Vector2(length, 0),
		at + Vector2(0, thin)], colour)
	Fx.polygon(canvas, [at + Vector2(0, -length), at + Vector2(thin, 0), at + Vector2(0, length),
		at + Vector2(-thin, 0)], colour)


## Where the head and the tail of a sweep across `half` either side of the
## aim have got to: the head races out, the tail chases it and catches up by
## the end, so the crescent forms, holds, then shrinks into the far tip.
static func sweep(progress: float, half: float, turn: float, head_by: float, heavy: bool) -> Vector2:
	var h := clampf(progress / head_by, 0.0, 1.0)
	h = h * h if heavy else 1.0 - (1.0 - h) * (1.0 - h)
	var t := clampf((progress - head_by * 0.6) / (1.0 - head_by * 0.6), 0.0, 1.0)
	t = t * t * 0.7
	return Vector2(-half + 2.0 * half * t, -half + 2.0 * half * h) * turn


static func _fade(progress: float, start: float) -> float:
	return 1.0 if progress < start else maxf(0.0, (1.0 - progress) / (1.0 - start))


static func _sword(canvas: CanvasItem, at: Vector2, angle: float, size: float, progress: float, turn: float) -> void:
	var radius := size * 0.58
	var half := asin(clampf(size * 0.5 / radius, 0.0, 1.0))
	var centre := Fx.polar(at, angle + PI, radius)
	var ends := sweep(progress, half, turn, 0.32, false)
	var tail := angle + ends.x
	var head := angle + ends.y
	var alpha := _fade(progress, 0.55)
	var width := size * 0.28
	crescent(canvas, centre, radius, tail, head, width * 2.1, Color("9fe4ff", 0.32 * alpha))
	crescent(canvas, centre, radius, tail, head, width, Color("5cc8ff", 0.95 * alpha))
	crescent(canvas, centre, radius + width * 0.12, tail, head, width * 0.42, Color(Color.WHITE, 0.95 * alpha))
	rim(canvas, centre, radius + width * 0.32, tail, head, 3.0, Color(Color.WHITE, alpha))
	if progress < 0.5:
		var tip := Fx.polar(centre, head, radius)
		glint(canvas, tip, size * 0.16 * (1.0 - progress), Color(Color.WHITE, 0.95))


static func _axe(canvas: CanvasItem, fx: Dictionary, at: Vector2, angle: float, size: float, progress: float,
		turn: float) -> void:
	var radius := size * 0.55
	var half := asin(clampf(size * 0.5 / radius, 0.0, 1.0)) * 1.1
	var centre := Fx.polar(at, angle + PI, radius)
	var ends := sweep(progress, half, turn, 0.38, true)
	var tail := angle + ends.x
	var head := angle + ends.y
	var alpha := _fade(progress, 0.55)
	var width := size * 0.42
	crescent(canvas, centre, radius, tail, head, width * 1.9, Color("ffb25c", 0.36 * alpha))
	crescent(canvas, centre, radius, tail, head, width, Color("ff8a2a", 0.95 * alpha))
	crescent(canvas, centre, radius + width * 0.1, tail, head, width * 0.45, Color("ffe4a8", 0.95 * alpha))
	rim(canvas, centre, radius + width * 0.3, tail, head, 4.0, Color("fff3d6", alpha))
	# The bite: a flash where the blade lands and embers thrown off ahead of it.
	var bite := clampf((progress - 0.34) / 0.5, 0.0, 1.0)
	if bite <= 0.0 or bite >= 1.0:
		return
	CircleStamp.disc(canvas, at, size * 0.26 * (1.0 - bite), Color("ffd38a", 0.7 * (1.0 - bite)))
	var rng := Fx.rng_for({"started": fx.get("started", 0), "pos": at}, 0)
	for k in 6:
		var a := angle + rng.randf_range(-1.1, 1.1)
		var reach := size * rng.randf_range(0.35, 0.7) * sqrt(bite)
		var spark := Fx.polar(at, a, reach)
		Fx.line(canvas, Fx.polar(at, a, reach * 0.7), spark, 3.0, Color("ffb050", 1.0 - bite))
		Fx.dot(canvas, spark, 2.6, Color("fff0c0", 1.0 - bite))


static func _hammer(canvas: CanvasItem, fx: Dictionary, at: Vector2, angle: float, size: float,
		progress: float, turn: float) -> void:
	const IMPACT := 0.3
	_hammer_swing(canvas, at, angle, size, progress, IMPACT, turn)
	if progress < IMPACT:
		var p := progress / IMPACT
		CircleStamp.ring(canvas, at, size * (0.5 - 0.35 * p), 2.5, Color("ffd27a", 0.3 + 0.5 * p), 40)
		return
	var p := (progress - IMPACT) / (1.0 - IMPACT)
	var alpha := 1.0 - p
	CircleStamp.disc(canvas, at, size * 0.42 * (0.6 + 0.4 * p), Color("6a4520", 0.28 * alpha))
	# Cracks in the ground, jagged and fixed for this strike.
	var rng := Fx.rng_for({"started": fx.get("started", 0), "pos": at}, 0)
	for k in 6:
		var a := angle + k * TAU / 6.0 + rng.randf_range(-0.3, 0.3)
		var points := PackedVector2Array([at])
		var length := size * rng.randf_range(0.38, 0.55) * minf(1.0, p * 3.0)
		for j in range(1, 4):
			points.append(Fx.polar(at, a + rng.randf_range(-0.28, 0.28), length * j / 3.0))
		Fx.polyline(canvas, points, 5.0, Color("3a2412", 0.85 * alpha))
		Fx.polyline(canvas, points, 2.0, Color("ffcf6a", 0.8 * alpha))
	# Two shockwaves, the second trailing the first.
	for delay in [0.0, 0.22]:
		var w := Fx.wave(p, delay)
		if w >= 0.0:
			CircleStamp.ring(canvas, at, size * (0.18 + 0.62 * w), (7.0 - 5.0 * w) * Fx.S,
				Color("ffbf40", 0.95 * (1.0 - w)), 48)
	# The flash of the blow.
	var flash := 1.0 - minf(1.0, p * 3.5)
	if flash > 0.0:
		CircleStamp.disc(canvas, at, size * 0.34, Color("fff4c8", 0.85 * flash))
		glint(canvas, at, size * 0.55 * flash, Color(Color.WHITE, flash))
	# Debris flung out and falling back.
	for k in 8:
		var a := rng.randf() * TAU
		var reach := size * rng.randf_range(0.3, 0.6) * p
		var lift := size * 0.35 * p * (1.0 - p) * rng.randf_range(0.5, 1.0)
		Fx.dot(canvas, Fx.polar(at, a, reach) - Vector2(0, lift), 3.2, Color("c89a5a", alpha))


## The hammer itself: a handle pivoting from behind the point, its head
## accelerating round over the top and landing on the point at `impact`,
## with a heavy trail behind it. Head and trail fade just after the blow.
static func _hammer_swing(canvas: CanvasItem, at: Vector2, angle: float, size: float, progress: float,
		impact: float, turn: float) -> void:
	var fade := 1.0 if progress < impact else 1.0 - clampf((progress - impact) / 0.25, 0.0, 1.0)
	if fade <= 0.0:
		return
	var radius := size * 0.62
	var pivot := Fx.polar(at, angle + PI, radius)
	var start := angle + 1.9 * turn
	var p := clampf(progress / impact, 0.0, 1.0)
	var head := lerpf(start, angle, p * p)
	var lag := clampf((progress - impact * 0.5) / impact, 0.0, 1.0)
	var tail := lerpf(start, angle, lag * lag)
	var width := size * 0.4
	crescent(canvas, pivot, radius, tail, head, width * 1.8, Color("fff0b0", 0.4 * fade))
	crescent(canvas, pivot, radius, tail, head, width, Color("ffb42e", 0.85 * fade))
	crescent(canvas, pivot, radius + width * 0.1, tail, head, width * 0.4, Color("fff6d8", 0.95 * fade))
	# The handle and a squared iron head across the end of it.
	var end := Fx.polar(pivot, head, radius)
	var along := Vector2(cos(head), sin(head))
	var across := along.orthogonal()
	Fx.line(canvas, pivot.lerp(end, 0.3), end, 5.0, Color("8a5a2b", fade))
	var long := size * 0.2
	var deep := size * 0.12
	var corners := [end - across * long - along * deep, end + across * long - along * deep,
		end + across * long + along * deep, end - across * long + along * deep]
	Fx.polygon(canvas, corners, Color("3c3f48", fade))
	Fx.polygon(canvas, [corners[0].lerp(corners[3], 0.15), corners[1].lerp(corners[2], 0.15),
		corners[1].lerp(corners[2], 0.45), corners[0].lerp(corners[3], 0.45)], Color("c9d0dc", fade))
	Fx.polyline(canvas, PackedVector2Array(corners + [corners[0]]), 2.0, Color("ffe8a8", 0.9 * fade))


static func _dagger(canvas: CanvasItem, at: Vector2, angle: float, size: float, progress: float, turn: float) -> void:
	var length := size * 0.5
	for cut in 2:
		var start := 0.0 if cut == 0 else 0.22
		var p := clampf((progress - start) / 0.6, 0.0, 1.0)
		if p <= 0.0 or p >= 1.0:
			continue
		var a := angle + (0.75 if cut == 0 else -0.75) * turn
		var dir := Vector2(cos(a), sin(a))
		var head := minf(1.0, p / 0.35)
		var tail := clampf((p - 0.3) / 0.7, 0.0, 1.0)
		var from := at - dir * length * (1.0 - 2.0 * tail)
		var to := at - dir * length * (1.0 - 2.0 * head)
		var alpha := 1.0 if p < 0.6 else (1.0 - p) / 0.4
		_cut(canvas, from, to, size * 0.24, Color("c9a0ff", 0.45 * alpha))
		_cut(canvas, from, to, size * 0.12, Color("dcc4ff", 0.95 * alpha))
		Fx.line(canvas, from, to, 2.5, Color(Color.WHITE, alpha))
	var cross := 1.0 - absf(progress - 0.42) / 0.16
	if cross > 0.0:
		glint(canvas, at, size * 0.28 * cross, Color(Color.WHITE, cross))


## A straight cut: a thin lens from `from` to `to`, `width` across its middle.
static func _cut(canvas: CanvasItem, from: Vector2, to: Vector2, width: float, colour: Color) -> void:
	if colour.a <= 0.001 or from.distance_squared_to(to) < 1.0:
		return
	var normal := (to - from).normalized().orthogonal()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in 9:
		var u := i / 8.0
		left.append(from.lerp(to, u) + normal * width * 0.5 * sin(PI * u))
		right.append(from.lerp(to, u) - normal * width * 0.2 * sin(PI * u))
	strip(canvas, left, right, colour)
