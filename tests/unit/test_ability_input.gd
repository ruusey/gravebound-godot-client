extends GutTest

## The keys and the mouse button that cast.

const ACTIONS := ["ability_1", "ability_2", "ability_3", "toggle_skills"]

var state: RealmState
var content: GameData
var client: GraveBoundClient
var transport: FakeTransport
var caster: AbilityCaster
var skills: SkillsPanel
var input: AbilityInput
var aim: Node2D
var now := 5000


func before_each():
	now = 5000
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return now)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	# A wizard, whose first slot fires a projectile group.
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	state.local.mana = 500
	transport.clear_sent()
	aim = Node2D.new()
	add_child_autofree(aim)
	caster = AbilityCaster.new(state, client, content, aim)
	skills = SkillsPanel.new()
	skills.setup(state, content, client)
	add_child_autofree(skills)
	input = AbilityInput.new(client, caster, skills)


func after_each():
	for action in ACTIONS:
		Input.action_release(action)
	_key(KEY_SHIFT, false)
	_right_mouse(false)


func _key(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _right_mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _casts() -> Array:
	var out: Array = []
	for packet in transport.sent_packets():
		if packet["name"] == "UseAbilityPacket":
			out.append(int(packet["data"]["abilityIndex"]))
	return out


func test_a_digit_typed_into_the_chat_line_is_not_a_cast():
	input.keyboard_captured = func() -> bool: return true
	Input.action_press("ability_1")
	input.tick(0.0)
	assert_eq(transport.sent_packets().size(), 0, "a 1 in the chat line is a digit")
	Input.action_release("ability_1")


func test_the_keys_are_bound():
	for action in ACTIONS:
		assert_true(InputMap.has_action(action), action)


func test_a_digit_casts_its_slot_once_per_press():
	Input.action_press("ability_2")
	input.tick(0.0)
	input.tick(0.0)
	assert_eq(_casts(), [1], "held is not pressed again")


func test_shift_leaves_the_digit_to_the_bag():
	_key(KEY_SHIFT, true)
	Input.action_press("ability_1")
	input.tick(0.0)
	assert_eq(_casts(), [])


func test_the_right_button_is_the_first_slot():
	_right_mouse(true)
	input.tick(0.0)
	input.tick(0.0)
	assert_eq(_casts(), [0], "once per press")
	_right_mouse(false)
	input.tick(0.0)
	now += AbilityCaster.GLOBAL_COOLDOWN_MS + 3000
	_right_mouse(true)
	input.tick(0.0)
	assert_eq(_casts(), [0, 0])


func test_a_right_click_on_a_panel_is_not_a_cast():
	input.mouse_captured = func() -> bool: return true
	_right_mouse(true)
	input.tick(0.0)
	assert_eq(_casts(), [])


func test_k_opens_the_sheet_once_per_press():
	Input.action_press("toggle_skills")
	input.tick(0.0)
	assert_true(skills.shown)
	input.tick(0.0)
	assert_true(skills.shown, "held is not pressed again")


func test_k_outside_a_realm_is_a_letter_in_the_password_field():
	client.stop_playing()
	Input.action_press("toggle_skills")
	input.tick(0.0)
	assert_false(skills.shown)


func test_nothing_casts_outside_a_realm():
	client.stop_playing()
	Input.action_press("ability_1")
	_right_mouse(true)
	input.tick(0.0)
	assert_eq(transport.sent_packets().size(), 0)
