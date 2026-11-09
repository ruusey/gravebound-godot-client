extends GutTest

## Movement and firing driven from real input state.

var input: PlayerInput
var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var aim: Node2D


var now := 1000


func before_each():
	now = 1000
	var content := GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content)

	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)

	aim = Node2D.new()
	add_child_autofree(aim)

	input = PlayerInput.new(state, client, aim, content)
	input.clock = func() -> int: return now

	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 0, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	state.local.inventory.put(0, {"itemId": 100, "damage": {"projectileGroupId": 10}})
	transport.clear_sent()


func after_each():
	_release_mouse()


func _press_mouse() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_mouse() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_a_click_on_the_bag_is_not_a_shot():
	# Main wires this to the panel; here it is simply true, which is the
	# whole of what the gate consults.
	input.mouse_captured = func() -> bool: return true
	_press_mouse()
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 0)
	assert_eq(state.projectiles.bullets.size(), 0)


func test_typing_into_the_chat_line_neither_walks_nor_shoots():
	# Main wires this to the chat line; the web client gates on chatMode.
	input.keyboard_captured = func() -> bool: return true
	Input.action_press("move_right")
	_press_mouse()
	input.tick(RealmState.TICK_DELTA * 2.0)
	Input.action_release("move_right")
	assert_eq(state.local.position.x, 0.0, "the held key is a letter")
	assert_eq(_shots_sent(), 0, "and the click is not a shot")


func test_does_nothing_before_entering_the_game():
	client.disconnect_from_server()
	input.tick(1.0)
	assert_eq(transport.sent.size(), 0)


func test_movement_is_predicted_and_sent():
	Input.action_press("move_right")
	input.tick(RealmState.TICK_DELTA * 2.0)
	Input.action_release("move_right")
	var sent := transport.sent_packets()
	assert_eq(sent.size(), 2)
	assert_eq(sent[0]["name"], "PlayerMovePacket")
	assert_gt(state.local.position.x, 0.0)


func test_bullets_advance_each_tick():
	state.projectiles.bullets[1] = Projectile.from_wire(
		{"id": 1, "angle": 0.0, "magnitude": 5.0, "range": 500.0, "pos": {"x": 0.0, "y": 0.0},
		 "flags": []}, 0)
	input.tick(RealmState.TICK_DELTA)
	assert_gt(state.projectiles.bullets[1]["pos"].y, 0.0)


func test_holding_the_mouse_fires():
	_press_mouse()
	input.tick(RealmState.TICK_DELTA)
	var shots := _shot_packets()
	assert_eq(shots.size(), 1, "one shot on the first frame the button is held")
	assert_eq(shots[0]["data"]["projectileGroupId"], 10)
	assert_eq(state.projectiles.bullets.size(), 1, "and a predicted bullet appears at once")


func test_firing_is_rate_limited():
	_press_mouse()
	input.tick(RealmState.TICK_DELTA)
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 1, "the cooldown suppresses the second frame")


func test_firing_resumes_after_the_cooldown():
	_press_mouse()
	input.tick(RealmState.TICK_DELTA)
	now += int(input.interval() * 1000.0)
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 2)


func test_no_shot_is_sent_without_a_weapon():
	state.local.inventory.clear()
	_press_mouse()
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 0)
	assert_eq(state.projectiles.bullets.size(), 0, "and nothing is predicted either")


func test_releasing_the_mouse_stops_firing():
	_release_mouse()
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 0)


func _shot_packets() -> Array:
	var shots: Array = []
	for packet in transport.sent_packets():
		if packet["name"] == "PlayerShootPacket":
			shots.append(packet)
	return shots


func _shots_sent() -> int:
	return _shot_packets().size()


# --- how fast we are allowed to shoot --------------------------------------

func test_a_stunned_player_does_not_shoot_at_all():
	# The server refuses it, so predicting the bullet would draw a shot that
	# never existed -- and it does not even refresh the last-shot time, so
	# nothing is banked while the stun lasts.
	state.local.effects = [AttackRate.STUNNED]
	_press_mouse()
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 0)
	assert_eq(state.projectiles.bullets.size(), 0, "and nothing is drawn either")


func test_the_trigger_waits_the_rate_it_computed():
	# Asserting the rate in isolation leaves the trigger free to ignore it: a
	# hardcoded quarter second passes every other test in this file.
	state.local.stats = {"dex": 12}      # two a second, so 510ms
	_press_mouse()
	input.tick(RealmState.TICK_DELTA)
	now += 260
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 1, "a quarter second is not enough at this DEX")

	now += int(input.interval() * 1000.0)
	input.tick(RealmState.TICK_DELTA)
	assert_eq(_shots_sent(), 2, "and the rate it computed is")


func test_a_quicker_character_shoots_sooner():
	state.local.stats = {"dex": 12}
	var slow := input.interval()
	state.local.stats = {"dex": 100}
	assert_lt(input.interval(), slow)


func test_berserk_shortens_it_and_dazed_lengthens_it():
	state.local.stats = {"dex": 50}
	var plain := input.interval()
	state.local.effects = [AttackRate.BERSERK]
	assert_lt(input.interval(), plain)
	state.local.effects = [AttackRate.DAZED]
	assert_gt(input.interval(), plain)


func test_an_empty_hand_and_no_stats_still_have_a_rate():
	# Both arrive late: stats come with the first UpdatePacket, and the
	# weapon with the inventory in it.
	state.local.inventory.clear()
	state.local.stats = {}
	assert_almost_eq(input.interval(),
		AttackRate.interval(AttackRate.DEFAULT_DEX, 1.0, []), 0.0001)


func test_the_rate_survives_having_no_content():
	var bare := PlayerInput.new(state, client, aim)
	state.local.stats = {"dex": 50}
	assert_almost_eq(bare.interval(), AttackRate.interval(50, 1.0, []), 0.0001)
