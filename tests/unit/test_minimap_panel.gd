extends GutTest

## The realm from above, top right: shown once a map lands, zoomed by the
## wheel, a dot named under the cursor and teleported to on a click.

var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var panel: MinimapPanel
var now := 10_000


func before_each():
	now = 10_000
	state = RealmState.new(null, func() -> int: return now)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	panel = MinimapPanel.new()
	panel.setup(state, ChatActions.new(state, client))
	add_child_autofree(panel)


func _in_game() -> void:
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(1, 0, Vector2(640, 480)))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	state.local.name = "Ruu"
	transport.clear_sent()


## A 40x30 map with the player mid-map and two others, one untouchable.
func _in_realm() -> void:
	_in_game()
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 1, "mapWidth": 40, "mapHeight": 30,
		"tiles": [WireHelper.tile(1, 0, 5, 5)]})
	state.apply_packet("GlobalPlayerPositionPacket", {"players": [
		{"playerId": 1, "name": "Ruu", "x": 640.0, "y": 480.0, "teleportable": true},
		{"playerId": 2, "name": "Mingau", "x": 160.0, "y": 200.0, "teleportable": true},
		{"playerId": 3, "name": "Ghost", "x": 900.0, "y": 700.0, "teleportable": false}]})
	panel._process(0.0)


func _mouse(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	panel._on_gui_input(motion)
	panel._process(0.0)


func _button(index: MouseButton) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = index
	press.pressed = true
	panel._on_gui_input(press)


func _sent() -> Array:
	return transport.sent_packets()


# --- when it shows -----------------------------------------------------------

func test_hidden_until_there_is_a_map_to_show():
	panel.visible = true
	panel._process(0.0)
	assert_false(panel.visible, "no player")
	_in_game()
	panel._process(0.0)
	assert_false(panel.visible, "a player but no map yet")
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapWidth": 40, "mapHeight": 30, "tiles": []})
	panel._process(0.0)
	assert_true(panel.visible)


func test_m_hides_it_and_shows_it_again():
	_in_realm()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	panel._unhandled_input(key)
	panel._process(0.0)
	assert_false(panel.visible)
	panel._unhandled_input(key)
	panel._process(0.0)
	assert_true(panel.visible)


func test_does_nothing_without_a_state():
	var bare := MinimapPanel.new()
	add_child_autofree(bare)
	bare.visible = true
	bare._process(0.0)
	assert_false(bare.visible)


# --- the window --------------------------------------------------------------

func test_a_small_map_is_shown_whole_and_a_large_one_at_sixty_four_tiles():
	_in_realm()
	assert_eq(panel.zoom, 1.0)
	assert_eq(panel._canvas.window, Rect2(0, 0, 40, 30))
	state.apply_packet("LoadMapPacket", {"realmId": 2, "mapId": 2, "mapWidth": 320, "mapHeight": 320,
		"tiles": []})
	panel._process(0.0)
	assert_eq(panel.zoom, 0.2, "a new map opens at its own zoom")
	assert_eq(panel._canvas.window.size, Vector2(64, 64))
	assert_eq(panel._canvas.window.position, Vector2(0, 0), "clamped: the player is near the corner")


func test_the_wheel_zooms_in_and_out():
	_in_realm()
	_button(MOUSE_BUTTON_WHEEL_UP)
	assert_almost_eq(panel.zoom, 0.95, 0.0001, "in")
	_button(MOUSE_BUTTON_WHEEL_DOWN)
	_button(MOUSE_BUTTON_WHEEL_DOWN)
	assert_eq(panel.zoom, 1.0, "out, and no further than the whole map")


func test_the_window_follows_the_player():
	_in_realm()
	panel.zoom = 0.5
	panel._process(0.0)
	assert_eq(panel._canvas.window, Rect2(10, 7.5, 20, 15), "centred on tile (20, 15)")


# --- hover and click ---------------------------------------------------------

func test_the_dot_under_the_cursor_is_named():
	_in_realm()
	# Mingau at tile (5, 6.25) on a 200px panel showing 40x30 tiles.
	var at := Vector2(5.0 / 40.0 * 200.0, 6.25 / 30.0 * 200.0)
	_mouse(at + Vector2(3, 3))
	assert_eq(panel.hovered.get("name", ""), "Mingau")
	_mouse(at + Vector2(9, 0))
	assert_eq(panel.hovered, {}, "nine pixels off is not on it")


func test_our_own_dot_is_never_a_destination():
	_in_realm()
	_mouse(Vector2(100, 100))
	assert_eq(panel.hovered, {})


func test_a_click_on_a_dot_teleports_to_them():
	_in_realm()
	_mouse(Vector2(5.0 / 40.0 * 200.0, 6.25 / 30.0 * 200.0))
	_button(MOUSE_BUTTON_LEFT)
	var packets := _sent()
	assert_eq(packets.size(), 1)
	assert_eq(packets[0]["name"], "CommandPacket")
	assert_string_contains(packets[0]["data"]["command"], "tp")
	assert_string_contains(packets[0]["data"]["command"], "Mingau")


func test_a_player_the_server_would_refuse_is_not_asked_for():
	_in_realm()
	# Ghost at tile (28.125, 21.875).
	_mouse(Vector2(28.125 / 40.0 * 200.0, 21.875 / 30.0 * 200.0))
	assert_eq(panel.hovered.get("name", ""), "Ghost")
	assert_false(panel.teleport_to_hovered())
	assert_eq(_sent().size(), 0)
	_mouse(Vector2(150, 20))
	assert_false(panel.teleport_to_hovered(), "and nothing under the cursor sends nothing")


func test_a_click_needs_someone_to_send_it():
	_in_realm()
	panel.chat = null
	_mouse(Vector2(5.0 / 40.0 * 200.0, 6.25 / 30.0 * 200.0))
	assert_false(panel.teleport_to_hovered())


func test_leaving_the_panel_forgets_the_hover():
	_in_realm()
	_mouse(Vector2(5.0 / 40.0 * 200.0, 6.25 / 30.0 * 200.0))
	assert_eq(panel.hovered.get("name", ""), "Mingau")
	panel._root.mouse_exited.emit()
	panel._process(0.0)
	assert_eq(panel.hovered, {})


func test_captures_the_mouse_only_over_itself_while_shown():
	_in_realm()
	assert_false(panel.captures_mouse(), "the real cursor is not over the top-right corner")
	panel.shown = false
	panel._process(0.0)
	assert_false(panel.captures_mouse())


# --- the picture -------------------------------------------------------------

func test_draws_the_others_as_dots_and_the_events_as_pins():
	_in_realm()
	state.apply_packet("TextPacket", {"from": "EVENT_MARKER", "to": "Ruu", "message": "ADD|7|99|400|600|Wyrm"})
	_mouse(Vector2(5.0 / 40.0 * 200.0, 6.25 / 30.0 * 200.0))
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	assert_eq(panel._canvas.draw_stats, {"dots": 2, "pins": 1, "arrows": 0, "hop": false})


func test_a_pin_out_of_the_window_is_an_arrow_at_the_edge():
	_in_realm()
	panel.zoom = 0.2
	state.apply_packet("TextPacket", {"from": "EVENT_MARKER", "to": "Ruu", "message": "ADD|7|99|64|64|Wyrm"})
	panel._process(0.0)
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	assert_eq(panel._canvas.draw_stats, {"dots": 0, "pins": 0, "arrows": 1, "hop": false},
		"everyone else is out of it too")


func test_the_texture_is_only_uploaded_again_when_the_picture_changed():
	_in_realm()
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	var texture: ImageTexture = panel._canvas._texture
	assert_not_null(texture)
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	assert_same(panel._canvas._texture, texture, "same map, same texture")
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 1, "mapWidth": 40, "mapHeight": 30,
		"tiles": [WireHelper.tile(1, 0, 6, 6)]})
	panel._process(0.0)
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	assert_same(panel._canvas._texture, texture, "more of the same map updates it in place")
	assert_eq(panel._canvas._painted, state.minimap.version)
	state.apply_packet("LoadMapPacket", {"realmId": 3, "mapId": 3, "mapWidth": 8, "mapHeight": 8, "tiles": []})
	panel._process(0.0)
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	assert_ne(panel._canvas._texture, texture, "a map of another size is a new texture")


func test_an_empty_canvas_draws_nothing():
	var bare := MinimapCanvas.new()
	add_child_autofree(bare)
	bare.draw_stats = {"dots": 9, "pins": 9, "arrows": 9, "hop": true}
	bare.queue_redraw()
	await wait_process_frames(2)
	assert_eq(bare.draw_stats, {"dots": 0, "pins": 0, "arrows": 0, "hop": false})


# --- hop mode ----------------------------------------------------------------

func _hop_on() -> void:
	state.apply_packet("TextPacket", {"from": "SYSTEM", "to": "Ruu", "message": "Hop mode: ON"})


func test_in_hop_mode_a_click_anywhere_hops_to_the_world_point_under_it():
	_in_realm()
	_hop_on()
	# The whole 40x30 map on 200px: (100, 50) is tile (20, 7.5), 32px a tile.
	_mouse(Vector2(100, 50))
	_button(MOUSE_BUTTON_LEFT)
	var packets := _sent()
	assert_eq(packets.size(), 1)
	assert_eq(packets[0]["name"], "CommandPacket")
	# The command travels as the server's JSON message.
	assert_eq(JSON.parse_string(packets[0]["data"]["command"]), {"command": "hop", "args": ["640", "240"]},
		"world pixels, whole")


func test_in_hop_mode_a_click_on_a_dot_hops_rather_than_teleports():
	_in_realm()
	_hop_on()
	_mouse(Vector2(5.0 / 40.0 * 200.0, 6.25 / 30.0 * 200.0))
	assert_eq(panel.hovered.get("name", ""), "Mingau", "still named under the cursor")
	_button(MOUSE_BUTTON_LEFT)
	assert_eq(_sent().size(), 1)
	assert_eq(JSON.parse_string(_sent()[0]["data"]["command"]), {"command": "hop", "args": ["160", "200"]},
		"to the spot, not /tp to him")


func test_a_hop_needs_someone_to_send_it():
	_in_realm()
	panel.chat = null
	assert_false(panel.hop_to(Vector2(100, 100)))


func test_hop_mode_wears_a_badge_and_loses_it_when_turned_off():
	_in_realm()
	_hop_on()
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	assert_true(panel._canvas.draw_stats["hop"])
	state.apply_packet("TextPacket", {"from": "SYSTEM", "to": "Ruu", "message": "Hop mode: OFF"})
	panel._canvas.queue_redraw()
	await wait_process_frames(2)
	assert_false(panel._canvas.draw_stats["hop"])
