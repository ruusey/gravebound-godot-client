class_name PacingProbe
extends RefCounted

## Frame pacing as the eye sees it, which a frame-time average does not.
##
## A display shows frames on an even beat, so an object moving at a steady speed
## should step the same distance every displayed frame. Judder is how much that
## step changes from one frame to the next: zero for even motion, a pixel or more
## when one frame's position was read off a clock that ran early or late. Steps
## are measured in world space before the renderer's pixel snap, so the score is
## the timing alone, scaled to screen pixels by the world zoom.
##
## Each kind of object is also scored against the camera, since the eye follows the
## player and sees everything else slide relative to it.

## A step change past this many screen px reads as a visible hitch.
const HITCH_PX := 0.75

var zoom := 2.0

var _last_frame_us := 0
var _intervals: Array[float] = []
var _deltas: Array[float] = []
## kind -> {id -> [last position, last step, has step]}
var _tracks := {}
var _camera_track: Array = []
## kind -> judder samples (screen px): own motion, against the camera, and step length
var _own := {}
var _relative := {}
var _steps := {}
## cause -> camera judder samples on frames with that cause
var _camera_causes := {}


func clear() -> void:
	_last_frame_us = 0
	_intervals.clear()
	_deltas.clear()
	_tracks.clear()
	_camera_track = []
	_own.clear()
	_relative.clear()
	_steps.clear()
	_camera_causes.clear()


## One displayed frame: the delta it advanced by, the camera centre, and per kind
## of object ("enemy", "bullet") a table of id -> world position.
## `camera_cause` sorts the camera's judder by what else happened that frame
## ("turned", "corrected", "steady"), so input and reconciliation can be told from timing.
func sample(delta: float, camera_centre: Vector2, groups: Dictionary, camera_cause := "") -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_us > 0:
		_intervals.append((now - _last_frame_us) / 1000.0)
		_deltas.append(delta * 1000.0)
	_last_frame_us = now
	var camera_jerk := Vector2.ZERO
	if _camera_track.is_empty():
		_camera_track = [camera_centre, Vector2.ZERO, false]
	else:
		var jerk: Variant = _step(_camera_track, camera_centre)
		if jerk is Vector2:
			camera_jerk = jerk
			_record(_own, "camera", camera_jerk)
			_record(_steps, "camera", _camera_track[1])
			if camera_cause != "":
				_record(_camera_causes, camera_cause, camera_jerk)
	for kind: String in groups:
		var positions: Dictionary = groups[kind]
		var tracks: Dictionary = _tracks.get(kind, {})
		_tracks[kind] = tracks
		for id in positions:
			var track: Array = tracks.get(id, [])
			if track.is_empty():
				tracks[id] = [positions[id], Vector2.ZERO, false]
				continue
			var jerk: Variant = _step(track, positions[id])
			if jerk is Vector2:
				_record(_own, kind, jerk)
				_record(_relative, kind, jerk - camera_jerk)
				_record(_steps, kind, track[1])
		for id in tracks.keys():
			if not positions.has(id):
				tracks.erase(id)


func _step(track: Array, position: Vector2) -> Variant:
	var step: Vector2 = position - track[0]
	var jerk: Variant = (step - track[1]) if track[2] else null
	track[0] = position
	track[1] = step
	track[2] = true
	return jerk


func _record(into: Dictionary, kind: String, value: Vector2) -> void:
	# Packed arrays are values: append to the stored one, not a copy of it.
	var samples: PackedFloat32Array = into.get(kind, PackedFloat32Array())
	samples.append(value.length() * zoom)
	into[kind] = samples


func report() -> PackedStringArray:
	var lines := PackedStringArray()
	if _intervals.is_empty():
		return lines
	var sorted := _intervals.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	var deltas := _deltas.duplicate()
	deltas.sort()
	var off_beat := 0
	for value in _deltas:
		if absf(value - deltas[deltas.size() / 2]) > 0.5:
			off_beat += 1
	lines.append("PACING frame interval median=%.2fms sd=%.2fms p99=%.2fms   advanced-by delta median=%.2fms, %d of %d frames off it (min %.2f max %.2f)" % [
		median, _stddev(_intervals), _pct(sorted, 0.99), deltas[deltas.size() / 2], off_beat, _deltas.size(),
		deltas[0], deltas[-1]])
	for kind: String in _own:
		var line := "PACING %-7s step %.2fpx  judder mean %.3fpx p95 %.3fpx p99 %.3fpx  frames juddering %.1f%%" % [
			kind, _mean(_steps[kind]), _mean(_own[kind]), _pct_packed(_own[kind], 0.95),
			_pct_packed(_own[kind], 0.99), _over(_own[kind]) * 100.0]
		if _relative.has(kind):
			line += "  | vs camera mean %.3fpx p95 %.3fpx juddering %.1f%%" % [_mean(_relative[kind]),
				_pct_packed(_relative[kind], 0.95), _over(_relative[kind]) * 100.0]
		lines.append(line)
	for cause: String in _camera_causes:
		var samples: PackedFloat32Array = _camera_causes[cause]
		lines.append("PACING camera on %-9s frames: %5d  judder mean %.3fpx p95 %.3fpx  juddering %.1f%%" % [
			cause, samples.size(), _mean(samples), _pct_packed(samples, 0.95), _over(samples) * 100.0])
	return lines


static func _over(samples: PackedFloat32Array) -> float:
	var count := 0
	for value in samples:
		if value > HITCH_PX:
			count += 1
	return float(count) / maxf(samples.size(), 1.0)


static func _mean(samples: Variant) -> float:
	var total := 0.0
	for value in samples:
		total += value
	return total / maxf(samples.size(), 1.0)


static func _stddev(samples: Array[float]) -> float:
	var mean := _mean(samples)
	var total := 0.0
	for value in samples:
		total += (value - mean) * (value - mean)
	return sqrt(total / maxf(samples.size(), 1.0))


static func _pct(sorted: Array, fraction: float) -> float:
	return sorted[clampi(int(sorted.size() * fraction), 0, sorted.size() - 1)]


static func _pct_packed(samples: PackedFloat32Array, fraction: float) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[clampi(int(sorted.size() * fraction), 0, sorted.size() - 1)]
