extends GutTest

## Client-side prediction and server reconciliation.
##
## The numbers here are the server's: tilesPerSec = 4.0 + 5.6 * (spd / 75),
## converted to pixels per 64Hz tick by * 32 / 64.

const TICK := RealmState.TICK_DELTA

var state: RealmState
var data: GameData


func before_each():
	data = GameData.new()
	data.library.tiles = {
		1: {"tileId": 1, "data": {"hasCollision": 0, "slows": 0}},
		2: {"tileId": 2, "data": {"hasCollision": 1, "slows": 0}},
		3: {"tileId": 3, "data": {"hasCollision": 0, "slows": 1}},
	}
	state = RealmState.new(data)
	state.local.id = 1
	state.local.stats = {"spd": 75}


## Where the player stands with its hitbox flush against the near edge of
## tile column (or row) 1. The hitbox is centred on the sprite, as the
## server's TileManager has it: inset by half the slack on each side.
func _flush() -> float:
	var hit := floorf(GameConstants.PLAYER_SIZE * GameConstants.COLLISION_HITBOX_SCALE)
	return GameConstants.TILE_SIZE - (GameConstants.PLAYER_SIZE - hit) * 0.5 - hit


func _step_px() -> float:
	var tiles_per_second := 4.0 + 5.6 * (float(state.local.stats["spd"]) / 75.0)
	return tiles_per_second * float(RealmState.TILE_SIZE) / GameConstants.TICK_RATE


func test_no_prediction_before_login():
	state.local.id = 0
	assert_eq(state.movement.predict(1.0, Vector2.RIGHT), [], "nothing is predicted or sent before we have a player id")


func test_one_input_per_fixed_tick():
	var sent := state.movement.predict(TICK * 3.0, Vector2.RIGHT)
	assert_eq(sent.size(), 3, "three 64Hz steps in three tick-lengths")
	assert_eq(sent[0]["seq"], 1)
	assert_eq(sent[2]["seq"], 3, "sequence numbers increase monotonically")


func test_sub_tick_frames_accumulate():
	assert_eq(state.movement.predict(TICK * 0.4, Vector2.RIGHT).size(), 0, "not a whole tick yet")
	assert_eq(state.movement.predict(TICK * 0.4, Vector2.RIGHT).size(), 0)
	assert_eq(state.movement.predict(TICK * 0.4, Vector2.RIGHT).size(), 1, "the remainder carries over")


func test_long_stall_does_not_replay_hundreds_of_ticks():
	var sent := state.movement.predict(10.0, Vector2.RIGHT)
	assert_eq(sent.size(), 8, "the accumulator is clamped to 8 ticks")


func test_movement_uses_the_server_speed_formula():
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x, _step_px(), 0.0001)
	assert_almost_eq(state.local.position.x, 4.8, 0.0001, "spd 75 is 9.6 tiles/sec, i.e. 4.8 px/tick")


func test_speed_scales_with_the_spd_stat():
	state.local.stats = {"spd": 0}
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x, 2.0, 0.0001, "spd 0 is 4 tiles/sec, i.e. 2 px/tick")


func test_missing_spd_stat_falls_back_to_a_default():
	state.local.stats = {}
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_gt(state.local.position.x, 0.0, "movement still works before the first UpdatePacket")


func test_zero_input_does_not_move():
	state.movement.predict(TICK * 5.0, Vector2.ZERO)
	assert_eq(state.local.position, Vector2.ZERO)
	assert_false(state.local.moving)


func test_diagonal_input_is_clamped_to_unit_length():
	# An unnormalised (1,1) would move 41% too fast; the server clamps it, so we must too.
	state.movement.predict(TICK, Vector2(1, 1))
	assert_almost_eq(state.local.position.length(), _step_px(), 0.0001)


func test_diagonal_has_the_same_total_step_as_cardinal():
	state.movement.predict(TICK, Vector2(1, 1).normalized())
	var diagonal := state.local.position.length()
	state.local.position = Vector2.ZERO
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(diagonal, state.local.position.x, 0.0001)


func test_facing_follows_the_dominant_axis():
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_eq(state.local.facing, "side")
	state.movement.predict(TICK, Vector2.DOWN)
	assert_eq(state.local.facing, "front", "+y is toward the camera")
	state.movement.predict(TICK, Vector2.UP)
	assert_eq(state.local.facing, "back")
	assert_true(state.local.moving)


func test_collision_blocks_movement_into_a_wall():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(2, GameConstants.COLLISION_LAYER, 1, 0)]})
	state.local.position = Vector2(_flush(), 0.0)  # hitbox ends exactly at the tile edge
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_eq(state.local.position.x, _flush(), "blocked on x")


func test_collision_resolves_axes_independently():
	# Sliding along a wall: x is blocked, y still moves.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(2, GameConstants.COLLISION_LAYER, 1, 0)]})
	state.local.position = Vector2(_flush(), 0.0)
	state.movement.predict(TICK, Vector2(1, 1).normalized())
	assert_eq(state.local.position.x, _flush(), "x stays blocked")
	assert_gt(state.local.position.y, 0.0, "y still advances")


func test_a_wall_taller_than_two_cells_blocks_down_its_whole_face():
	# 8x24 art covers its own cell and two below; all three are solid, as the server's
	# TileModel.solidRows has it, so nobody stands on the lower face.
	data.library.tiles[4] = {"tileId": 4, "spriteSize": 8, "spriteHeight": 24,
		"data": {"hasCollision": 1, "isWall": 1}}
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(4, GameConstants.COLLISION_LAYER, 1, 0)]})
	var size := GameConstants.TILE_SIZE
	for row in 3:
		assert_true(state.tiles.blocks(Vector2(size, row * size), size), "row %d of the wall" % row)
	assert_false(state.tiles.blocks(Vector2(size, 3 * size), size), "the floor in front of it")


func test_an_8x16_wall_blocks_only_its_own_cell():
	data.library.tiles[5] = {"tileId": 5, "spriteSize": 8, "spriteHeight": 16,
		"data": {"hasCollision": 1, "isWall": 1}}
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(5, GameConstants.COLLISION_LAYER, 1, 0)]})
	var size := GameConstants.TILE_SIZE
	assert_true(state.tiles.blocks(Vector2(size, 0), size))
	assert_false(state.tiles.blocks(Vector2(size, size), size), "its front face is walked in front of")


func test_walking_north_stops_at_the_foot_of_a_tall_wall():
	data.library.tiles[4] = {"tileId": 4, "spriteSize": 8, "spriteHeight": 24,
		"data": {"hasCollision": 1, "isWall": 1}}
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(4, GameConstants.COLLISION_LAYER, 0, 0)]})
	state.local.position = Vector2(0.0, 4.0 * GameConstants.TILE_SIZE)
	state.movement.predict(TICK * 8.0, Vector2.UP)
	var hit := floorf(GameConstants.PLAYER_SIZE * GameConstants.COLLISION_HITBOX_SCALE)
	var box_top := state.local.position.y + (GameConstants.PLAYER_SIZE - hit) * 0.5
	assert_gte(box_top, 3.0 * GameConstants.TILE_SIZE, "held at the bottom of the third row")


func test_non_colliding_tiles_do_not_block():
	# Decoration tiles live in the collision layer with hasCollision = 0.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(1, GameConstants.COLLISION_LAYER, 1, 0)]})
	state.local.position = Vector2(_flush(), 0.0)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_gt(state.local.position.x, _flush(), "hasCollision = 0 is walkable")


func test_tiles_on_other_layers_do_not_block():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(2, 0, 1, 0)]})
	state.local.position = Vector2(_flush(), 0.0)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_gt(state.local.position.x, _flush(), "only the collision layer blocks")


func test_movement_is_unobstructed_without_content():
	# Without tiles.json we cannot reproduce the server's collision, so we
	# predict freely and let reconciliation correct us.
	var bare := RealmState.new(null)
	bare.local.id = 1
	bare.local.stats = {"spd": 75}
	bare.movement.predict(TICK, Vector2.RIGHT)
	assert_gt(bare.local.position.x, 0.0)


func test_slow_tile_divides_speed_by_three():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(3, 0, 0, 0)]})
	state.local.position = Vector2(2, 2)  # feet at (16, 30): inside tile (0,0)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x - 2.0, _step_px() / 3.0, 0.0001)


func test_slow_is_sampled_under_the_feet_on_the_base_layer():
	# feetOnFlaggedTile, which all three clients copy: the horizontal middle
	# and the BOTTOM of the sprite, on the terrain layer. The centre of this
	# player is on dry row 0; its feet are in the water on row 1.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(3, 0, 0, 1),
		WireHelper.tile(1, 0, 0, 0)]})
	state.local.position = Vector2(2, 10)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x - 2.0, _step_px() / 3.0, 0.0001, "the feet decide")
	# The same water on the collision layer is scenery to this test.
	state.apply_packet("LoadMapPacket", {"realmId": 2, "tiles": [WireHelper.tile(3, GameConstants.COLLISION_LAYER, 0, 0),
		WireHelper.tile(1, 0, 0, 0)]})
	state.local.position = Vector2(2, 2)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x - 2.0, _step_px(), 0.0001)


func test_a_corner_blocks_the_smaller_axis_and_slides_along_the_larger():
	# Neither axis alone hits the wall at (1,1); the diagonal does. The
	# server, the web and the native client all give way on the smaller
	# axis (y here, with |dx| == |dy|) rather than cutting the corner. The
	# old X-then-Y resolution moved x and then found y clear too.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(2, GameConstants.COLLISION_LAYER, 1, 1)]})
	var corner := Vector2(_flush(), _flush())
	state.local.position = corner
	state.movement.predict(TICK, Vector2(1, 1).normalized())
	assert_almost_eq(state.local.position.x, corner.x + _step_px() * sqrt(0.5), 0.0001, "slides along x")
	assert_eq(state.local.position.y, corner.y, "y gave way")
	# Mostly downward: now x is the smaller axis and gives way instead.
	state.local.position = corner
	state.movement.predict(TICK, Vector2(0.5, 1.0).normalized())
	assert_eq(state.local.position.x, corner.x, "x gave way")
	assert_almost_eq(state.local.position.y, corner.y + _step_px() / sqrt(1.25), 0.0001, "slides along y")


func test_each_axis_is_tested_from_where_the_tick_started():
	# A wall at (1,0) and a second at (0,1): moving diagonally from the
	# corner between them, x is blocked, y is blocked, nothing moves --
	# whereas testing y from the already-moved x would find y clear.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(2, GameConstants.COLLISION_LAYER, 1, 0),
		WireHelper.tile(2, GameConstants.COLLISION_LAYER, 0, 1)]})
	state.local.position = Vector2(_flush(), _flush())
	state.movement.predict(TICK, Vector2(1, 1).normalized())
	assert_eq(state.local.position, Vector2(_flush(), _flush()))


func test_the_map_edge_and_the_void_block():
	# A 4x4 map with terrain everywhere but cell (2,1), which the stream
	# never sent: a hole. collidesXLimit / collidesYLimit and isVoidTile.
	var tiles := []
	for x in 4:
		for y in 4:
			if not (x == 2 and y == 1):
				tiles.append(WireHelper.tile(1, 0, x, y))
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapWidth": 4, "mapHeight": 4, "tiles": tiles})
	state.local.position = Vector2(1, 50)
	state.movement.predict(TICK, Vector2.LEFT)
	assert_eq(state.local.position.x, 1.0, "the left edge")
	state.local.position = Vector2(97, 50)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_eq(state.local.position.x, 97.0, "the right edge, sprite width included")
	state.local.position = Vector2(50, 97)
	state.movement.predict(TICK, Vector2.DOWN)
	assert_eq(state.local.position.y, 97.0, "the bottom edge")
	state.local.position = Vector2(48, 20)  # centre at 62: the next step puts it in cell 2
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_eq(state.local.position.x, 48.0, "a hole in the world")
	state.local.position = Vector2(48, 60)  # cell (2,2) is terrain
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_gt(state.local.position.x, 48.0)
	# An id-0 tile the stream did send is a hole too.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapWidth": 4, "mapHeight": 4, "tiles": [WireHelper.tile(0, 0, 2, 2)]})
	state.local.position = Vector2(48, 60)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_eq(state.local.position.x, 48.0)


func test_the_speed_effects_the_server_applies():
	state.local.effects = [LocalPlayer.SPEEDY]
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x, _step_px() * 1.5, 0.0001, "SPEEDY is half again")
	state.local.position = Vector2.ZERO
	state.local.effects = []
	state.apply_packet("PlayerPosAckPacket", {"seq": state.movement.input_seq, "posX": 0.0, "posY": 0.0,
		"slowedMs": 1000})
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x, _step_px() * 0.5, 0.0001, "SLOWED is half")
	state.apply_packet("PlayerPosAckPacket", {"seq": state.movement.input_seq, "posX": 0.0, "posY": 0.0})
	state.local.position = Vector2.ZERO
	state.local.effects = [LocalPlayer.PARALYZED]
	var sent := state.movement.predict(TICK, Vector2.RIGHT)
	assert_eq(state.local.position, Vector2.ZERO, "PARALYZED does not move")
	assert_eq(sent.size(), 1, "but the input is still sent and sequenced, as the server acks it")


func test_unknown_tile_id_is_not_solid():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(999, GameConstants.COLLISION_LAYER, 1, 0)]})
	state.local.position = Vector2(_flush(), 0.0)
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_gt(state.local.position.x, _flush())


# --- reconciliation --------------------------------------------------------

func test_first_ack_without_history_snaps_to_the_server():
	state.apply_packet("PlayerPosAckPacket", {"seq": 99, "posX": 500.0, "posY": 600.0})
	assert_eq(state.local.position, Vector2(500, 600))
	assert_eq(state.movement.unacked_inputs, 0)


func test_matching_ack_is_not_a_correction():
	state.movement.predict(TICK * 3.0, Vector2.RIGHT)
	var predicted_at_2: Vector2 = state.movement._history[1]["position"]
	state.apply_packet("PlayerPosAckPacket", {"seq": 2, "posX": predicted_at_2.x, "posY": predicted_at_2.y})
	assert_eq(state.movement.corrections, 0, "agreement is not a correction")
	assert_eq(state.movement.unacked_inputs, 1, "only the unacked input remains")


func test_tiny_divergence_is_tolerated():
	state.movement.predict(TICK, Vector2.RIGHT)
	var predicted: Vector2 = state.movement._history[0]["position"]
	state.apply_packet("PlayerPosAckPacket", {"seq": 1, "posX": predicted.x + 0.1, "posY": predicted.y})
	assert_eq(state.movement.corrections, 0, "float noise under the epsilon is ignored")


func test_real_divergence_corrects_and_replays_unacked_input():
	state.movement.predict(TICK * 3.0, Vector2.RIGHT)
	var before := state.local.position
	# Server says we were held at the origin on input 1 (it saw a wall we didn't).
	state.apply_packet("PlayerPosAckPacket", {"seq": 1, "posX": 0.0, "posY": 0.0})
	assert_eq(state.movement.corrections, 1)
	assert_gt(state.movement.last_correction_px, 0.0)
	assert_eq(state.movement.unacked_inputs, 2, "inputs 2 and 3 are still ours to replay")
	# Replaying two rightward inputs from the origin.
	assert_almost_eq(state.local.position.x, _step_px() * 2.0, 0.0001)
	assert_ne(state.local.position, before)


func test_replay_preserves_later_inputs_exactly():
	state.movement.predict(TICK, Vector2.RIGHT)
	state.movement.predict(TICK, Vector2.DOWN)
	state.apply_packet("PlayerPosAckPacket", {"seq": 1, "posX": 100.0, "posY": 100.0})
	assert_almost_eq(state.local.position.x, 100.0, 0.0001, "the down input did not move x")
	assert_almost_eq(state.local.position.y, 100.0 + _step_px(), 0.0001)


func test_history_is_bounded():
	state.movement.predict(TICK * 8.0, Vector2.RIGHT)
	for i in 60:
		state.movement.predict(TICK * 8.0, Vector2.RIGHT)
	assert_lte(state.movement._history.size(), MovementPredictor.MAX_INPUT_HISTORY)


func test_an_ack_older_than_everything_kept_replays_it_all():
	# The history was bounded away from it, or it is a re-ack: either way the
	# inputs we hold are all still unseen by the server, so they replay from
	# where it says we were. Nothing is thrown away.
	state.movement.predict(TICK * 8.0, Vector2.RIGHT)
	state.apply_packet("PlayerPosAckPacket", {"seq": -5, "posX": 42.0, "posY": 43.0})
	assert_almost_eq(state.local.position.x, 42.0 + _step_px() * 8.0, 0.001)
	assert_almost_eq(state.local.position.y, 43.0, 0.001)
	assert_eq(state.movement._history.size(), 8, "every input kept for the next ack")


func test_a_re_acked_seq_after_an_empty_server_tick_is_one_step_not_a_snap():
	# The server acks lastProcessedInputSeq every other tick; on a tick no
	# packet reached it, it steps us on the last velocity and acks the same
	# seq again, one step further on.
	state.movement.predict(TICK * 4.0, Vector2.RIGHT)
	var at_2: Vector2 = state.movement._history[1]["position"]
	_ack(2, at_2)
	assert_eq(state.movement.unacked_inputs, 2)
	assert_eq(state.movement.corrections, 0)
	var predicted := state.local.position
	_ack(2, at_2 + Vector2(_step_px(), 0.0))
	assert_eq(state.movement.unacked_inputs, 2, "inputs 3 and 4 are still ours: no history wipe")
	assert_eq(state.movement.corrections, 1, "exactly the one-step disagreement")
	assert_almost_eq(state.movement.last_correction_px, _step_px(), 0.001)
	assert_almost_eq(state.local.position.x, predicted.x + _step_px(), 0.001,
		"adopted the server's extra step, replayed on top")
	assert_almost_eq(state.local.render_position().x, state.local.interpolated().x - _step_px(), 0.001,
		"and the whole step, under the cap, is eased by the render offset rather than shown")


func test_pending_input_count_tracks_unacked_history():
	assert_eq(state.movement.pending_input_count(), 0)
	state.movement.predict(TICK * 3.0, Vector2.RIGHT)
	assert_eq(state.movement.pending_input_count(), 3)


# --- reconciliation policy --------------------------------------------------

func _ack(seq: int, position: Vector2) -> void:
	state.apply_packet("PlayerPosAckPacket",
		{"seq": seq, "posX": position.x, "posY": position.y})


func test_a_small_disagreement_is_still_adopted():
	# The server re-applies the last input on any tick no packet reached it,
	# so keeping our own prediction because the gap looked small lets it
	# compound. Adopt the server's answer every time.
	state.advance(RealmState.TICK_DELTA, Vector2.RIGHT, 0.0)
	var seq: int = state.movement.input_seq
	var nudged: Vector2 = state.local.position + Vector2(1.0, 0.0)
	_ack(seq, nudged)
	assert_eq(state.local.position, nudged, "the server's position wins")
	assert_eq(state.movement.corrections, 0, "too small to be worth reporting")
	assert_eq(state.local.smooth_offset, Vector2.ZERO, "nothing to unwind")


func test_a_visible_correction_is_absorbed_into_the_render_offset():
	state.advance(RealmState.TICK_DELTA, Vector2.RIGHT, 0.0)
	var seq: int = state.movement.input_seq
	var predicted: Vector2 = state.local.position
	var drawn_before := state.local.render_position()
	# Bigger than the cap, so part of it shows.
	var jump := LocalPlayer.SMOOTHING_CAP_PX + 4.0
	var server := predicted + Vector2(jump, 0.0)
	_ack(seq, server)

	assert_eq(state.local.position, server, "logical position follows the server")
	assert_eq(state.movement.corrections, 1)
	assert_almost_eq(state.movement.last_correction_px, jump, 0.001)
	assert_ne(state.local.smooth_offset, Vector2.ZERO,
		"the jump is absorbed visually rather than snapped")
	assert_almost_eq(state.local.render_position().x, drawn_before.x + jump - LocalPlayer.SMOOTHING_CAP_PX, 0.001,
		"drawn where it was, plus only what the cap could not hide of the jump")


func test_smoothing_is_capped_and_decays_to_nothing():
	state.advance(RealmState.TICK_DELTA, Vector2.RIGHT, 0.0)
	_ack(state.movement.input_seq, state.local.position + Vector2(40.0, 0.0))
	assert_almost_eq(state.local.smooth_offset.length(), LocalPlayer.SMOOTHING_CAP_PX, 0.001,
		"a large jump is only partly hidden")

	var anchored: Vector2 = state.local.position
	# Half-lives from the cap down to the 0.05px floor, plus a tick to spare.
	var half_lives := log(LocalPlayer.SMOOTHING_CAP_PX / 0.05) / log(2.0)
	for i in ceili(half_lives * LocalPlayer.SMOOTHING_HALF_LIFE / RealmState.TICK_DELTA) + 1:
		state.advance(RealmState.TICK_DELTA, Vector2.ZERO, 0.0)
	assert_eq(state.local.smooth_offset, Vector2.ZERO, "the offset unwinds")
	assert_eq(state.local.position, anchored, "and never moved the real position")


func test_the_frame_is_drawn_between_ticks():
	# Half a tick in: nothing has stepped yet, and there is nothing to slide
	# between, so the sprite is where it was.
	state.movement.predict(TICK * 0.5, Vector2.RIGHT)
	assert_eq(state.local.render_position(), Vector2.ZERO)
	# A whole tick later the predictor stepped once; the frame is halfway
	# into the next tick, so the sprite is halfway along the step.
	state.movement.predict(TICK, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x, _step_px(), 0.001, "prediction itself is the tick")
	assert_almost_eq(state.local.render_position().x, _step_px() * 0.5, 0.001)
	state.movement.predict(TICK * 0.25, Vector2.RIGHT)
	assert_almost_eq(state.local.render_position().x, _step_px() * 0.75, 0.001)
	# The frame that lands exactly on the second tick draws exactly one step,
	# which is where the previous frame was heading: no jump either side.
	state.movement.predict(TICK * 0.25, Vector2.RIGHT)
	assert_almost_eq(state.local.position.x, _step_px() * 2.0, 0.001)
	assert_almost_eq(state.local.render_position().x, _step_px(), 0.001)
	assert_almost_eq(state.local.render_centre().x, _step_px() + GameConstants.PLAYER_SIZE * 0.5, 0.001)


func test_a_long_frame_still_draws_evenly():
	# Two ticks in one frame: the sprite is drawn at the first of them, not
	# at the second, so the next frame does not stall.
	state.movement.predict(TICK * 2.0, Vector2.RIGHT)
	assert_almost_eq(state.local.render_position().x, _step_px(), 0.001)


func test_a_correction_moves_both_ends_of_the_slide():
	state.movement.predict(TICK * 1.5, Vector2.RIGHT)
	var before := state.local.render_position()
	state.movement.apply_position_ack({"seq": 1, "posX": 20.0, "posY": 0.0})
	# The slide is 20px further on; the render offset hides all it can of
	# the jump, and the rest is the honest correction.
	var jump := 20.0 - _step_px()
	var shown := state.local.render_position()
	assert_almost_eq(shown.x, before.x + jump - LocalPlayer.SMOOTHING_CAP_PX, 0.001,
		"a cap's worth of the jump is absorbed by the offset")
	assert_almost_eq(state.local.previous_position.x, jump, 0.001, "the slide's start moved with the position")


func test_a_placed_player_is_drawn_where_it_is_put():
	state.movement.predict(TICK * 1.5, Vector2.RIGHT)
	assert_ne(state.local.previous_position, state.local.position, "mid-slide")
	state.local.position = Vector2(4096.0, 4096.0)
	assert_eq(state.local.render_position(), Vector2(4096.0, 4096.0), "a new place, not a slide to it")
	state.local.position = Vector2(4.0, 4.0)
	assert_eq(state.local.render_position(), Vector2(4.0, 4.0), "however near the old one")
	# A teleport ack settles the same way.
	state.movement.predict(TICK * 1.5, Vector2.RIGHT)
	state.movement.apply_position_ack({"seq": state.movement.input_seq, "posX": 500.0, "posY": 4.0})
	assert_eq(state.local.render_position(), Vector2(500.0, 4.0))


func test_a_teleport_snaps_without_smoothing():
	state.advance(RealmState.TICK_DELTA, Vector2.RIGHT, 0.0)
	var far: Vector2 = state.local.position + Vector2(500.0, 0.0)
	_ack(state.movement.input_seq, far)
	assert_eq(state.local.position, far)
	assert_eq(state.local.smooth_offset, Vector2.ZERO,
		"a teleport is not a walking disagreement; there is nothing to ease")
