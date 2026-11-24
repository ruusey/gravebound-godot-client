class_name PerfTelemetry
extends Node

## Prints one `[perf] {json}` line a second: the engine's own counters beside
## what the world holds and what the socket delivered, so a browser harness
## reading the console can tell a leak (objects or nodes climbing while the scene
## stands still) from a stall (a worst frame that lines up with a packet burst).
## Behind --perf-log only.

const PREFIX := "[perf] "
const SLOW_FRAME_MS := 20.0

var state: RealmState
var client: GraveBoundClient

var _elapsed := 0.0
var _frames := 0
var _worst_ms := 0.0
var _slow_frames := 0
var _last_packets := 0
var _last_bytes := 0


func _process(delta: float) -> void:
	var frame_ms := delta * 1000.0
	_frames += 1
	_worst_ms = maxf(_worst_ms, frame_ms)
	if frame_ms > SLOW_FRAME_MS:
		_slow_frames += 1
	_elapsed += delta
	if _elapsed < 1.0:
		return
	print(PREFIX + JSON.stringify(sample()))
	_elapsed = 0.0
	_frames = 0
	_worst_ms = 0.0
	_slow_frames = 0


func sample() -> Dictionary:
	var stats: NetStats = client.stats if client != null else null
	var packets: int = stats.packets_in if stats != null else 0
	var bytes: int = stats.bytes_in if stats != null else 0
	var line := {
		"frames": _frames,
		"worst_ms": snappedf(_worst_ms, 0.1),
		"slow_frames": _slow_frames,
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"draw_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"packets": packets - _last_packets,
		"kbytes": snappedf((bytes - _last_bytes) / 1024.0, 0.1),
	}
	_last_packets = packets
	_last_bytes = bytes
	if stats != null:
		line["ping_ms"] = stats.ping_ms
		line["jitter_ms"] = stats.jitter_ms
	if state != null:
		line["players"] = state.entities.players.size()
		line["enemies"] = state.entities.enemies.size()
		line["containers"] = state.entities.containers.size()
		line["bullets"] = state.projectiles.bullets.size()
		line["unacked"] = state.movement.pending_input_count()
		line["corrections"] = state.movement.corrections
	return line
