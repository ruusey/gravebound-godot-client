extends GutTest

## Which inputs the client runs at half speed: the server's slowedMs forecast on
## each ack, and the slows predicted from a shot seen touching the player before
## the server has said a word.

const TICK := GameConstants.TICK_DELTA
const TICK_MS := 1000.0 / GameConstants.TICK_RATE

var player: LocalPlayer
var movement: MovementPredictor
var probe_hits := {}


func before_each():
	player = LocalPlayer.new()
	player.id = 1
	player.stats = {"spd": 75}
	movement = MovementPredictor.new(player, TileMapState.new(null))
	probe_hits = {}
	movement.slow_probe = func(_position: Vector2, _size: int, seq: int) -> int:
		return probe_hits.get(seq, 0)


func _step_px() -> float:
	return (4.0 + 5.6) * GameConstants.TILE_SIZE / GameConstants.TICK_RATE


func _ack(seq: int, x: float, slowed_ms := 0) -> void:
	movement.apply_position_ack({"seq": seq, "posX": x, "posY": 0.0, "slowedMs": slowed_ms})


## Steps one input and returns how far it moved.
func _step() -> float:
	var before := player.position.x
	movement.predict(TICK, Vector2.RIGHT)
	return player.position.x - before


func test_the_ack_forecast_slows_as_many_inputs_as_its_slowed_ms_covers():
	_ack(0, 0.0, int(TICK_MS * 3) + 1)
	for index in 3:
		assert_almost_eq(_step(), _step_px() * 0.5, 0.0001, "input %d is inside the slow" % (index + 1))
	assert_almost_eq(_step(), _step_px(), 0.0001, "the fourth input is past it")


func test_a_slowed_state_packet_alone_does_not_slow_movement():
	player.effects = [LocalPlayer.SLOWED]
	assert_almost_eq(_step(), _step_px(), 0.0001, "only the ack says which inputs the server slows")


func test_a_slow_ending_on_the_server_frees_the_unacked_inputs():
	_ack(0, 0.0, 1000)
	for index in 4:
		_step()
	_ack(1, _step_px() * 0.5, 0)
	assert_almost_eq(player.position.x, _step_px() * 0.5 + 3 * _step_px(), 0.0001,
		"inputs 2-4 replay at full speed once the server's slow is over")


func test_a_shot_touching_the_player_slows_the_inputs_after_it():
	probe_hits[1] = 1000
	assert_almost_eq(_step(), _step_px(), 0.0001, "the input the shot touched ran before it landed")
	assert_almost_eq(_step(), _step_px() * 0.5, 0.0001, "the next is slowed before the server says so")


func test_a_predicted_slow_the_server_never_landed_is_dropped_past_the_margin():
	probe_hits[1] = 1000
	for index in 8:
		_step()
	_ack(2 + MovementPredictor.SLOW_MARGIN_TICKS - 1, 0.0, 0)
	assert_true(movement.is_slowed(), "within the margin the server may still land it")
	_ack(2 + MovementPredictor.SLOW_MARGIN_TICKS, 0.0, 0)
	assert_false(movement.is_slowed(), "past it, the server's forecast says it never did")


func test_the_server_forecast_outlives_a_predicted_slow_it_has_overtaken():
	probe_hits[1] = 100
	for index in 10:
		_step()
	_ack(2 + MovementPredictor.SLOW_MARGIN_TICKS, 0.0, 1000)
	assert_true(movement.is_slowed(), "the server's own slow ran longer than the shot's")


func test_warded_blocks_the_prediction():
	player.effects = [MovementPredictor.WARDED]
	probe_hits[1] = 1000
	_step()
	assert_false(movement.is_slowed(), "the server drops every debuff under WARDED")


func test_vulnerable_doubles_the_predicted_slow():
	player.effects = [MovementPredictor.VULNERABLE]
	probe_hits[1] = 100
	_step()
	var last_slowed := 1 + roundi(200 * GameConstants.TICK_RATE / 1000.0)
	while movement.input_seq + 1 < last_slowed:
		_step()
	assert_true(movement.is_slowed(), "still inside twice the shot's duration")
	_step()
	assert_false(movement.is_slowed())
