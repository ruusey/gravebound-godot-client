extends GutTest

## Saying something: the line under the log, and the packets it sends.

var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var actions: ChatActions
var panel: ChatPanel


func before_each():
	var content := GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	actions = ChatActions.new(state, client)
	panel = ChatPanel.new()
	panel.setup(state, actions)
	add_child_autofree(panel)


func _in_game() -> void:
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	state.local.name = "Ruu"
	transport.clear_sent()


func _key(keycode: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _sent() -> Array:
	return transport.sent_packets()


# --- what is sent ------------------------------------------------------------

func test_a_line_is_a_text_packet_under_our_name():
	_in_game()
	assert_true(actions.say("  hello there  "))
	var packets := _sent()
	assert_eq(packets.size(), 1)
	assert_eq(packets[0]["name"], "TextPacket")
	assert_eq(packets[0]["data"], {"from": "Ruu", "to": "Player", "message": "hello there"},
		"trimmed, and addressed the way the web client addresses it")


func test_a_slash_is_a_server_command():
	_in_game()
	assert_true(actions.say("/tp 10 20"))
	var packets := _sent()
	assert_eq(packets[0]["name"], "CommandPacket")
	assert_eq(int(packets[0]["data"]["commandId"]), LoginHandshake.SERVER_COMMAND)
	assert_eq(int(packets[0]["data"]["playerId"]), 9)
	assert_eq(JSON.parse_string(packets[0]["data"]["command"]), {"command": "tp", "args": ["10", "20"]})


func test_a_blank_line_and_a_line_outside_a_realm_send_nothing():
	_in_game()
	assert_false(actions.say("   "))
	client.disconnect_from_server()
	assert_false(actions.say("hello"))
	assert_eq(_sent().size(), 0)
	assert_false(ChatActions.new(state, null).say("hello"), "no client at all")


# --- the line ----------------------------------------------------------------

func test_enter_opens_the_line_and_it_takes_the_keyboard():
	_in_game()
	assert_false(panel.is_typing())
	panel._unhandled_input(_key(KEY_ENTER))
	assert_true(panel.is_typing())
	assert_true(panel._input.visible)
	assert_true(panel._input.has_focus(), "keys go to it, not to the world")


func test_the_line_stays_closed_before_we_are_in_a_realm():
	panel._unhandled_input(_key(KEY_ENTER))
	assert_false(panel.is_typing(), "Enter on the login screen is the form's")
	_in_game()
	panel._unhandled_input(_key(KEY_A))
	assert_false(panel.is_typing(), "only Enter opens it")
	panel._unhandled_input(_key(KEY_ENTER, false))
	assert_false(panel.is_typing(), "on the press, not the release")


func test_submitting_sends_and_closes():
	_in_game()
	panel._unhandled_input(_key(KEY_KP_ENTER))
	panel._input.text = "on my way"
	panel._input.text_submitted.emit("on my way")
	assert_eq(_sent()[0]["name"], "TextPacket")
	assert_eq(_sent()[0]["data"]["message"], "on my way")
	assert_false(panel.is_typing(), "closed after sending")
	assert_eq(panel._input.text, "", "and cleared for next time")


func test_an_empty_enter_just_closes():
	_in_game()
	panel._unhandled_input(_key(KEY_ENTER))
	panel._input.text_submitted.emit("")
	assert_false(panel.is_typing())
	assert_eq(_sent().size(), 0)


func test_escape_discards_and_a_click_on_the_world_closes():
	_in_game()
	panel._unhandled_input(_key(KEY_ENTER))
	panel._input.text = "never mi"
	panel._input._on_gui_input(_key(KEY_ESCAPE))
	assert_false(panel.is_typing())
	assert_eq(panel._input.text, "")
	panel._unhandled_input(_key(KEY_ENTER))
	assert_true(panel.is_typing())
	panel._unhandled_input(_click())
	assert_false(panel.is_typing(), "a click that reached the world, not the line")
	assert_eq(_sent().size(), 0)


func test_losing_focus_closes_the_line():
	_in_game()
	panel._unhandled_input(_key(KEY_ENTER))
	panel._input.release_focus()
	assert_false(panel.is_typing())
	panel._input.close()
	assert_false(panel.is_typing(), "closing a closed line is nothing")


func test_without_actions_a_line_is_still_closed_after_enter():
	var mute := ChatPanel.new()
	mute.setup(state)
	add_child_autofree(mute)
	_in_game()
	mute._unhandled_input(_key(KEY_ENTER))
	mute._input.text_submitted.emit("hello?")
	assert_false(mute.is_typing())
	assert_eq(_sent().size(), 0)
	var bare := ChatPanel.new()
	add_child_autofree(bare)
	bare._unhandled_input(_key(KEY_ENTER))
	assert_false(bare.is_typing(), "no state, no realm to talk in")
