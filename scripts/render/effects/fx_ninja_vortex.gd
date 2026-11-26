class_name FxNinjaVortex
extends RefCounted

## The ninja dash's vortex: blades spaced along the path, each orbiting
## across it (alternate ones sweeping opposite ways, which is what reads as
## a vortex) while spinning on its own axis. They pop in front to back,
## peak and shrink away. Each is a tier-coloured lens round a white core
## outlined in black, trailing a streak back along the path.

## The web's pixel sizes, halved into world units.
const ORBIT_REACH := 44.0 * Fx.S
const GLOW_LENGTH := 22.0 * Fx.S
const GLOW_WIDTH := 7.0 * Fx.S
const CORE_LENGTH := 16.0 * Fx.S
const CORE_WIDTH := 4.0 * Fx.S
const TRAIL := 14.0 * Fx.S


## When blade `t` of the way along the path appears: the far end last,
## 45% of the way in.
static func appear_at(t: float) -> float:
	return t * 0.45


## A blade's size over its own life: up over the first 15%, held, and
## down over the last quarter.
static func blade_scale(local: float) -> float:
	if local < 0.15:
		return local / 0.15
	if local > 0.75:
		return maxf(0.0, (1.0 - local) / 0.25)
	return 1.0


## How far blade `i` is across the path, before its scale.
static func orbit(i: int, elapsed_ms: int) -> float:
	var sign := 1.0 if i & 1 else -1.0
	return sin(sign * (elapsed_ms * 0.011 + i * 0.55)) * ORBIT_REACH


static func spin(i: int, elapsed_ms: int) -> float:
	return elapsed_ms * 0.016 + i * 0.4


static func draw(canvas: CanvasItem, from: Vector2, to: Vector2, count: int, progress: float,
		colour: Color, elapsed_ms: int) -> void:
	var alpha := 1.0 - progress
	var along := (to - from).normalized()
	var across := Vector2(-along.y, along.x)
	for i in count:
		var t := (i + 0.5) / count
		var appear := appear_at(t)
		if progress < appear:
			continue
		var size := blade_scale((progress - appear) / maxf(0.001, 1.0 - appear))
		if size <= 0.0:
			continue
		var at := from + (to - from) * t + across * orbit(i, elapsed_ms) * size
		var angle := spin(i, elapsed_ms)
		_quad(canvas, FxBladeShapes.lens(at, angle, GLOW_LENGTH * size, GLOW_WIDTH * size),
			Color(colour, alpha * 0.32 * size))
		var core := FxBladeShapes.lens(at, angle, CORE_LENGTH * size, CORE_WIDTH * size)
		FxBladeShapes.outline(canvas, core, 1.0, Color(Color.BLACK, alpha * 0.7 * size))
		_quad(canvas, core, Color(Color.WHITE, alpha * 0.85 * size))
		Fx.line(canvas, core[0], core[0] - along * TRAIL * size, 2.0, Color(colour, alpha * 0.45 * size))


## A blade's diamond filled as a quad, not a polygon: the polygon path
## triangulates it, and a blade popping in is a sliver too small for the
## triangulator, which then fails ("Invalid polygon data") -- more often the
## further from the origin it is drawn. A convex quad needs no triangulating.
static func _quad(canvas: CanvasItem, points: Array, colour: Color) -> void:
	if colour.a > 0.001:
		canvas.draw_primitive(PackedVector2Array(points), PackedColorArray([colour, colour, colour, colour]),
			PackedVector2Array())
