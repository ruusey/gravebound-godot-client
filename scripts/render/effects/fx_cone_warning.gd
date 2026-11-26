class_name FxConeWarning
extends RefCounted

## CONE_WARNING (67): an enemy's cone telegraph. A wedge from the enemy
## (`pos`) toward `target`, as long as the distance between them, opening
## `radius` degrees either side of that line (30 when the server sends 0).
## It flashes like BEAM_WARNING and holds until it expires, while a second
## wedge fills it from the apex so the strike's timing can be read. Red, or
## green and blue at the boss tiers 11 and 12.

const DEFAULT_HALF_ANGLE := 30.0
const STEPS := 16


## The half-angle in radians, kept to a wedge that still reads as a cone.
static func half_angle(radius: float) -> float:
	return deg_to_rad(clampf(radius if radius > 0.0 else DEFAULT_HALF_ANGLE, 5.0, 85.0))


## The wedge's outline: the apex, then the far arc.
static func wedge(apex: Vector2, heading: float, length: float, half: float) -> Array:
	var points := [apex]
	for i in STEPS + 1:
		points.append(Fx.polar(apex, heading - half + 2.0 * half * i / STEPS, length))
	return points


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var apex: Vector2 = fx["pos"]
	var along: Vector2 = fx["target"] - apex
	if along.length() < 2.0:
		return
	var tones: Array = FxGeneric.BOSS.get(int(fx.get("tier", 0)), FxGeneric.BOSS_RED)
	var heading := along.angle()
	var length := along.length()
	var half := half_angle(fx["radius"])
	var pulse := FxBeamWarning.pulse(elapsed_ms)
	Fx.polygon(canvas, wedge(apex, heading, length, half), Color(tones[0], 0.12 + 0.18 * pulse))
	var filled := length * clampf(progress, 0.0, 1.0)
	if filled > 2.0:
		Fx.polygon(canvas, wedge(apex, heading, filled, half), Color(tones[0], 0.3))
		Fx.arc(canvas, apex, heading - half, heading + half, filled, STEPS, 2.0, Color(tones[2], 0.9))
	var edge := Color(tones[1], pulse)
	Fx.line(canvas, apex, Fx.polar(apex, heading - half, length), 3.0, edge)
	Fx.line(canvas, apex, Fx.polar(apex, heading + half, length), 3.0, edge)
	Fx.arc(canvas, apex, heading - half, heading + half, length, STEPS, 3.0, edge)
