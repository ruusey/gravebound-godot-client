extends SceneTree

## Replays the slow pipeline -- move, an enemy shot lands, SLOWED, half speed --
## through a model of the server's tick and a laggy, jittery but ordered link,
## with the real MovementPredictor and ProjectileSystem on the client end, and
## reports the corrections the player would see. Deterministic per seed, so a
## change to the client (or to the server model, which mirrors RealmManagerServer)
## can be measured before and after.
##
##   godot --headless --path . --script tests/tools/slow_netcode_sim.gd
##   godot --headless --path . --script tests/tools/slow_netcode_sim.gd -- --seconds=120 --seeds=4 --gap=800
##
## Server tick, in RealmManagerServer.tick order: inbound packets are queued; then
## per player processBulletHit (each loaded enemy shot as the last tick's advance
## left it, rewound by half the reported RTT and swept over one tick, against the
## player where the last processed input left them), removeExpiredEffects and
## movePlayer (stale inputs dropped, guessed steps taken back, up to 32 queued
## inputs, else a guessed step on the last velocity); then the shots advance; then
## enqueueGameData: a PlayerStatePacket the tick the effect set changes, new shots
## every other tick, and a PlayerPosAckPacket every other tick while moving (every
## sixth while idle) carrying how long SLOWED outlasts the acked input.
##
## Columns: corrections over 2px, over 6px, over 12px (past the smoothing cap: a
## visible snap), the worst, the total and per second; then the slowing hits the
## server landed, how many the client predicted, the client's false alarms and
## misses, and how many inputs apart the two judged the hits that both saw.

const TICK_MS := 1000.0 / 64.0
const SLOWED := 21
const HIT_RADIUS_FACTOR := 0.475
const LAG_COMP_MAX_MS := 350.0
const MAX_GUESS_TICKS := 4
const BULLET_SIZE := 10
const BULLET_SPEED := 5.0
const SPAWN_DISTANCE := 150.0
const SHOT_LIFE_MS := 2000.0
const SPD := 50.0
const SLOW_DURATIONS := [1000, 1500, 2000, 2500, 3000]
const ENEMY_ID := 999

var seconds := 60.0
var seeds := 3
var frame_hz := 60.0
var shot_gap_ms := 1600.0
var scenarios := [
	[40.0, 4.0], [100.0, 10.0], [160.0, 20.0], [160.0, 45.0], [250.0, 30.0],
]


class Link:
	extends RefCounted
	## An ordered stream (TCP/WebSocket): nothing overtakes what was sent before it.
	var base_ms := 0.0
	var jitter_ms := 0.0
	var rng: RandomNumberGenerator
	var queue: Array = []
	var _last := 0.0

	func _init(one_way_ms: float, jitter: float, random: RandomNumberGenerator) -> void:
		base_ms = one_way_ms
		jitter_ms = jitter
		rng = random

	func send(now: float, packet: Dictionary) -> void:
		var arrival := maxf(_last, now + base_ms + rng.randf() * jitter_ms)
		_last = arrival
		packet["arrival"] = arrival
		queue.append(packet)

	func receive(now: float) -> Array:
		var out: Array = []
		while not queue.is_empty() and float(queue[0]["arrival"]) <= now:
			out.append(queue.pop_front())
		return out


class Shot:
	extends RefCounted
	var id := 0
	var origin := Vector2.ZERO
	var direction := Vector2.ZERO
	var spawn_ms := 0.0
	var slow_ms := 0
	var alive := true
	var loaded := false

	func at(time_ms: float) -> Vector2:
		return origin + direction * BULLET_SPEED * (time_ms - spawn_ms) / TICK_MS

	func wire(time_ms: float) -> Dictionary:
		var position := at(time_ms)
		# Projectile.angle: velocity is (sin, cos) * magnitude.
		return {"id": id, "projectileId": slow_ms, "pos": {"x": position.x, "y": position.y},
			"size": BULLET_SIZE, "angle": atan2(direction.x, direction.y), "magnitude": BULLET_SPEED,
			"range": 2000.0, "flags": [], "srcEntityId": ENEMY_ID}


class Server:
	extends RefCounted
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var queue: Array = []
	var last_processed := 0
	var last_input_ms := 0.0
	var slow_expiry := -1.0
	var guess_from = null
	var guess_to = null
	var guess_ticks := 0
	var tick := 0
	var sent_slowed := false
	## shot id -> the last processed input when it landed
	var hits := {}
	## [server ms, true when a slow started / false when it ended]
	var transitions: Array = []

	func slowed(now: float) -> bool:
		return now <= slow_expiry

	func step(now: float) -> void:
		var vector := velocity
		if vector.length() > 1.0:
			vector = vector.normalized()
		var tiles_per_second := 4.0 + 5.6 * (SPD / 75.0)
		if slowed(now):
			tiles_per_second *= 0.5
		position += vector * (tiles_per_second * 32.0 / 64.0)


var _rng := RandomNumberGenerator.new()


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		var value: String = pair[1] if pair.size() > 1 else ""
		match pair[0]:
			"seconds": seconds = float(value)
			"seeds": seeds = int(value)
			"fps": frame_hz = float(value)
			"gap": shot_gap_ms = float(value)
	print("slow netcode sim: %ds x %d seeds per scenario, %d fps client, a slowing shot every ~%dms" \
		% [seconds, seeds, frame_hz, shot_gap_ms])
	print("%-12s %6s %6s %6s %6s %7s %6s | %5s %5s %5s %5s %6s %6s | %s" % ["rtt/jitter",
		">2px", ">6px", ">12px", "max", "sum", "px/s", "hits", "match", "false", "miss", "|dseq|", "bias",
		">6px after start/end"])
	for scenario in scenarios:
		var total := {}
		for seed_index in seeds:
			var result := _run(scenario[0], scenario[1], 1000 + seed_index)
			for key in result:
				total[key] = total.get(key, 0.0) + result[key]
		var matched := maxf(1.0, total["matched"])
		print("%-12s %6d %6d %6d %6.1f %7.0f %6.2f | %5d %5d %5d %5d %6.2f %6.2f | %d/%d" % [
			"%d/%d ms" % [scenario[0], scenario[1]],
			total["corrections"], total["over6"], total["over12"], total["max"] / seeds, total["sum"],
			total["sum"] / (seconds * seeds), total["server_hits"], total["matched"],
			total["false_alarms"], total["misses"], total["dseq"] / matched, total["bias"] / matched,
			total["big_start"], total["big_end"]])
	quit()


func _run(rtt: float, jitter: float, run_seed: int) -> Dictionary:
	_rng.seed = run_seed
	var up := Link.new(rtt * 0.5, jitter, _rng)
	var down := Link.new(rtt * 0.5, jitter, _rng)
	# The heartbeat's round trip, which also waits out the server's tick.
	var reported_rtt := rtt + jitter + TICK_MS * 0.5
	var rewind := minf(reported_rtt * 0.5, LAG_COMP_MAX_MS)
	var clock := {"now": 0.0}

	var content := GameData.new()
	for duration in SLOW_DURATIONS:
		content.library.projectile_groups[duration] = {"projectiles": [
			{"effects": [{"effectId": SLOWED, "duration": duration}]}]}
	var player := LocalPlayer.new()
	player.id = 1
	player.stats = {"spd": SPD}
	player.position = Vector2(1000, 1000)
	var movement := MovementPredictor.new(player, TileMapState.new(null))
	var projectiles := ProjectileSystem.new(player, content, func() -> int: return int(clock["now"]))
	projectiles.latency_ms = reported_rtt
	var client_hits := {}
	movement.slow_probe = func(position: Vector2, size: int, seq: int) -> int:
		var slow_ms := projectiles.slowing_hit_ms(position, size, seq)
		if slow_ms > 0:
			for id in projectiles._slow_hits:
				if not client_hits.has(id):
					client_hits[id] = seq
		return slow_ms
	var server := Server.new()
	server.position = player.position

	var result := {"corrections": 0.0, "over6": 0.0, "over12": 0.0, "max": 0.0, "sum": 0.0,
		"server_hits": 0.0, "matched": 0.0, "false_alarms": 0.0, "misses": 0.0, "dseq": 0.0,
		"bias": 0.0, "big_start": 0.0, "big_end": 0.0}
	var shots: Array = []
	var frame_ms := 1000.0 / frame_hz
	var now := 0.0
	var next_tick := 0.0
	var next_frame := 0.0
	var next_shot := 500.0
	var next_turn := 0.0
	var input := Vector2.RIGHT
	var shot_id := 0
	var end := seconds * 1000.0

	while now < end:
		now = minf(next_tick, next_frame)
		clock["now"] = now
		if next_tick <= next_frame:
			_server_tick(server, up, down, shots, now, rewind)
			if now >= next_shot:
				shot_id += 1
				shots.append(_aim(server, shot_id, now))
				next_shot = now + shot_gap_ms * (0.6 + _rng.randf() * 0.8)
			next_tick += TICK_MS
			continue

		for packet in down.receive(now):
			match packet["kind"]:
				"state":
					player.effects = [SLOWED] if packet["slowed"] else []
				"load":
					projectiles.apply_load({"bullets": [packet["wire"]]})
				"unload":
					projectiles.apply_unload({"bullets": packet["ids"]})
				"ack":
					var before := movement.corrections
					movement.apply_position_ack({"seq": packet["seq"], "posX": packet["x"],
						"posY": packet["y"], "slowedMs": packet["slowedMs"]})
					if movement.corrections != before:
						_count_correction(result, movement.last_correction_px, server.transitions, now)
		if now >= next_turn:
			input = _turn()
			next_turn = now + 300.0 + _rng.randf() * 600.0
		# RealmState.advance order: smoothing, prediction (which probes), then the shots.
		player.decay_smoothing(frame_ms / 1000.0)
		for move in movement.predict(frame_ms / 1000.0, input):
			up.send(now, {"seq": move["seq"], "vx": move["vx"], "vy": move["vy"]})
		projectiles.advance(frame_ms / 1000.0)
		next_frame += frame_ms

	for id in server.hits:
		result["server_hits"] += 1
		if client_hits.has(id):
			result["matched"] += 1
			var delta := float(client_hits[id]) - float(server.hits[id])
			result["dseq"] += absf(delta)
			result["bias"] += delta
		else:
			result["misses"] += 1
	for id in client_hits:
		if not server.hits.has(id):
			result["false_alarms"] += 1
	return result


func _count_correction(result: Dictionary, px: float, transitions: Array, now: float) -> void:
	result["corrections"] += 1
	result["sum"] += px
	result["max"] = maxf(result["max"], px)
	if px <= 6.0:
		return
	result["over6"] += 1
	if px > 12.0:
		result["over12"] += 1
	var last = null
	for transition in transitions:
		if transition[0] <= now:
			last = transition
	if last != null:
		result["big_start" if last[1] else "big_end"] += 1


func _server_tick(server: Server, up: Link, down: Link, shots: Array, now: float, rewind: float) -> void:
	for move in up.receive(now):
		if int(move["seq"]) > server.last_processed:
			server.queue.append(move)

	# processBulletHit: the shots as the last tick's advance left them, rewound.
	var centre := server.position + Vector2(GameConstants.PLAYER_SIZE, GameConstants.PLAYER_SIZE) * 0.5
	var reach := (BULLET_SIZE + GameConstants.PLAYER_SIZE) * HIT_RADIUS_FACTOR
	var half := Vector2(BULLET_SIZE, BULLET_SIZE) * 0.5
	var unloads: Array = []
	for shot: Shot in shots:
		if not shot.alive or not shot.loaded:
			continue
		var a := shot.at(now - TICK_MS - rewind - TICK_MS) + half
		var b := shot.at(now - TICK_MS - rewind) + half
		if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_squared_to(centre) < reach * reach:
			shot.alive = false
			unloads.append(shot.id)
			server.hits[shot.id] = server.last_processed
			server.slow_expiry = maxf(server.slow_expiry, now + shot.slow_ms)

	# movePlayer
	while not server.queue.is_empty() and int(server.queue[0]["seq"]) <= server.last_processed:
		server.queue.pop_front()
	if not server.queue.is_empty() and server.guess_to != null:
		if server.guess_ticks <= MAX_GUESS_TICKS and server.position == server.guess_to:
			server.position = server.guess_from
		server.guess_from = null
		server.guess_to = null
		server.guess_ticks = 0
	var processed := 0
	while not server.queue.is_empty() and processed < 32:
		var move: Dictionary = server.queue.pop_front()
		server.velocity = Vector2(move["vx"], move["vy"])
		server.last_processed = int(move["seq"])
		server.step(now)
		processed += 1
	if processed > 0:
		server.last_input_ms = now
	else:
		var moving := server.velocity != Vector2.ZERO
		if moving and server.guess_from == null:
			server.guess_from = server.position
		server.step(now)
		if moving:
			server.guess_to = server.position
			server.guess_ticks += 1

	# tickRealmBullets: shots past their life go.
	for index in range(shots.size() - 1, -1, -1):
		var shot: Shot = shots[index]
		if now - shot.spawn_ms > SHOT_LIFE_MS:
			if shot.alive and shot.loaded:
				unloads.append(shot.id)
			shots.remove_at(index)

	# enqueueGameData
	server.tick += 1
	var slowed := server.slowed(now)
	if slowed != server.sent_slowed:
		server.sent_slowed = slowed
		server.transitions.append([now, slowed])
		down.send(now, {"kind": "state", "slowed": slowed})
	if server.tick % 2 == 0:
		for shot: Shot in shots:
			if not shot.loaded and shot.alive:
				shot.loaded = true
				down.send(now, {"kind": "load", "wire": shot.wire(now)})
	if not unloads.is_empty():
		down.send(now, {"kind": "unload", "ids": unloads})
	var moving_now := server.velocity != Vector2.ZERO
	if (moving_now and server.tick % 2 == 0) or (not moving_now and server.tick % 6 == 0):
		var acked: Vector2 = server.position
		if server.guess_to != null and server.guess_ticks <= MAX_GUESS_TICKS and server.position == server.guess_to:
			acked = server.guess_from
		var slowed_ms := mini(int(server.slow_expiry - server.last_input_ms), 32767) if slowed else 0
		down.send(now, {"kind": "ack", "seq": server.last_processed, "x": acked.x, "y": acked.y,
			"slowedMs": slowed_ms})


## A slowing shot fired at where the player will be, give or take, from a random side.
func _aim(server: Server, id: int, now: float) -> Shot:
	var shot := Shot.new()
	shot.id = id
	shot.spawn_ms = now
	shot.slow_ms = SLOW_DURATIONS[_rng.randi_range(0, SLOW_DURATIONS.size() - 1)]
	var centre := server.position + Vector2(GameConstants.PLAYER_SIZE, GameConstants.PLAYER_SIZE) * 0.5
	var flight_ticks := SPAWN_DISTANCE / BULLET_SPEED
	var tiles_per_second := 4.0 + 5.6 * (SPD / 75.0)
	var pace := tiles_per_second * 32.0 / 64.0 * (0.5 if server.slowed(now) else 1.0)
	var lead := server.velocity.limit_length(1.0) * pace * flight_ticks * _rng.randf()
	var target := centre + lead + Vector2(_rng.randf_range(-18, 18), _rng.randf_range(-18, 18))
	var from := target + Vector2.from_angle(_rng.randf() * TAU) * SPAWN_DISTANCE
	shot.direction = (target - from).normalized()
	shot.origin = from - Vector2(BULLET_SIZE, BULLET_SIZE) * 0.5
	return shot


func _turn() -> Vector2:
	if _rng.randf() < 0.1:
		return Vector2.ZERO
	return Vector2.from_angle(_rng.randi_range(0, 7) * PI / 4.0).round().normalized()
