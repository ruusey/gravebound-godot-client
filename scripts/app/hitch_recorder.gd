class_name HitchRecorder
extends Node

## Records where each frame's time goes, to say what a hitch was.
##
## A frame that runs past one display refresh misses it, and the whole screen
## holds a frame then jumps -- the frame-rate counter barely moves. Each frame is
## split into: reading and decoding the socket, applying the packets (per packet
## type), simulation, every other node's _process, the canvas _draw pass and the
## present (the render server's work plus the buffer swap, which under vsync waits
## for the refresh -- so most of it is idle). The viewport's measured render CPU and
## GPU times sit beside it. Alongside: what arrived that frame and how busy the
## realm was. A hitch is a frame interval past HITCH_FACTOR of the normal one; it is
## blamed on the script phase that overran, on the GPU, or on the present when both
## fit and the swap still missed a refresh (the compositor, the driver, the browser).
##
## Started with the record_hitches key (F4 by default), /hitch [seconds], or
## --hitch=SECONDS from the command line; the report goes to the console, the
## clipboard, user://hitch-reports and chat.

signal finished(report: String)

const DEFAULT_SECONDS := 60.0
const HITCH_FACTOR := 1.5
## Movement packets in one frame past this mean the network delivered a clump.
const BURST_MOVES := 3
const WORST_LISTED := 15
const REPORT_DIR := "user://hitch-reports"
## How many of each kind the pacing probe follows: enough to average, few enough to stay cheap.
const PACED_ENEMIES := 40
const PACED_BULLETS := 200

var client: GraveBoundClient
var state: RealmState
## The ground's chunk cache, for how much of the draw phase was chunk painting.
var ground: GroundChunks

var _recording := false
var _ends_us := 0
var _seconds := 0.0
var _phase_us := 0
var _bytes_at_start := 0
var _last_packet_us := 0
var _frame_delta := 0.0
var _corrections_seen := 0
var _corrections_at_start := 0
var _corrected := false
var _last_input := Vector2.ZERO
var _turned := false
var _last_pace := 0.0
## What else moved the camera's step this frame besides time: see mark_simulation.
var _camera_cause := "steady"
var _pacing := PacingProbe.new()

var _start_us := PackedInt64Array()
var _read_ms := PackedFloat32Array()
var _apply_ms := PackedFloat32Array()
var _sim_ms := PackedFloat32Array()
var _ui_ms := PackedFloat32Array()
var _draw_ms := PackedFloat32Array()
var _present_ms := PackedFloat32Array()
var _render_cpu_ms := PackedFloat32Array()
var _gpu_ms := PackedFloat32Array()
var _bytes := PackedInt32Array()
var _bullets := PackedInt32Array()
var _enemies := PackedInt32Array()
var _effects := PackedInt32Array()
var _chunk_ms := PackedFloat32Array()
var _chunk_paints := PackedInt32Array()
var _chunk_repaints := PackedInt32Array()
var _ground_seen := [0, 0, 0]
## Per frame: packet name -> [count, apply microseconds], or null when none arrived.
var _packets: Array = []


func _ready() -> void:
	# Last of every node's _process, so the gap from the simulation mark to here is the rest of the tree.
	process_priority = 4096
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func recording() -> bool:
	return _recording


func start(seconds := DEFAULT_SECONDS) -> void:
	for series in [_start_us, _read_ms, _apply_ms, _sim_ms, _ui_ms, _draw_ms, _present_ms, _render_cpu_ms,
			_gpu_ms, _bytes, _bullets, _enemies, _effects, _chunk_ms, _chunk_paints, _chunk_repaints]:
		series.clear()
	_packets.clear()
	_pacing.clear()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_corrections_seen = state.movement.corrections
	_corrections_at_start = state.movement.corrections
	if ground != null:
		_ground_seen = [ground.paints, ground.repaints, ground.paint_us]
	_seconds = seconds
	_ends_us = Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	_bytes_at_start = client.stats.bytes_in
	if not client.packet_received.is_connected(_on_packet):
		client.packet_received.connect(_on_packet)
	_recording = true


## Stops early and reports what was recorded.
func stop() -> void:
	if _recording:
		_finish()


## `delta` is what the frame advances the world by, for the pacing probe.
func begin_frame(delta: float) -> void:
	if not _recording:
		return
	_frame_delta = delta
	var now := Time.get_ticks_usec()
	if now >= _ends_us:
		_finish()
		return
	_start_us.append(now)
	for series in [_read_ms, _apply_ms, _sim_ms, _ui_ms, _draw_ms, _present_ms, _render_cpu_ms, _gpu_ms]:
		series.append(0.0)
	_bytes.append(0)
	_chunk_ms.append(0.0)
	_chunk_paints.append(0)
	_chunk_repaints.append(0)
	_bullets.append(0)
	_enemies.append(0)
	_effects.append(0)
	_packets.append(null)
	_phase_us = now


func mark_network() -> void:
	if not _recording or _start_us.is_empty():
		return
	var now := Time.get_ticks_usec()
	var last := _start_us.size() - 1
	var read_done := clampi(client.read_done_us, _phase_us, now)
	_read_ms[last] = (read_done - _phase_us) / 1000.0
	_apply_ms[last] = (now - read_done) / 1000.0
	var bytes_now := client.stats.bytes_in
	_bytes[last] = bytes_now - _bytes_at_start
	_bytes_at_start = bytes_now
	_phase_us = now


func mark_simulation() -> void:
	if not _recording or _start_us.is_empty():
		return
	var now := Time.get_ticks_usec()
	var last := _start_us.size() - 1
	_sim_ms[last] = (now - _phase_us) / 1000.0
	_corrected = state.movement.corrections != _corrections_seen
	_corrections_seen = state.movement.corrections
	_turned = state.movement.last_input != _last_input
	_last_input = state.movement.last_input
	var pace := state.movement.pace_px
	var moved := state.local.position.distance_to(state.local.previous_position)
	var sped := absf(pace - _last_pace) > 0.01 * maxf(pace, 0.01)
	_last_pace = pace
	if _corrected:
		_camera_cause = "corrected"
	elif _turned:
		_camera_cause = "turned"
	elif sped:
		_camera_cause = "speed"
	elif state.local.moving and moved > 0.0 and moved < pace * 0.95:
		_camera_cause = "blocked"
	else:
		_camera_cause = "steady"
	_bullets[last] = state.projectiles.bullets.size()
	_enemies[last] = state.entities.enemies.size()
	_effects[last] = state.abilities.effects.size()
	_phase_us = now


func _process(_delta: float) -> void:
	if not _recording or _start_us.is_empty():
		return
	var now := Time.get_ticks_usec()
	_ui_ms[_start_us.size() - 1] = (now - _phase_us) / 1000.0
	_phase_us = now


func _on_pre_draw() -> void:
	if not _recording or _start_us.is_empty():
		return
	var now := Time.get_ticks_usec()
	var last := _start_us.size() - 1
	_draw_ms[last] = (now - _phase_us) / 1000.0
	if ground != null:
		_chunk_ms[last] = (ground.paint_us - _ground_seen[2]) / 1000.0
		_chunk_paints[last] = ground.paints - _ground_seen[0]
		_chunk_repaints[last] = ground.repaints - _ground_seen[1]
		_ground_seen = [ground.paints, ground.repaints, ground.paint_us]
	_pacing.zoom = get_viewport().get_camera_2d().zoom.x if get_viewport().get_camera_2d() != null else 2.0
	_pacing.sample(_frame_delta, state.local.render_centre(), moving_objects(state, PACED_ENEMIES, PACED_BULLETS),
		_camera_cause)
	_phase_us = Time.get_ticks_usec()


func _on_post_draw() -> void:
	if not _recording or _start_us.is_empty():
		return
	var last := _start_us.size() - 1
	_present_ms[last] = (Time.get_ticks_usec() - _phase_us) / 1000.0
	var viewport := get_viewport().get_viewport_rid()
	_render_cpu_ms[last] = RenderingServer.viewport_get_measured_render_time_cpu(viewport) 		+ RenderingServer.get_frame_setup_time_cpu()
	_gpu_ms[last] = RenderingServer.viewport_get_measured_render_time_gpu(viewport)


## Runs right after the realm applied the packet, so the time since the previous
## mark is this packet's handling.
func _on_packet(packet_name: String, _data: Dictionary) -> void:
	if not _recording or _packets.is_empty():
		return
	var now := Time.get_ticks_usec()
	var since := maxi(_last_packet_us, client.read_done_us)
	_last_packet_us = now
	var last := _packets.size() - 1
	if _packets[last] == null:
		_packets[last] = {}
	var entry: Array = _packets[last].get(packet_name, [0, 0])
	entry[0] += 1
	entry[1] += now - since
	_packets[last][packet_name] = entry


func _finish() -> void:
	_recording = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	if client.packet_received.is_connected(_on_packet):
		client.packet_received.disconnect(_on_packet)
	var report := "\n".join(build_report())
	print(report)
	DisplayServer.clipboard_set(report)
	var saved := _save(report)
	if saved != "":
		print("[hitch] report saved to %s" % ProjectSettings.globalize_path(saved))
	finished.emit(report)


func _save(report: String) -> String:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var path := REPORT_DIR.path_join("hitch-%s.txt" % Time.get_datetime_string_from_system().replace(":", "-"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(report)
	return path


## One line for chat: how many hitches and what caused most of them.
func headline() -> String:
	var analysis := _analyse()
	if analysis.is_empty():
		return "Hitch report: no frames recorded."
	return "Hitch report: %d hitches in %.0fs (%.1f/min), worst %.0f ms, mostly %s. Copied to clipboard." % [
		analysis["hitches"].size(), analysis["seconds"], analysis["per_minute"], analysis["worst_ms"],
		analysis["top_cause"]]


func build_report() -> PackedStringArray:
	var lines := PackedStringArray()
	var analysis := _analyse()
	if analysis.is_empty():
		lines.append("[hitch] no frames recorded")
		return lines
	var period: float = analysis["period_ms"]
	lines.append("[hitch] %d frames over %.1fs, frame interval median %.2f ms (%.0f Hz), %s, %s" % [
		analysis["frames"], analysis["seconds"], period, 1000.0 / period, OS.get_name(),
		RenderingServer.get_current_rendering_method()])
	lines.append("[hitch] hitches (> %.1f ms): %d = %.1f/min, worst %.1f ms; causes: %s" % [
		period * HITCH_FACTOR, analysis["hitches"].size(), analysis["per_minute"], analysis["worst_ms"],
		_join_counts(analysis["causes"])])
	lines.append("[hitch] per-frame ms (mean / p99 / max): read %s | apply %s | sim %s | ui %s | draw %s | present %s (render cpu %s, gpu %s)" % [
		_spread(_read_ms), _spread(_apply_ms), _spread(_sim_ms), _spread(_ui_ms), _spread(_draw_ms),
		_spread(_present_ms), _spread(_render_cpu_ms), _spread(_gpu_ms)])
	lines.append("[hitch] network: ping %d ms, jitter %d ms; packets/frame mean %.1f max %d; frames with a burst of >= %d move packets: %d (%d of them hitched); position corrections %d (last %.1f px)" % [
		client.stats.ping_ms, client.stats.jitter_ms, analysis["packets_mean"], analysis["packets_max"],
		BURST_MOVES, analysis["bursts"], analysis["burst_hitches"],
		state.movement.corrections - _corrections_at_start, state.movement.last_correction_px])
	if ground != null:
		var paints := 0
		var repaints := 0
		for i in _chunk_paints.size():
			paints += _chunk_paints[i]
			repaints += _chunk_repaints[i]
		lines.append("[hitch] ground chunks: %d painted (%d were repaints of a drawn chunk), paint ms per frame %s" % [
			paints, repaints, _spread(_chunk_ms)])
	for line in _pacing.report():
		lines.append("[hitch] " + line)
	lines.append("[hitch] packet apply cost by type (total ms / count / worst single-frame ms):")
	for row in analysis["by_type"]:
		lines.append("[hitch]   %-28s %8.1f ms  x%-6d  %.2f ms" % row)
	lines.append("[hitch] worst frames:")
	for index in analysis["worst"]:
		lines.append("[hitch]   " + _frame_line(index, analysis["intervals"][index]))
	return lines


## Where the enemies and steadily-moving bullets are drawn this frame, for the pacing
## probe: {"enemy": {id: position}, "bullet": {id: position}}. Curving and spinning
## bullets are left out; their step changes on purpose.
static func moving_objects(realm: RealmState, enemy_limit: int, bullet_limit := 200) -> Dictionary:
	var enemies := {}
	for id in realm.entities.enemies:
		if enemies.size() >= enemy_limit:
			break
		enemies[id] = realm.entities.render_position(realm.entities.enemies[id])
	var bullets := {}
	var curving := ProjectileKind.TRAIT_PARAMETRIC | ProjectileKind.TRAIT_ORBITAL | ProjectileKind.TRAIT_SPINS \
		| ProjectileKind.TRAIT_LINE_SEGMENT | ProjectileKind.TRAIT_HOMING | ProjectileKind.TRAIT_SPEED_CURVE \
		| ProjectileKind.TRAIT_CONSUMED
	for bullet: Projectile in realm.projectiles.bullets.values():
		if bullets.size() >= bullet_limit:
			break
		if bullet.traits >= 0 and not bullet.traits & curving:
			bullets[bullet.id] = bullet.pos
	return {"enemy": enemies, "bullet": bullets}


func _analyse() -> Dictionary:
	var count := _start_us.size()
	if count < 3:
		return {}
	# A frame's interval runs from its start to the next frame's, so the last one has none.
	var intervals := PackedFloat32Array()
	intervals.resize(count - 1)
	for i in count - 1:
		intervals[i] = (_start_us[i + 1] - _start_us[i]) / 1000.0
	var sorted := intervals.duplicate()
	sorted.sort()
	var period: float = sorted[sorted.size() / 2]
	var hitches: Array[int] = []
	var causes := {}
	var bursts := 0
	var burst_hitches := 0
	var packets_total := 0
	var packets_max := 0
	var by_type := {}
	for i in count - 1:
		var moves := 0
		var arrived := 0
		if _packets[i] != null:
			for packet_name: String in _packets[i]:
				var entry: Array = _packets[i][packet_name]
				arrived += entry[0]
				if packet_name == "ObjectMovePacket" or packet_name == "CompactMovePacket":
					moves += entry[0]
				var totals: Array = by_type.get(packet_name, [0.0, 0, 0.0])
				totals[0] += entry[1] / 1000.0
				totals[1] += entry[0]
				totals[2] = maxf(totals[2], entry[1] / 1000.0)
				by_type[packet_name] = totals
		packets_total += arrived
		packets_max = maxi(packets_max, arrived)
		var hitched := intervals[i] > period * HITCH_FACTOR
		if moves >= BURST_MOVES:
			bursts += 1
			if hitched:
				burst_hitches += 1
		if hitched:
			hitches.append(i)
			var cause := _cause(i, period)
			causes[cause] = int(causes.get(cause, 0)) + 1
	var rows: Array = []
	for packet_name: String in by_type:
		var totals: Array = by_type[packet_name]
		rows.append([packet_name, totals[0], totals[1], totals[2]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var worst: Array = range(count - 1)
	worst.sort_custom(func(a: int, b: int) -> bool: return intervals[a] > intervals[b])
	var seconds := (_start_us[count - 1] - _start_us[0]) / 1_000_000.0
	var top_cause := "nothing"
	var top_count := 0
	for cause: String in causes:
		if causes[cause] > top_count:
			top_cause = cause
			top_count = causes[cause]
	return {"frames": count, "seconds": seconds, "period_ms": period, "intervals": intervals,
		"hitches": hitches, "per_minute": hitches.size() / maxf(seconds / 60.0, 0.001),
		"worst_ms": sorted[-1], "causes": causes, "top_cause": top_cause, "bursts": bursts,
		"burst_hitches": burst_hitches, "packets_mean": float(packets_total) / (count - 1),
		"packets_max": packets_max, "by_type": rows.slice(0, 12),
		"worst": worst.slice(0, WORST_LISTED)}


## The script phase that ate the frame; else "gpu" when the GPU ran past a refresh;
## else "present": the frame's work all fit and the swap still missed the refresh,
## which is the compositor, the driver or the browser.
func _cause(i: int, period: float) -> String:
	var phases := {"net-read": _read_ms[i], "net-apply": _apply_ms[i], "sim": _sim_ms[i],
		"ui": _ui_ms[i], "draw": _draw_ms[i], "render-cpu": _render_cpu_ms[i]}
	var work := 0.0
	var biggest := ""
	for phase: String in phases:
		work += phases[phase]
		if biggest == "" or phases[phase] > phases[biggest]:
			biggest = phase
	# The swap and the compositor take their share too: past this the frame was ours.
	if work > period * 0.8:
		return biggest
	return "gpu" if _gpu_ms[i] > period * 0.9 else "present"


func _frame_line(i: int, interval: float) -> String:
	var arrived := PackedStringArray()
	if _packets[i] != null:
		for packet_name: String in _packets[i]:
			var entry: Array = _packets[i][packet_name]
			arrived.append("%s x%d %.1fms" % [packet_name.trim_suffix("Packet"), entry[0], entry[1] / 1000.0])
	var at := (_start_us[i] - _start_us[0]) / 1_000_000.0
	return "t=%6.2fs %6.1f ms | read %.1f apply %.1f sim %.1f ui %.1f draw %.1f (chunks %d/%d %.1f) present %.1f (cpu %.1f gpu %.1f) | %d B | bullets %d enemies %d effects %d | %s" % [
		at, interval, _read_ms[i], _apply_ms[i], _sim_ms[i], _ui_ms[i], _draw_ms[i], _chunk_paints[i],
		_chunk_repaints[i], _chunk_ms[i], _present_ms[i], _render_cpu_ms[i], _gpu_ms[i], _bytes[i], _bullets[i], _enemies[i], _effects[i], ", ".join(arrived) if not arrived.is_empty() else "no packets"]


static func _spread(series: PackedFloat32Array) -> String:
	var sorted := series.duplicate()
	sorted.sort()
	var total := 0.0
	for value in series:
		total += value
	return "%.2f/%.2f/%.1f" % [total / maxf(series.size(), 1.0),
		sorted[clampi(int(sorted.size() * 0.99), 0, sorted.size() - 1)], sorted[-1]]


static func _join_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"
	var parts := PackedStringArray()
	for key: String in counts:
		parts.append("%s %d" % [key, counts[key]])
	return ", ".join(parts)
