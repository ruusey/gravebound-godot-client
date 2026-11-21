class_name MotionHeading
extends RefCounted

## Which way a body that turns to face its travel is pointing.
##
## Read off the drawn motion rather than the streamed velocity: the server only
## resends an enemy once it drifts off its last velocity, so on a curve that
## velocity lags the path the sprite is actually tracing. A body standing still
## keeps the heading it last moved along.

## How quickly the heading swings round to a new direction, per second.
const TURN_RATE := 14.0
## Movement shorter than this between frames is jitter, not travel.
const MIN_STEP_PX := 0.05


## The entity's heading in radians (0 = facing +x, clockwise-positive like the
## canvas), advanced to its drawn `position` at time `now` (seconds).
static func advance(entity: Dictionary, position: Vector2, now: float) -> float:
	var heading: float = entity.get("heading", NAN)
	if is_nan(heading):
		heading = _initial(entity)
	var last: Variant = entity.get("heading_from")
	var last_at: float = entity.get("heading_at", now)
	if last is Vector2:
		var step: Vector2 = position - last
		if step.length_squared() > MIN_STEP_PX * MIN_STEP_PX:
			var weight := 1.0 - exp(-TURN_RATE * maxf(now - last_at, 0.0))
			heading = lerp_angle(heading, step.angle(), weight)
	entity["heading"] = heading
	entity["heading_from"] = position
	entity["heading_at"] = now
	return heading


## A body first seen mid-flight faces its streamed velocity; one at rest faces +x,
## the way the art is drawn.
static func _initial(entity: Dictionary) -> float:
	var snapshots: Array = entity.get("snaps", [])
	if not snapshots.is_empty():
		var velocity: Vector2 = snapshots[-1]["vel"]
		if velocity.length_squared() > 0.0001:
			return velocity.angle()
	return 0.0
