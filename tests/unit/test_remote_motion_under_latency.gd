extends GutTest

## How evenly a remote entity is drawn under latency, by the numbers.
##
## The server's own send rules, run over a walker that turns a corner
## every second and a half: a moving peer re-sent every four ticks and on
## any change of velocity, an enemy only when it drifts four pixels off
## its last sent velocity, changes velocity or has been silent 48 ticks.
## Each sample reaches the client after a one-way delay with a uniform
## jitter, in order, as LagTransport delivers bytes -- modelled here as an
## arrival time, since nothing below the packet matters to the sampler --
## and lands on the 60Hz frame that first sees it, stamped with that
## frame's clock, which is how GraveBoundClient.tick stamps a packet.
##
## The drawn motion is then judged by the live movement test's rule: a
## frame that barely moved is a stall, and a walk is uneven with more than
## one stall in twenty, a spread over half the mean, or a jump past five
## means. A 16Hz staircase reads as three stalls in four; a freeze and a
## jump reads as a max of thirty means. Both failed here before the
## sampler searched the whole buffer and walked on through the silence.

const TICK_MS := 1000.0 / GameConstants.TICK_RATE
const FRAME_MS := 1000.0 / 60.0
const SPEED := 2.0            # px/tick: a middling SPD stat
const TURN_EVERY := 96        # ticks between corners
const WARMUP_FRAMES := 40     # the delay line filling
const FRAMES := 240
const MAX_STALLS := FRAMES / 20
const MAX_SPREAD := 0.5
const MAX_JUMP := 5.0

## The server's dead-reckoning thresholds (EntityMotionState) and cadences.
const RESEND_TICKS := 4
const STALE_TICKS := 48
const VELOCITY_THRESHOLD_SQ := 0.25
const POSITION_THRESHOLD_SQ := 16.0

var registry: EntityRegistry


func before_each():
	registry = EntityRegistry.new()


func test_a_peer_walks_evenly_at_every_lag():
	for lag in [0.0, 50.0, 100.0, 200.0]:
		_judge("peer at %3.0f ms" % lag, GameConstants.ENTITY_PLAYER, lag, 4.0)


func test_an_enemy_walks_evenly_at_every_lag():
	for lag in [0.0, 50.0, 100.0, 200.0]:
		_judge("enemy at %3.0f ms" % lag, GameConstants.ENTITY_ENEMY, lag, 4.0)


func test_an_enemy_walks_evenly_under_heavy_jitter():
	_judge("enemy at 100 ms, jitter 30", GameConstants.ENTITY_ENEMY, 100.0, 30.0)


func _judge(label: String, kind: int, lag_ms: float, jitter_ms: float) -> void:
	var measured := _drawn(_stream(kind, lag_ms, jitter_ms), kind)
	print("%-28s %s" % [label, MotionTrace.summary(measured)])
	assert_true(measured["stalls"] <= MAX_STALLS,
		"%s: %d frames barely moved" % [label, measured["stalls"]])
	assert_true(measured["sd"] <= MAX_SPREAD * measured["mean"],
		"%s: spread %.2f over half the mean %.2f" % [label, measured["sd"], measured["mean"]])
	assert_true(measured["max"] <= MAX_JUMP * measured["mean"],
		"%s: a jump of %.2f past five means %.2f" % [label, measured["max"], measured["mean"]])


## What the server sends, as [arrival_ms, position, velocity] in arrival
## order: the walker steps every tick, movement is looked at every other
## tick (OBJECT_MOVE_BROADCAST_DIVISOR), and a sample goes out only when
## the rules say so.
func _stream(kind: int, lag_ms: float, jitter_ms: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var position := Vector2.ZERO
	var velocity := Vector2(SPEED, 0)
	var sent := {}
	var out := []
	var last_arrival := 0.0
	for tick in 640:
		position += velocity
		if tick > 0 and tick % TURN_EVERY == 0:
			velocity = Vector2(-velocity.y, velocity.x)
		if tick % 2 != 0 or not _server_sends(kind, position, velocity, sent, tick):
			continue
		sent = {"pos": position, "vel": velocity, "tick": tick}
		last_arrival = maxf(last_arrival,
			tick * TICK_MS + lag_ms + rng.randf_range(-jitter_ms, jitter_ms))
		out.append([last_arrival, position, velocity])
	return out


func _server_sends(kind: int, position: Vector2, velocity: Vector2, sent: Dictionary, tick: int) -> bool:
	if sent.is_empty():
		return true
	var since: int = tick - sent["tick"]
	if kind == GameConstants.ENTITY_PLAYER and velocity != Vector2.ZERO and since >= RESEND_TICKS:
		return true
	if since >= STALE_TICKS and not (velocity == Vector2.ZERO and sent["vel"] == Vector2.ZERO
			and position == sent["pos"]):
		return true
	if (velocity - sent["vel"]).length_squared() > VELOCITY_THRESHOLD_SQ:
		return true
	var predicted: Vector2 = sent["pos"] + sent["vel"] * float(since)
	return (position - predicted).length_squared() > POSITION_THRESHOLD_SQ


## The frames, as MotionTrace.measure takes them.
func _drawn(stream: Array, kind: int) -> Dictionary:
	var entity := registry.upsert({}, 1, kind)
	var frames := []
	var next := 0
	var last := Vector2.INF
	for frame in WARMUP_FRAMES + FRAMES:
		var now := int(frame * FRAME_MS)
		while next < stream.size() and stream[next][0] <= now:
			EntitySnapshots.push(entity, stream[next][1], stream[next][2], now)
			next += 1
		var drawn := EntitySnapshots.render_position(entity, now)
		if frame >= WARMUP_FRAMES:
			frames.append([FRAME_MS, 1, drawn.distance_to(last)])
		last = drawn
	return MotionTrace.measure(frames, 0)
