class_name BenchWorldNode
extends Node

## Frame-cost benchmark: a synthetic bullet-hell realm driven through the real
## renderer, lighting and overlay, with no server.
##
##   godot --path . res://tests/tools/bench_world.tscn -- --bullets=1500 --enemies=150
##       --players=30 --effects=40 --seconds=10 [--data=<gravebound-data resources dir>]
##       [--hide=bullets,entities,lighting,overlay,chunk,...] [--out=<report file>]
##
## --headless measures the script (CPU) cost alone; windowed adds the GPU. --hide
## leaves world layers out to attribute draw cost; "chunk" instead turns on a probe
## that repaints one ground chunk every frame and reports what that costs.

const MAP_SIZE := 96
const SHALLOW_WATER_TILE := 5
const LAVA_TILE := 25
const MOVE_INTERVAL_MS := 62.5
const UNLOAD_INTERVAL_MS := 125.0

var bullets_target := 1500
## Persistent LINE_SEGMENT wall hazards (like a dungeon arena). Each renders as a
## row of length/size tiles, so this is the knob for the wall-render cost.
var walls_target := 0
## Active ability effects to hold on the effects layer (a crowd of casters). Each
## is a procedural AoE drawer redrawn every frame, so this is the knob for the
## effect-render cost that a real fight has but a bullets-only bench does not.
var effects_target := 0
var enemy_count := 150
var player_count := 30
var seconds := 10.0
var data_root := ""
## World layers (WorldRenderer member names) left invisible, to attribute draw cost.
var hidden_layers: PackedStringArray = []
## Also writes the report here: a release build has no console to print to.
var out_path := ""
## Water and lava blobs in the floor, so the liquid layer and its shores are drawn.
var shores := false
## Walk the local player in a wandering loop so the camera pans across the tile
## field -- the only way the movement-triggered light rescan (SceneLighting) is
## exercised; a stationary player rescans only on the slow fixed cadence.
var walk := false
## Arena-style wave turnover: every `wave_period` seconds unload every enemy and load
## a fresh batch of `enemy_count` at once, the way a wave spawns. The frames right after
## each spawn are timed on their own, so a one-frame stall on "enemies loading in" shows
## up separately from the steady cost (which pre-spawned warmup frames hide). Off by default.
var waves := false
const WAVE_PERIOD := 2.0
## Frames attributed to a spawn after each wave lands (the stall, if any, is on the
## load frame and the immediate-mode redraw that follows it).
const WAVE_WATCH := 4
var _lines: PackedStringArray = []

var content: GameData
var state: RealmState
var world: WorldRenderer
var lighting: SceneLighting
var overlay: EntityOverlay
var camera: Camera2D

var _groups: Array[int] = []
var _effect_types: Array[int] = []
var _next_bullet_id := 1_000_000
var _since_move := 0.0
var _since_unload := 0.0
var _clock := 0.0
var _running := false
var _frames: Array[float] = []
var _advance_us: Array[float] = []
var _overlay_us: Array[float] = []
var _draw_us: Array[float] = []
var _process_end_us := 0
var _last_frame_us := 0
var _started_us := 0
var _bullet_samples := 0
var _rng := RandomNumberGenerator.new()
var _sections := {}
var _chunk_probe: Node2D
var _frame_start_us := 0
var _since_wave := 0.0
var _wave_watch := 0
var _wave_draw_watch := 0
var _spawn_frames: Array[float] = []
var _spawn_net_us: Array[float] = []
var _spawn_draw_us: Array[float] = []
var _wave_count := 0


func _ready() -> void:
	_rng.seed = 7
	_parse_args()
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	content = GameData.new()
	if not await content.load_from(FileContentSource.new(data_root)):
		push_error("content failed to load from %s" % data_root)
		get_tree().quit(1)
		return
	state = RealmState.new(content)
	state.settings.set_on("show_other_bullets", true)
	state.settings.set_on("ability_animations", true)
	state.settings.set_on("show_ally_effects", true)
	if "lighting" in hidden_layers:
		state.settings.set_on("lighting", false)
	state.settings.set_on("vsync", false)
	_build_world()
	_pick_groups()
	_populate()
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	_started_us = Time.get_ticks_usec()
	_last_frame_us = _started_us
	_running = true


func _parse_args() -> void:
	data_root = ProjectSettings.globalize_path("res://").path_join("../gravebound-data/src/main/resources").simplify_path()
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"bullets": bullets_target = int(parts[1])
			"walls": walls_target = int(parts[1])
			"effects": effects_target = int(parts[1])
			"enemies": enemy_count = int(parts[1])
			"players": player_count = int(parts[1])
			"seconds": seconds = float(parts[1])
			"data": data_root = parts[1]
			"hide": hidden_layers = parts[1].split(",")
			"out": out_path = parts[1]
			"shores": shores = parts[1] == "1"
			"walk": walk = parts[1] == "1"
			"waves": waves = parts[1] == "1"


func _build_world() -> void:
	world = WorldRenderer.new()
	world.setup(state, content)
	add_child(world)
	for layer in hidden_layers:
		if world.get(layer) is CanvasItem:
			(world.get(layer) as CanvasItem).visible = false
	lighting = SceneLighting.new()
	lighting.setup(state, content)
	add_child(lighting)
	world.set_process(false)
	lighting.set_process(false)
	camera = Camera2D.new()
	camera.zoom = Vector2(DisplayScale.WORLD_ZOOM, DisplayScale.WORLD_ZOOM)
	add_child(camera)
	camera.make_current()
	overlay = EntityOverlay.new()
	overlay.setup(state, content)
	add_child(overlay)
	overlay.set_process(false)
	_chunk_probe = Node2D.new()
	_chunk_probe.set_script(load("res://tests/tools/bench_chunk_probe.gd"))
	_chunk_probe.set("ground", world.tiles)
	_chunk_probe.set("liquid", world.liquid)
	_chunk_probe.visible = "chunk" in hidden_layers
	add_child(_chunk_probe)
	# Last in the tree, so its _process marks the end of every other node's.
	var marker := Node.new()
	marker.set_script(load("res://tests/tools/bench_process_marker.gd"))
	marker.set("bench", self)
	add_child(marker)


func _pick_groups() -> void:
	for group_id in content.library.projectile_groups:
		if content.projectile_texture(int(group_id)) != null:
			_groups.append(int(group_id))
	_groups.sort()
	for type_id in EffectType.NAMES:
		_effect_types.append(int(type_id))
	_effect_types.sort()


func _populate() -> void:
	var floor_id := -1
	var wall_id := -1
	for tile_id in content.library.tiles:
		var data := content.tile_data(int(tile_id))
		if floor_id < 0 and int(tile_id) > 0 and int(data.get("hasCollision", 0)) == 0 \
				and not content.tile_is_liquid(int(tile_id)):
			floor_id = int(tile_id)
		if wall_id < 0 and content.tile_is_wall(int(tile_id)):
			wall_id = int(tile_id)
	var tiles := []
	for y in MAP_SIZE:
		for x in MAP_SIZE:
			# A crystal accent every few cells, so the lighting has emitters to light.
			var lit := (x * 7 + y * 3) % 23 == 0
			var ground := 124 if lit else floor_id
			if shores:
				var blob := sin(x * 0.45) + sin(y * 0.38 + x * 0.12)
				if blob > 0.9:
					ground = SHALLOW_WATER_TILE
				elif blob < -1.2:
					ground = LAVA_TILE
			tiles.append({"tileId": ground, "layer": 0, "xIndex": y, "yIndex": x})
			var edge := x == 0 or y == 0 or x == MAP_SIZE - 1 or y == MAP_SIZE - 1
			if edge or (x % 12 == 0 and y % 12 < 3):
				tiles.append({"tileId": wall_id, "layer": GameConstants.COLLISION_LAYER, "xIndex": y, "yIndex": x})
	var started := Time.get_ticks_usec()
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 1, "mapWidth": MAP_SIZE,
		"mapHeight": MAP_SIZE, "tiles": tiles})
	var first_ms := (Time.get_ticks_usec() - started) / 1000.0
	# The same packet again, the way the server re-sends a tile chunk the client holds.
	started = Time.get_ticks_usec()
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 1, "mapWidth": MAP_SIZE,
		"mapHeight": MAP_SIZE, "tiles": tiles})
	_say("BENCH load_map tiles=%d first=%.1fms again=%.1fms" % [tiles.size(), first_ms,
		(Time.get_ticks_usec() - started) / 1000.0])

	var centre := Vector2(MAP_SIZE, MAP_SIZE) * GameConstants.TILE_SIZE * 0.5
	state.local.id = 1
	state.local.name = "bench"
	state.local.position = centre
	state.local.previous_position = centre
	var players := [_player_wire(1, centre)]
	for i in player_count:
		players.append(_player_wire(100 + i, centre + _scatter(220.0)))
	var enemies := []
	var enemy_ids := content.library.enemies.keys()
	for i in enemy_count:
		enemies.append({"id": 10_000 + i, "enemyId": int(enemy_ids[i % enemy_ids.size()]),
			"weaponId": 0, "size": 32, "pos": _vec(centre + _scatter(300.0)), "dX": 0.0, "dY": 0.0,
			"difficulty": 1.0, "health": 800, "maxHealth": 1000, "shortId": 0})
	state.apply_packet("LoadPacket", {"players": players, "enemies": enemies})


func _player_wire(id: int, at: Vector2) -> Dictionary:
	return {"id": id, "name": "p%d" % id, "accountUuid": "", "characterUuid": "",
		"classId": id % 8, "size": 28, "pos": _vec(at), "dX": 0.0, "dY": 0.0,
		"shortId": 0, "chatRole": "", "dyeId": 0}


func _scatter(radius: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * radius


static func _vec(at: Vector2) -> Dictionary:
	return {"x": at.x, "y": at.y}


func _process(delta: float) -> void:
	if not _running:
		return
	var now_us := Time.get_ticks_usec()
	var frame_ms := (now_us - _last_frame_us) / 1000.0
	_frames.append(frame_ms)
	if _wave_watch > 0:
		_spawn_frames.append(frame_ms)
		_wave_watch -= 1
	_last_frame_us = now_us
	_clock += delta * 1000.0
	_since_move += delta * 1000.0
	_since_unload += delta * 1000.0
	if waves:
		_since_wave += delta * 1000.0
		if _since_wave >= WAVE_PERIOD * 1000.0:
			_since_wave = 0.0
			_fire_wave()
	_frame_start_us = now_us
	var net_started := Time.get_ticks_usec()
	if _since_move >= MOVE_INTERVAL_MS:
		_since_move = fmod(_since_move, MOVE_INTERVAL_MS)
		_send_moves()
	if _since_unload >= UNLOAD_INTERVAL_MS:
		_since_unload = 0.0
		_send_unloads()
	_spawn_bullets()
	_spawn_walls()
	_spawn_effects()
	_section("net", net_started)

	var started := Time.get_ticks_usec()
	_advance_sections(delta)
	_advance_us.append(Time.get_ticks_usec() - started)
	_bullet_samples += state.projectiles.bullets.size()

	PixelSnap.camera(camera, state.local.render_centre(), state.local.render_position())
	var t := Time.get_ticks_usec()
	world._process(delta)
	t = _section("world_process", t)
	lighting._process(delta)
	_section("lighting_process", t)
	if (now_us - _started_us) > int(seconds * 1_000_000.0):
		_report()


## RealmState.advance, step by step, so each part's cost is reported.
func _advance_sections(delta: float) -> void:
	var t := Time.get_ticks_usec()
	state.projectiles.latency_ms = 60.0
	state.transition.expire()
	state.local.decay_smoothing(delta)
	state.movement.predict(delta, _walk_input())
	state.local.walk.advance(state.movement.pace_px, delta)
	state.local.attack.tick(delta)
	RemoteAnimation.advance(state.entities.players, delta)
	RemoteAnimation.advance(state.entities.enemies, delta)
	t = _section("entities", t)
	state.projectiles.advance(delta)
	t = _section("projectiles", t)
	state.particles.advance(delta, state.projectiles.bullets, BulletVisibility.of(state))
	t = _section("particles", t)
	state.texts.advance(delta)
	state.abilities.expire()
	state.minimap.expire()
	state.trade.expire()
	state.party.expire()
	state.pvp.expire()
	_section("rest", t)


## A wandering walk direction: a slowly rotating heading that steers back toward the
## map centre once the player drifts far, so it keeps crossing the emitter/wall field
## instead of lodging in a corner. Vector2.ZERO (stationary) unless --walk=1.
func _walk_input() -> Vector2:
	if not walk:
		return Vector2.ZERO
	var centre := Vector2(MAP_SIZE, MAP_SIZE) * GameConstants.TILE_SIZE * 0.5
	var from_centre := state.local.position - centre
	if from_centre.length() > 800.0:
		return -from_centre.normalized()
	return Vector2.from_angle(_clock / 1000.0 * 0.7)


func _section(name: String, since_us: int) -> int:
	var now := Time.get_ticks_usec()
	_sections[name] = float(_sections.get(name, 0.0)) + (now - since_us)
	return now


func mark_process_end() -> void:
	if not _running:
		return
	var started := Time.get_ticks_usec()
	if not "overlay" in hidden_layers:
		overlay.refresh()
	_overlay_us.append(Time.get_ticks_usec() - started)
	_process_end_us = Time.get_ticks_usec()
	_section("all_process", _frame_start_us)


func _on_pre_draw() -> void:
	if _running and _process_end_us > 0:
		var draw_us := Time.get_ticks_usec() - _process_end_us
		_draw_us.append(draw_us)
		if _wave_draw_watch > 0:
			_spawn_draw_us.append(draw_us)
			_wave_draw_watch -= 1


## Arena wave turnover: drop every enemy and load a fresh batch at once, so the apply
## cost (CPU) is timed on its own and the next frames' deltas/draws capture any stall
## the "enemies loading in" causes. Ids are reused so the steady _send_moves stays valid;
## the dicts are freed and rebuilt, so first-sight work (bar/tag pools, light defs) still runs.
func _fire_wave() -> void:
	var gone := []
	for i in enemy_count:
		gone.append(10_000 + i)
	var centre := Vector2(MAP_SIZE, MAP_SIZE) * GameConstants.TILE_SIZE * 0.5
	var enemies := []
	var enemy_ids := content.library.enemies.keys()
	for i in enemy_count:
		enemies.append({"id": 10_000 + i, "enemyId": int(enemy_ids[(i + _wave_count) % enemy_ids.size()]),
			"weaponId": 0, "size": 32, "pos": _vec(centre + _scatter(300.0)), "dX": 0.0, "dY": 0.0,
			"difficulty": 1.0, "health": 800, "maxHealth": 1000, "shortId": 0})
	var started := Time.get_ticks_usec()
	state.apply_packet("UnloadPacket", {"enemies": gone})
	state.apply_packet("LoadPacket", {"players": [], "enemies": enemies})
	_spawn_net_us.append(Time.get_ticks_usec() - started)
	_wave_watch = WAVE_WATCH
	_wave_draw_watch = WAVE_WATCH
	_wave_count += 1


func _send_moves() -> void:
	var movements := []
	var t := _clock / 1000.0
	var centre := Vector2(MAP_SIZE, MAP_SIZE) * GameConstants.TILE_SIZE * 0.5
	for i in enemy_count:
		var phase := float(i) * 0.37
		var at := centre + Vector2(cos(t * 0.6 + phase), sin(t * 0.8 + phase)) * (120.0 + (i % 9) * 22.0)
		var velocity := Vector2(-sin(t * 0.6 + phase) * 0.6, cos(t * 0.8 + phase) * 0.8) \
			* (120.0 + (i % 9) * 22.0) / GameConstants.TICK_RATE
		movements.append({"entityType": GameConstants.ENTITY_ENEMY, "entityId": 10_000 + i,
			"posX": at.x, "posY": at.y, "velX": velocity.x, "velY": velocity.y, "flags": 0})
	for i in player_count:
		var at := centre + Vector2(cos(t + i), sin(t * 1.3 + i)) * 200.0
		movements.append({"entityType": GameConstants.ENTITY_PLAYER, "entityId": 100 + i,
			"posX": at.x, "posY": at.y, "velX": 0.0, "velY": 0.0, "flags": 0})
	state.apply_packet("ObjectMovePacket", {"movements": movements})


func _send_unloads() -> void:
	var gone := []
	for bullet: Projectile in state.projectiles.bullets.values():
		if bullet.traveled > bullet.range:
			gone.append(bullet.id)
	if not gone.is_empty():
		state.apply_packet("UnloadPacket", {"bullets": gone})


func _spawn_bullets() -> void:
	var missing := bullets_target - state.projectiles.bullets.size()
	if missing <= 0:
		return
	var wires := []
	var enemies := state.entities.enemies.keys()
	var shooters := enemies + state.entities.players.keys()
	while missing > 0:
		var source: int = shooters[_rng.randi() % shooters.size()]
		var entity := state.entities.find_any(source)
		var origin := state.entities.render_position(entity) + Vector2(16, 16)
		var group_id: int = _groups[_rng.randi() % _groups.size()]
		var burst := mini(missing, 8)
		var base := _rng.randf() * TAU
		for k in burst:
			_next_bullet_id += 1
			wires.append({"id": _next_bullet_id, "projectileId": group_id, "pos": _vec(origin),
				"size": 12, "angle": base + k * TAU / burst, "magnitude": 3.0 + _rng.randf() * 2.0,
				"range": 300.0 + _rng.randf() * 200.0, "damage": 10,
				"flags": [] if (k % 5) else [ProjectileKind.PARAMETRIC],
				"amplitude": 8.0 if (k % 5) == 0 else 0.0, "frequency": 12.0 if (k % 5) == 0 else 0.0,
				"srcEntityId": source})
		missing -= burst
	state.apply_packet("LoadPacket", {"bullets": wires})


## Maintain `walls_target` persistent LINE_SEGMENT walls scattered on open floor.
## Static (magnitude 0) with a huge range; topped up as the wall-life cap recycles them.
func _spawn_walls() -> void:
	if walls_target <= 0:
		return
	var have := 0
	for bullet: Projectile in state.projectiles.bullets.values():
		if bullet.traits & ProjectileKind.TRAIT_LINE_SEGMENT:
			have += 1
	var missing := walls_target - have
	if missing <= 0:
		return
	var centre := Vector2(MAP_SIZE, MAP_SIZE) * GameConstants.TILE_SIZE * 0.5
	var wires := []
	for i in missing:
		_next_bullet_id += 1
		# A frequency makes the wall SWEEP (angle advances every tick), like the real
		# moving arena hazards — so every tile transform genuinely changes each frame.
		wires.append({"id": _next_bullet_id, "projectileId": _groups[_rng.randi() % _groups.size()],
			"pos": _vec(centre + _scatter(360.0)), "size": 16, "angle": _rng.randf() * TAU,
			"magnitude": 0.0, "range": 1.0e9, "damage": 0, "length": 240.0 + _rng.randf() * 200.0,
			"frequency": 20.0 + _rng.randf() * 40.0,
			"flags": [ProjectileKind.LINE_SEGMENT], "srcEntityId": 10_000})
	state.apply_packet("LoadPacket", {"bullets": wires})


## Tops the effects layer up to `effects_target` active, each a different drawer
## type scattered near the fray with a 1.2-1.8s life, so a steady crowd of casts
## churns through every fx_*.gd the way a real boss fight does.
func _spawn_effects() -> void:
	if effects_target <= 0 or _effect_types.is_empty():
		return
	var centre := Vector2(MAP_SIZE, MAP_SIZE) * GameConstants.TILE_SIZE * 0.5
	var missing := effects_target - state.abilities.effects.size()
	while missing > 0:
		missing -= 1
		var at := centre + _scatter(320.0)
		var target := at + _scatter(120.0)
		state.apply_packet("CreateEffectPacket", {
			"effectType": _effect_types[_rng.randi() % _effect_types.size()],
			"posX": at.x, "posY": at.y, "radius": 40.0 + _rng.randf() * 50.0,
			"duration": 1200 + _rng.randi() % 600, "targetPosX": target.x, "targetPosY": target.y,
			"tier": _rng.randi() % 7, "ownerId": state.local.id})


func _report() -> void:
	_running = false
	var frames := _frames.slice(10)
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in frames:
		total += ms
	var mean := total / maxf(frames.size(), 1.0)
	_say("BENCH bullets=%d enemies=%d players=%d renderer=%s" % [bullets_target, enemy_count,
		player_count, DisplayServer.get_name()])
	_say("BENCH frames=%d fps=%.1f mean=%.2fms p50=%.2fms p95=%.2fms p99=%.2fms max=%.2fms" % [
		frames.size(), 1000.0 / mean, mean, _pct(sorted, 0.5), _pct(sorted, 0.95), _pct(sorted, 0.99),
		sorted[-1]])
	_say("BENCH advance=%.2fms overlay=%.2fms draw=%.2fms avg_bullets=%d" % [
		_mean(_advance_us) / 1000.0, _mean(_overlay_us) / 1000.0, _mean(_draw_us) / 1000.0,
		_bullet_samples / maxi(_frames.size(), 1)])
	# Where the worst frames spend their time: isolates a stall to script-advance,
	# overlay, or the draw step (immediate-mode layer _draw on the main thread).
	_say("BENCH maxes advance=%.2fms overlay=%.2fms draw=%.2fms" % [
		_max(_advance_us) / 1000.0, _max(_overlay_us) / 1000.0, _max(_draw_us) / 1000.0])
	# Wave-spawn frames on their own: the apply cost (unload+load CPU), the worst frame
	# delta in the window after each spawn, and the worst draw step there. A spawn stall
	# shows as a spawn-frame max well over the steady p99; a clean one tracks it.
	if waves:
		var spawn_sorted := _spawn_frames.duplicate()
		spawn_sorted.sort()
		# _spawn_frames are already ms (frame deltas); the _us arrays are microseconds.
		_say("BENCH waves=%d spawn_apply_mean=%.2fms spawn_apply_max=%.2fms spawn_frame_mean=%.2fms spawn_frame_max=%.2fms spawn_draw_max=%.2fms" % [
			_wave_count, _mean(_spawn_net_us) / 1000.0, _max(_spawn_net_us) / 1000.0,
			_mean(_spawn_frames), spawn_sorted[-1] if not spawn_sorted.is_empty() else 0.0,
			_max(_spawn_draw_us) / 1000.0])
	var parts := []
	for name in _sections:
		parts.append("%s=%.2fms" % [name, _sections[name] / 1000.0 / maxf(_frames.size(), 1.0)])
	_say("BENCH sections %s" % " ".join(parts))
	_say("BENCH drawn=%s" % world.draw_stats)
	if _chunk_probe.visible:
		var samples: Array[float] = _chunk_probe.get("samples")
		var liquid_samples: Array[float] = _chunk_probe.get("liquid_samples")
		_say("BENCH chunk_paint=%.2fms liquid_paint=%.2fms" % [_mean(samples) / 1000.0,
			_mean(liquid_samples) / 1000.0])
	_say("BENCH draw_calls=%d objects_drawn=%d primitives=%d video_mem=%.1fMB" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_say("BENCH static_mem=%.1fMB objects=%d" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT)])
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string("\n".join(_lines))
	get_tree().quit(0)


func _say(line: String) -> void:
	print(line)
	_lines.append(line)


static func _pct(sorted: Array, fraction: float) -> float:
	return sorted[clampi(int(sorted.size() * fraction), 0, sorted.size() - 1)]


static func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(values.size(), 1.0)


static func _max(values: Array[float]) -> float:
	var top := 0.0
	for value in values:
		top = maxf(top, value)
	return top
