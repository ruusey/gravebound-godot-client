class_name EntitySnapshots
extends RefCounted

## Position history for remote entities, and the interpolation over it.
##
## Remote entities are drawn INTERP_DELAY_MS in the past, between whichever
## two snapshots bracket that moment -- the web client's sampleRemoteSnapshot
## over a RETAIN_MS buffer. Not the two newest: a moving peer arrives every
## 62.5ms, so at a 100ms delay the render time falls between the second and
## third newest, and reading only two clamps to one of them and holds it, a
## 16Hz staircase. Past the newest snapshot the entity rides its last
## velocity, as both references do, because the server is silent on
## purpose: an enemy is re-sent only when it drifts 4px off its sent
## velocity or after 750ms (EntityMotionState), so a 250ms cap was a
## freeze followed by a jump. Extrapolation stops when the server has gone
## quiet for STALE_MS, or the entity is beyond the ten tiles the server
## sends movement for -- it would be a ghost.
##
## A snapshot that moves the drawn point -- a late packet, a correction --
## is absorbed as a render offset that closes at the native client's rate
## (the gap in 50ms, at most 256 px/s, outright past five tiles), so the
## sprite never jumps on the frame a packet lands.

const INTERP_DELAY_MS := 100.0
## The web client's SNAP_BUFFER_MS: enough to hold every pair the delay can
## fall between, with slack for a gap.
const RETAIN_MS := 400.0
## A load and a move for the same tick land in the same frame: fold them.
const COLLAPSE_MS := 8.0
## Both references' extrapolation cap; the server forces a resend of a
## moving enemy at 750ms, so silence past this means it is not coming.
const STALE_MS := 1200.0
## A moving peer is heard from every four ticks: the web client's rule is
## that 300ms of silence means it stopped or left.
const PEER_STALE_MS := 300.0
## The server's movement radius, ten tiles, plus half a tile of margin so a
## sprite on the edge is not frozen and freed every step.
const VIEWPORT_FREEZE_PX := 10.0 * GameConstants.TILE_SIZE + 16.0
const CLOSE_TIME_S := 0.05
const MAX_CLOSE_PX_PER_S := 256.0
const SNAP_PX := 5.0 * GameConstants.TILE_SIZE
const OFFSET_FLOOR_PX := 0.3


## Records a server position. Where the entity is drawn does not change on
## this clock reading: the difference is banked as an offset and closed
## over the frames that follow.
static func push(entity: Dictionary, position: Vector2, velocity: Vector2, now_ms: float,
		viewer: Vector2 = Vector2.INF) -> void:
	var snapshots: Array = entity["snaps"]
	entity["drawn_at"] = -1.0
	var drawn := render_position(entity, now_ms, viewer) if not snapshots.is_empty() else Vector2.INF
	var t := float(now_ms)
	if not snapshots.is_empty() and t - snapshots[-1]["t"] < COLLAPSE_MS:
		snapshots[-1] = {"t": snapshots[-1]["t"], "pos": position, "vel": velocity}
	else:
		snapshots.append({"t": t, "pos": position, "vel": velocity})
	while snapshots.size() > 2 and snapshots[0]["t"] < t - RETAIN_MS:
		snapshots.pop_front()
	if drawn != Vector2.INF:
		var offset: Vector2 = drawn - sampled(entity, now_ms, viewer)
		entity["offset"] = Vector2.ZERO if offset.length() > SNAP_PX else offset
		entity["offset_t"] = now_ms


## Where to draw the entity: the sampled position plus what is left of the
## last correction. `viewer` is the local player's centre, for the viewport
## gate; INF means no gate.
static func render_position(entity: Dictionary, now_ms: float, viewer: Vector2 = Vector2.INF) -> Vector2:
	return sampled(entity, now_ms, viewer) + _offset(entity, now_ms)


## The server's position at the render time, with no smoothing over it.
static func sampled(entity: Dictionary, now_ms: float, viewer: Vector2 = Vector2.INF) -> Vector2:
	var snapshots: Array = entity.get("snaps", [])
	if snapshots.is_empty():
		return Vector2.ZERO
	var target := float(now_ms) - INTERP_DELAY_MS
	if target <= snapshots[0]["t"]:
		return snapshots[0]["pos"]
	var newest: Dictionary = snapshots[-1]
	if target < newest["t"]:
		for i in range(snapshots.size() - 1, 0, -1):
			var older: Dictionary = snapshots[i - 1]
			if target >= older["t"]:
				var span: float = maxf(snapshots[i]["t"] - older["t"], 1.0)
				return older["pos"].lerp(snapshots[i]["pos"], (target - older["t"]) / span)
		return newest["pos"]
	var velocity: Vector2 = newest["vel"]
	if velocity == Vector2.ZERO or _outside_viewport(entity, newest["pos"], viewer):
		return newest["pos"]
	var stale: float = PEER_STALE_MS if entity.get("kind", -1) == GameConstants.ENTITY_PLAYER else STALE_MS
	var ahead: float = minf(target - newest["t"], stale - INTERP_DELAY_MS)
	# Velocities are pixels per tick at 64Hz.
	return newest["pos"] + velocity * (ahead / 1000.0) * GameConstants.TICK_RATE


static func _outside_viewport(entity: Dictionary, position: Vector2, viewer: Vector2) -> bool:
	if viewer == Vector2.INF:
		return false
	var centre := position + Vector2.ONE * float(entity.get("size", 16)) * 0.5
	return centre.distance_squared_to(viewer) > VIEWPORT_FREEZE_PX * VIEWPORT_FREEZE_PX


## What is left of the last correction at this clock reading, stepped once
## per reading however many times the frame asks.
static func _offset(entity: Dictionary, now_ms: float) -> Vector2:
	var offset: Vector2 = entity.get("offset", Vector2.ZERO)
	if offset == Vector2.ZERO:
		return offset
	var dt := (now_ms - float(entity.get("offset_t", now_ms))) / 1000.0
	if dt > 0.0:
		var gap := offset.length()
		var step := minf(gap, minf(gap / CLOSE_TIME_S, MAX_CLOSE_PX_PER_S) * dt)
		offset = Vector2.ZERO if gap - step < OFFSET_FLOOR_PX else offset * ((gap - step) / gap)
		entity["offset"] = offset
		entity["offset_t"] = now_ms
	return offset
