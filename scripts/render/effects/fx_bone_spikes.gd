class_name FxBoneSpikes
extends RefCounted

## BONE_SPIKES (24): bone spikes bursting up through the ground. The earth
## darkens, then a few spikes punch up in the middle and a ring of taller
## ones erupts round the edge in a sweep, each a curved ivory fang with a
## dark edge and a shadowed side, overshooting its height as it breaks the
## surface and flinging clods of dirt off its base. They hold, then sink
## back into the ground over the last fifth.

const IVORY := Color("efe6c8")
const EDGE := Color("2a2216")
const DIRT := Color("3a2a18")
## A spike's own rise, as a fraction of the effect.
const RISE := 0.14
const SINK_FROM := 0.8


## Spikes round the edge: one per 8 units of radius, 6 to 10.
static func outer_count(radius: float) -> int:
	return clampi(int(radius / 8.0), 6, 10)


## Spikes inside the ring: half as many as round it, 3 or 4.
static func inner_count(radius: float) -> int:
	return clampi(outer_count(radius) / 2, 3, 4)


## Where spike `i` stands from the centre: the first outer_count round the
## edge at 85% of the radius, the rest a ring at 40% between them.
static func spike_offset(radius: float, i: int) -> Vector2:
	var outer := outer_count(radius)
	var wobble := 1.0 + 0.08 * sin(i * 2.9)
	if i < outer:
		return Fx.polar(Vector2.ZERO, i * TAU / outer - PI * 0.5, radius * 0.85 * wobble)
	var k := i - outer
	return Fx.polar(Vector2.ZERO, (k + 0.5) * TAU / inner_count(radius), radius * 0.40 * wobble)


## When spike `i` starts up: the inner ones together at once, the ring
## sweeping round from 6% to 24%.
static func delay(radius: float, i: int) -> float:
	var outer := outer_count(radius)
	return 0.06 + 0.18 * float(i) / outer if i < outer else 0.0


## How far up a spike is, 0..1.2: shooting up past full height over its
## RISE and settling back, then sinking from SINK_FROM.
static func rise(progress: float, start: float) -> float:
	var t := (progress - start) / RISE
	if t <= 0.0:
		return 0.0
	var up := sin(minf(t, 1.0) * PI * 0.5) + 0.2 * sin(minf(t, 1.5) / 1.5 * PI)
	return up * clampf((1.0 - progress) / (1.0 - SINK_FROM), 0.0, 1.0)


## Spike `i`'s full height in world units: about half the radius, 14 to
## 48 units, varied by a fifth either way.
static func spike_height(radius: float, i: int) -> float:
	return clampf(radius * 0.55, 14.0, 48.0) * (0.8 + 0.4 * fposmod(i * 0.683 * 7.0, 1.0))


## Every spike, back to front, so the nearer ones stand over the farther.
static func depth_order(radius: float) -> Array:
	var order := range(outer_count(radius) + inner_count(radius))
	order.sort_custom(func(a: int, b: int) -> bool: return spike_offset(radius, a).y < spike_offset(radius, b).y)
	return order


## A curved fang standing on `base`: `width` either side at the foot,
## `height` tall, its tip bent `lean` of its height sideways.
static func fang(base: Vector2, width: float, height: float, lean: float) -> Array:
	var bend := lean * height
	return [base + Vector2(-width, 0.0), base + Vector2(-width * 0.55 + bend * 0.35, -height * 0.5),
		base + Vector2(bend, -height), base + Vector2(width * 0.45 + bend * 0.3, -height * 0.55),
		base + Vector2(width, 0.0)]


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	var ground := clampf(progress / 0.08, 0.0, 1.0) * clampf((1.0 - progress) / 0.2, 0.0, 1.0)
	CircleStamp.disc(canvas, at, radius * 1.05, Color(Color.BLACK, ground * 0.28))
	CircleStamp.disc(canvas, at, radius * 0.6, Color(DIRT, ground * 0.25))
	for i in depth_order(radius):
		var base := at + spike_offset(radius, i)
		var start := delay(radius, i)
		var up := rise(progress, start)
		var height := spike_height(radius, i)
		var width := height * 0.22
		CircleStamp.disc(canvas, base, width * 1.5, Color(DIRT, ground * 0.85))
		# A spike barely out of the ground is a sliver the triangulator rejects.
		if height * up > 3.0:
			_spike(canvas, base, width, height * up, sin(i * 1.9) * 0.3, ground)
		_clods(canvas, base, width, (progress - start) / (RISE * 2.0), ground)


static func _spike(canvas: CanvasItem, base: Vector2, width: float, height: float, lean: float,
		a: float) -> void:
	Fx.polygon(canvas, fang(base + Vector2(0.6, 0.4), width + 1.4, height + 1.8, lean), Color(EDGE, a))
	Fx.polygon(canvas, fang(base, width, height, lean), Color(IVORY, a))
	var tip := base + Vector2(lean * height, -height)
	Fx.line(canvas, base + Vector2(width * 0.35, -1.0), tip.lerp(base, 0.12), 3.0, Color("b8a880", a))


## Dirt flung off a spike's base as it breaks through, for twice its rise.
static func _clods(canvas: CanvasItem, base: Vector2, width: float, t: float, a: float) -> void:
	if t <= 0.0 or t >= 1.0:
		return
	for k in 3:
		var angle := -PI * (0.15 + 0.35 * k)
		var spot := Fx.polar(base, angle, width * (1.0 + 3.0 * t)) + Vector2(0.0, 6.0 * t * t)
		Fx.dot(canvas, spot, 3.0, Color(DIRT, a * (1.0 - t)))
