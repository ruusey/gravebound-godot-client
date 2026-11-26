class_name FxFirePillar
extends RefCounted

## FIRE_PILLAR (71): flame erupting from the ground. For the first 15% the
## ground glows inside a scorched ring -- the tell -- then a column of fire
## shoots up: four nested tongues of flame, deep red outside to a white-hot
## core, their edges licking and their tips flickering, with a molten pool
## at the foot and embers streaming off the top. From 75% it burns down
## into the scorch.

const SCORCH := Color("2a1408")
const DEEP := Color("c42a10")
const FLAME := Color("ff7a1a")
const BRIGHT := Color("ffd040")
const CORE := Color("fff6d0")
const TELL_END := 0.15
const RISE_END := 0.3
const FALL_START := 0.75
const EDGE_POINTS := 10
## [colour, share of the full width, share of the full height, alpha]
const TONGUES := [[DEEP, 1.0, 1.0, 0.9], [FLAME, 0.74, 0.9, 0.95], [BRIGHT, 0.48, 0.74, 0.95],
	[CORE, 0.24, 0.55, 1.0]]


## The column's height as a share of its full height.
static func rise(progress: float) -> float:
	if progress < TELL_END:
		return 0.0
	if progress < RISE_END:
		return ease((progress - TELL_END) / (RISE_END - TELL_END), 0.35)
	if progress > FALL_START:
		return 1.0 - (progress - FALL_START) / (1.0 - FALL_START)
	return 1.0


## One tongue of flame: up the left edge from the foot to the tip and back
## down the right, bulging low and tapering to a point that sways.
static func tongue(foot: Vector2, width: float, height: float, elapsed_ms: int, seed: float) -> Array:
	var left := []
	var right := []
	for i in EDGE_POINTS:
		var t := float(i) / EDGE_POINTS
		var half := width * sin(PI * (0.18 + 0.82 * t)) * (1.0 - t * 0.35)
		var lick := sin(elapsed_ms * 0.018 + t * 7.0 + seed) * width * 0.16 * t
		var sway := sin(elapsed_ms * 0.007 + seed) * width * 0.3 * t * t
		var y := foot.y - height * t
		left.append(Vector2(foot.x + sway - half + lick, y))
		right.push_front(Vector2(foot.x + sway + half + lick * 0.6, y))
	var tip := Vector2(foot.x + sin(elapsed_ms * 0.007 + seed) * width * 0.3, foot.y - height)
	return left + [tip] + right


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var glow := minf(1.0, progress / TELL_END)
	var fade := 1.0 - progress * 0.6
	CircleStamp.disc(canvas, at, radius, Color(SCORCH, 0.6 * (1.0 - progress * 0.5)))
	CircleStamp.disc(canvas, at, radius * 0.75, Color(DEEP, 0.4 * glow * fade))
	CircleStamp.disc(canvas, at, radius * 0.45, Color(FLAME, 0.35 * glow * fade))
	Fx.ring(canvas, at, radius, 4.0, Color(FLAME, 0.85 * glow * fade))
	var lift := rise(progress)
	var height := radius * 2.6 * lift
	if height < 2.0:
		return
	var width := radius * 0.62
	var flicker := 0.92 + 0.08 * sin(elapsed_ms * 0.05)
	for i in TONGUES.size():
		var layer: Array = TONGUES[i]
		Fx.polygon(canvas, tongue(at, width * layer[1], height * layer[2] * flicker, elapsed_ms, i * 1.7),
			Color(layer[0], layer[3]))
	for i in 12:
		var phase := fmod(elapsed_ms * 0.0016 + i * 0.137, 1.0)
		var ember := at + Vector2(sin(i * 2.1 + phase * 5.0) * width * 1.1, -height * (0.5 + phase * 0.8))
		Fx.dot(canvas, ember, 3.0, Color(BRIGHT, (1.0 - phase) * lift))
		Fx.dot(canvas, ember, 1.5, Color(CORE, (1.0 - phase) * lift))
