class_name MovementPredictor
extends RefCounted

## Client-side prediction and server reconciliation for the local player.
##
## The server runs a fixed 64Hz tick, so prediction steps at that same fixed
## rate rather than per rendered frame -- that is what keeps the client's
## integration identical to the server's. Each step is sequence-numbered; the
## server acks with the position it produced, and we rewind to it and replay
## every input it has not seen, so a correction never costs the player input
## they already made.

## Divergence beyond this (px) is a visible correction worth counting and
## smoothing. Smaller errors are still adopted -- see apply_position_ack.
const VISIBLE_CORRECTION_PX := 2.0
## Past this the player was moved by something other than walking (teleport,
## realm change): snap outright, with no smoothing to unwind.
const TELEPORT_PX := 64.0
const MAX_INPUT_HISTORY := 256
## Never replay more than this after a stall (window drag, breakpoint).
const MAX_CATCHUP_TICKS := 8.0
## How far (in ticks) the server's view of a slow may sit from ours before it
## counts as a disagreement: the hit lands on the server a tick or two either side
## of the input we saw it on, and an ack can be read before the state packet the
## server sent with it.
const SLOW_MARGIN_TICKS := 3
## The server's slow outlasting a predicted span by this many acked ticks means
## the span ended too early, not that the two are a tick apart.
const SLOW_OVERRUN_TICKS := 3
const OPEN_SPAN := 1 << 62
const INVINCIBLE := 6
const DOWNED := 43
## Negates three hits in four on the server, so a hit under it is not predicted.
const DODGE := 40
const SPAN_FROM := 0
const SPAN_TO := 1
const SPAN_CONFIRMED := 2

var input_seq := 0
var corrections := 0
var last_correction_px := 0.0
var unacked_inputs := 0
## Applied pixels-per-tick as of the last predict(), for the walk cadence:
## the speed the player is really moving at, slow tiles included.
var pace_px := 0.0
## (top-left position, size, seq) -> how long the enemy shot touching the player
## there slows them, in ms, or 0. RealmState points it at the projectile system;
## unset, a slow is only learned from the server's state packet.
var slow_probe: Callable

var _player: LocalPlayer
var _tiles: TileMapState
var _history: Array = []   # [{seq, input: Vector2, position: Vector2}]
var _send_policy := MoveSendPolicy.new()
var _accumulator := 0.0
var _acked_seq := 0
## The input spans the server runs slowed, as [from, to, confirmed]. The server
## slows a player on the tick its shot lands, a round trip before its state
## packet says so, and every input predicted at full speed in between would come
## back as a correction -- the hitch on being slowed. So a slowing shot the client
## sees touching the player opens a span from the next input, for the shot's
## duration, before the server says a word; the state packet then confirms it, or
## a span the server never matched is dropped. The server decides where the
## player is either way: the span only decides what the client expects.
var _slow_spans: Array = []


func _init(player: LocalPlayer, tiles: TileMapState) -> void:
	_player = player
	_tiles = tiles


## Steps prediction at the fixed tick rate and returns the inputs worth
## sending, as [{seq, vx, vy}, ...].
func predict(delta: float, input: Vector2) -> Array:
	var to_send: Array = []
	if not _player.is_present():
		return to_send

	_reconcile_slow_spans()
	_accumulator = minf(_accumulator + delta, GameConstants.TICK_DELTA * MAX_CATCHUP_TICKS)
	while _accumulator >= GameConstants.TICK_DELTA:
		_accumulator -= GameConstants.TICK_DELTA
		input_seq += 1
		var before := _player.position
		var snapshot := _effect_snapshot()
		_player.position = _replay_step(before, input, snapshot, input_seq)
		_player.previous_position = before
		_history.append({"seq": input_seq, "input": input, "position": _player.position,
			"snapshot": snapshot})
		if _history.size() > MAX_INPUT_HISTORY:
			_history.pop_front()
		_probe_slow(input_seq)
		if _send_policy.should_send(input):
			to_send.append({"seq": input_seq, "vx": input.x, "vy": input.y})

	# What is left over is how far this frame sits into the next tick.
	_player.tick_alpha = _accumulator / GameConstants.TICK_DELTA
	unacked_inputs = _history.size()
	_player.moving = input.length() > 0.001
	pace_px = _pace(_player.position, _effect_snapshot(), input_seq + 1) if _player.moving else 0.0
	if _player.moving:
		_player.face_toward(input)
	return to_send


## Whether the next input runs slowed, by the spans: the movement's view of
## SLOWED, which leads the state packet's by a round trip.
func is_slowed() -> bool:
	return _slowed_at(input_seq + 1)


## The movement math shared by the live step and reconciliation replay: clamp to
## a unit vector, then each axis tested from where the tick STARTED, sliding along
## a corner when only the diagonal is blocked.
func _move(position: Vector2, input: Vector2, pace: float) -> Vector2:
	var vector := input
	if vector.length() > 1.0:
		vector = vector.normalized()
	var delta := vector * pace
	var size := GameConstants.PLAYER_SIZE
	var x_blocked := _tiles.blocks(position + Vector2(delta.x, 0.0), size)
	var y_blocked := _tiles.blocks(position + Vector2(0.0, delta.y), size)
	if not x_blocked and not y_blocked and delta.x != 0.0 and delta.y != 0.0 \
			and _tiles.blocks(position + delta, size):
		if absf(delta.x) >= absf(delta.y):
			y_blocked = true
		else:
			x_blocked = true
	return Vector2(position.x if x_blocked else position.x + delta.x,
		position.y if y_blocked else position.y + delta.y)


## One 64Hz movement tick, mirroring RealmManagerServer.applyMovementTick: the
## pace from SPD and the speed effects, the slow-tile divisor, then _move. A
## paralysed player does not move at all.
##
## Input `seq`, live or replayed: SPD, SPEEDY and PARALYZED as they were
## when the input was made (its snapshot), SLOWED from the spans. Replaying at the
## captured speeds rather than the current ones keeps a buff's arrival from rewriting
## every unacked input at once; SLOWED alone is re-read, because the spans are what
## learn, after the fact, which inputs the server really slowed.
func _replay_step(position: Vector2, input: Vector2, snap: Dictionary, seq: int) -> Vector2:
	if input.length_squared() <= 0.000001 or snap.get("paralyzed", false):
		return position
	return _move(position, input, _pace(position, snap, seq))


## Pixels per tick from here, after the per-tile speed multiplier -- the server's
## TileManager.slowSpeedMul, sampled where it samples (1/3 for a full slow, >1 on a
## speed-up tile).
func _pace(position: Vector2, snap: Dictionary, seq: int) -> float:
	var tiles_per_second := 4.0 + 5.6 * (float(snap.get("spd", 15)) / 75.0)
	if snap.get("speedy", false):
		tiles_per_second *= 1.5
	if _slowed_at(seq):
		tiles_per_second *= 0.5
	var pace := tiles_per_second * float(GameConstants.TILE_SIZE) / GameConstants.TICK_RATE
	return pace * _tiles.slow_mul(position, GameConstants.PLAYER_SIZE)


func _slowed_at(seq: int) -> bool:
	for span in _slow_spans:
		if seq >= span[SPAN_FROM] and seq <= span[SPAN_TO]:
			return true
	return false


## A slowing shot touching where input `seq` left the player slows every input
## after it, for as many ticks as the shot's slow lasts -- the inputs the server
## will run while its SLOWED holds.
func _probe_slow(seq: int) -> void:
	if not slow_probe.is_valid():
		return
	if _player.effects.has(INVINCIBLE) or _player.effects.has(DOWNED) or _player.effects.has(DODGE):
		return
	var slow_ms: int = slow_probe.call(_player.position, GameConstants.PLAYER_SIZE, seq)
	if slow_ms > 0:
		_slow_spans.append([seq + 1, seq + roundi(slow_ms * GameConstants.TICK_RATE / 1000.0), false])


## Squares the spans with what the server has said. The state packet's effects are
## the server's as of the newest ack (it sends a change the tick it happens), so:
## slowed there confirms a span the ack has reached, and holds open one the ack has
## run past; not slowed there ends a confirmed span at the ack and drops a predicted
## one the server has passed without slowing (a dodge, a shot it never landed). A
## slow no span accounts for (an ability, an AoE) slows the inputs from the next one
## on, and its unacked inputs come back as corrections as before.
func _reconcile_slow_spans() -> void:
	var server_slowed: bool = _player.effects.has(LocalPlayer.SLOWED)
	var explained := false
	for index in range(_slow_spans.size() - 1, -1, -1):
		var span: Array = _slow_spans[index]
		if server_slowed:
			if _acked_seq >= span[SPAN_FROM]:
				span[SPAN_CONFIRMED] = true
			if span[SPAN_CONFIRMED] and _acked_seq >= span[SPAN_TO] + SLOW_OVERRUN_TICKS:
				span[SPAN_TO] = OPEN_SPAN
			if span[SPAN_TO] >= _acked_seq - SLOW_OVERRUN_TICKS \
					and (span[SPAN_CONFIRMED] or span[SPAN_FROM] <= _acked_seq + SLOW_MARGIN_TICKS):
				explained = true
		elif span[SPAN_CONFIRMED]:
			span[SPAN_TO] = mini(span[SPAN_TO], _acked_seq)
		elif _acked_seq >= span[SPAN_FROM] + SLOW_MARGIN_TICKS:
			span[SPAN_TO] = -1
		if span[SPAN_TO] <= _acked_seq:
			_slow_spans.remove_at(index)
	if server_slowed and not explained:
		_slow_spans.append([input_seq + 1, OPEN_SPAN, true])


## The effect state to record with an input, for accurate replay later. Effects
## and SPD change rarely, so the same immutable snapshot is shared across the
## inputs that saw identical state -- a fresh dict is built only when it changes,
## not 64 times a second. Safe to share: replay reads the snapshot, never mutates it.
var _snapshot_cache: Dictionary = {}

func _effect_snapshot() -> Dictionary:
	var speedy := _player.effects.has(LocalPlayer.SPEEDY)
	var paralyzed := _player.effects.has(LocalPlayer.PARALYZED)
	var spd := float(_player.stats.get("spd", 15))
	if _snapshot_cache.is_empty() or _snapshot_cache["speedy"] != speedy \
			or _snapshot_cache["paralyzed"] != paralyzed or _snapshot_cache["spd"] != spd:
		_snapshot_cache = {"speedy": speedy, "paralyzed": paralyzed, "spd": spd}
	return _snapshot_cache


func apply_position_ack(data: Dictionary) -> void:
	var acked_seq := int(data.get("seq", -1))
	var server_position := Vector2(data.get("posX", 0.0), data.get("posY", 0.0))

	# Drop what the server has seen and keep everything after it -- never
	# look for the exact sequence. The server acks lastProcessedInputSeq at
	# 32Hz, and on a tick no packet reached it, it steps us anyway and then
	# acks the SAME seq again: an ack for an input already dropped is the
	# ordinary case, not a lost history. Treating it as one -- snapping to
	# the server's position and clearing every unacked input -- put the
	# player an RTT's worth of inputs back, and the next real ack was not in
	# the history either. That was a 15px sawtooth on a real connection,
	# invisible on loopback. Both references drop `<= seq` and replay the
	# rest, and so does this.
	# seq is monotonic and history is append-ordered, so the acked inputs are a
	# contiguous prefix: drop it in place instead of allocating a filtered Array
	# and a lambda on every 32Hz ack. Equivalent to keeping every `seq > acked`.
	while not _history.is_empty() and int(_history[0]["seq"]) <= acked_seq:
		_history.pop_front()
	_acked_seq = maxi(_acked_seq, acked_seq)
	_reconcile_slow_spans()

	# Replay from the server's position and adopt the result *always*, even
	# when the error looks negligible. The server re-applies the last input on
	# any tick no packet reached it, so keeping our own prediction because the
	# gap looked small lets it compound.
	var replayed := server_position
	for entry in _history:
		replayed = _replay_step(replayed, entry["input"], entry.get("snapshot", {}), int(entry["seq"]))
		entry["position"] = replayed

	var predicted := _player.position
	var slide_from := _player.previous_position
	var error := predicted.distance_to(replayed)
	_player.position = replayed
	unacked_inputs = _history.size()
	if error > TELEPORT_PX:
		# Settled on the new place by the assignment: nothing to slide from.
		pass
	else:
		# Carried along with the position, so the correction is the render
		# offset's to unwind and not something the frame slides across.
		_player.previous_position = slide_from + (replayed - predicted)
	if error <= VISIBLE_CORRECTION_PX:
		return

	corrections += 1
	last_correction_px = error
	# A teleport has nothing to unwind visually; smaller jumps ease back.
	_player.set_smoothing(Vector2.ZERO if error > TELEPORT_PX else predicted - replayed)


## Drops every unacked input. A realm change is not a mispredict: there is
## nothing to replay onto a map we have not been sent yet, and replaying
## across the boundary would only fight the spawn position that follows.
func clear_pending() -> void:
	_history.clear()
	_slow_spans.clear()
	unacked_inputs = 0


func pending_input_count() -> int:
	return _history.size()
