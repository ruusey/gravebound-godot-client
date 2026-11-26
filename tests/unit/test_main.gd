extends GutTest

## Top-level wiring: config -> content -> transport -> state -> rendering.

const MainScript := preload("res://scripts/app/main.gd")

var main: Node
var transport: FakeTransport


func _build(config: ClientConfig) -> Node:
	var node := Node.new()
	node.set_script(MainScript)
	node.config = config
	add_child_autofree(node)
	return node


func _config(overrides := {}) -> ClientConfig:
	var config := ClientConfig.new()
	config.data_root = ProjectSettings.globalize_path("res://tests/fixtures/datadir")
	config.autoconnect = false
	for key in overrides:
		config.set(key, overrides[key])
	return config


func _login(player_id := 99) -> void:
	main.client.connection.transport = transport
	main.session.begin("a@b.c", "pw", "char-1")
	transport.become_connected()
	main.client._process(0.0)
	transport.deliver(WireHelper.login_response(player_id, 2, Vector2(320, 640)))
	main.client._process(0.0)


func before_each():
	transport = FakeTransport.new()
	main = _build(_config())


# --- construction ----------------------------------------------------------

func test_builds_the_whole_stack():
	assert_not_null(main.client)
	assert_not_null(main.state)
	assert_not_null(main.game_data)
	assert_not_null(main._world)
	assert_not_null(main._camera)
	assert_not_null(main.session)
	assert_not_null(main.input)
	assert_not_null(main.screens.hud)
	assert_not_null(main.screens.login)
	assert_same(main.screens.overlay.content, main.game_data, "the loot previews draw item art off it")


func test_the_loading_screen_has_lifted_once_the_content_is_in():
	# Off disk the load finishes inside _ready, so the cover is never seen.
	assert_true(main.game_data.ready)
	main.screens.loading._process(0.0)
	assert_false(main.screens.loading.visible)
	assert_eq(main.screens.loading.layer, 25, "over the login screen")


func test_loads_content_from_the_configured_root():
	assert_eq(main.game_data.tiles.size(), 13)
	assert_true(main.state.tiles.blocks(Vector2.ZERO, 28) == false, "the state has content wired for collision")
	assert_eq(main.game_data.items.size(), 15)


func test_the_bag_is_wired_to_the_session():
	assert_not_null(main.screens.inventory)
	assert_eq(main.screens.inventory.state, main.state)
	assert_eq(main.screens.inventory.actions, main.inventory_actions)
	assert_eq(main.inventory_actions.client, main.client)
	assert_eq(main.inventory_input.panel, main.screens.inventory)
	assert_true(main.input.mouse_captured.is_valid(), "a click on the bag is not a shot")


func test_the_bag_and_the_bar_are_up_once_we_are_in_a_realm():
	# The goldens draw each panel on its own; this is the wiring through Main,
	# which is what a player actually sees -- and once did not.
	assert_false(main.screens.inventory.visible, "hidden from the first frame, not the first process")
	assert_false(main.screens.abilities.visible)
	await wait_process_frames(1)
	assert_false(main.screens.inventory.visible, "not on the login screen")
	_login(5)
	await wait_process_frames(2)
	assert_true(main.screens.inventory.visible)
	assert_true(main.screens.abilities.visible)
	assert_false(main.screens.skills.visible, "the sheet waits to be asked for")


func test_the_network_is_stepped_by_main_before_prediction_and_the_camera():
	# An ack reconciled AFTER the camera was placed drew the sprite off the
	# camera's centre for a frame, on every correction. Main drives the
	# client's frame itself, first, and the engine no longer does.
	assert_false(main.client.is_processing(), "the engine does not step the client")
	_login(5)
	var polled := transport.poll_count
	main._process(0.008)
	assert_eq(transport.poll_count, polled + 1, "Main's frame does, once")
	assert_eq(main._camera.position, main.state.local.render_centre(),
		"and the camera is on the player at the end of the same frame")


func test_lag_in_the_chat_steps_the_delay_line_and_l_no_longer_does():
	assert_true(main.client.connection.transport is LagTransport, "always there, at no delay")
	# Signed in through a delay line of its own over the fake, as the client's is.
	var line := LagTransport.new(transport, 0.0, 0.0)
	main.client.connection.transport = line
	main.session.begin("a@b.c", "pw", "char-1")
	transport.become_connected()
	main.client._process(0.0)
	transport.deliver(WireHelper.login_response(5, 2, Vector2(320, 640)))
	main.client._process(0.0)
	assert_true(main.client.is_in_game())
	assert_false(line.delaying())
	var key := InputEventKey.new()
	key.keycode = KEY_L
	key.physical_keycode = KEY_L
	key.pressed = true
	main._unhandled_input(key)
	assert_eq(line.one_way_ms, 0.0, "L is the quest log's now")
	main.chat_actions.say("/lag")
	assert_eq(line.one_way_ms, 50.0)
	main.chat_actions.say("/lag")
	assert_eq(line.one_way_ms, 100.0)
	assert_eq(main.state.chat.lines[-1]["message"], "Lag +100 ms one way")
	main.chat_actions.say("/lag 120")
	assert_eq([line.one_way_ms, line.jitter_ms], [120.0, 4.0])
	main.chat_actions.say("/lag 0")
	assert_eq([line.one_way_ms, line.jitter_ms], [0.0, 0.0])


func test_the_screenshot_key_also_traces_the_next_frames():
	_login(5)
	assert_false(main.trace.active())
	var key := InputEventKey.new()
	key.keycode = KEY_QUOTELEFT
	key.pressed = true
	main._unhandled_input(key)
	assert_true(main.trace.active(), "the trace runs whether or not a frame could be read back")
	main._process(0.008)
	main._process(0.008)
	assert_true(main.trace.active(), "two frames in, still counting")
	# The frame's last look, before it is drawn: the camera is on the player.
	main._on_pre_draw()
	assert_almost_eq(main.trace.off_centre, 0.0, 0.5, "the sprite is the camera's centre")


func test_no_screen_owns_the_mouse_before_login():
	assert_false(main.screens.captures_mouse())


func test_the_chat_line_is_wired_to_every_polled_key():
	assert_eq(main.screens.chat.actions, main.chat_actions)
	assert_eq(main.chat_actions.client, main.client)
	assert_false(main.screens.captures_keyboard(), "closed until Enter")
	for ticker in [main.input, main.portals, main.inventory_input, main.ability_input]:
		assert_true(ticker.keyboard_captured.is_valid())
		assert_false(ticker.keyboard_captured.call())
	_login(5)
	main.screens.chat._input.open()
	assert_true(main.screens.captures_keyboard())
	assert_true(main.input.keyboard_captured.call(), "the same answer, through the wiring")


func test_hud_is_wired_to_the_client_state_and_renderer():
	assert_eq(main.screens.hud.client, main.client)
	assert_eq(main.screens.hud.state, main.state)
	assert_eq(main.screens.hud.renderer, main._world)


func test_data_service_points_at_the_configured_host():
	assert_eq(main._data_service.base_url, "http://127.0.0.1:8080")
	var deployed := _build(_config({"host": "grave-bound.com", "data_port": 80}))
	assert_eq(deployed._data_service.base_url, "http://grave-bound.com",
		"port 80 is omitted so the deployed setup keeps producing a plain host")
	deployed.free()


func test_missing_content_is_surfaced_on_the_login_screen():
	var broken := _build(_config({"data_root": "/no/such/place"}))
	assert_gt(broken.game_data.errors.size(), 0)
	assert_string_contains(broken.screens.login._status.text, "Content warnings")


func test_credentials_are_prefilled_from_config():
	var prefilled := _build(_config({"email": "me@example.com", "password": "pw"}))
	assert_eq(prefilled.screens.login._form.email.text, "me@example.com")


func test_autoconnect_skips_the_character_picker():
	var auto := _build(_config({
		"autoconnect": true, "email": "me@example.com",
		"password": "pw", "character_uuid": "uuid-9", "host": "127.0.0.1",
	}))
	assert_eq(auto.session.credentials.get("character_uuid", ""), "uuid-9",
		"a fully specified config connects without the data service")
	auto.client.disconnect_from_server()


func test_autoconnect_is_skipped_without_a_character():
	var manual := _build(_config({"autoconnect": true, "email": "me@example.com"}))
	assert_eq(manual.session.credentials, {}, "no character uuid means the picker is still needed")


# --- session flow ----------------------------------------------------------

func test_connecting_sends_the_login_command():
	main.client.connection.transport = transport
	main.session.begin("a@b.c", "pw", "char-1")
	transport.become_connected()
	main.client._process(0.0)
	var sent := transport.sent_packets()
	assert_eq(sent[0]["name"], "CommandPacket")
	assert_eq(JSON.parse_string(sent[0]["data"]["command"])["characterUuid"], "char-1")


func test_connection_failure_is_shown_on_the_login_screen():
	main.session._on_connection_failed("refused")
	assert_string_contains(main.screens.login._status.text, "Could not reach")


func test_login_success_places_the_player_and_hides_the_form():
	_login(1234)
	assert_eq(main.state.local.id, 1234)
	assert_eq(main.state.local.class_id, 2)
	assert_eq(main.state.local.position, Vector2(320, 640))
	assert_eq(main._camera.position, main.state.local.centre())
	assert_false(main.screens.login.visible)
	# Nothing of the sign-in screen keeps working behind the game.
	var backdrop: LoginBackdrop = main.screens.login._backdrop
	assert_false(backdrop.is_processing(), "the torches stop")
	assert_eq(backdrop.field.count, 0, "and their fire is dropped")
	main.screens.login.visible = true
	assert_true(backdrop.is_processing(), "back at the sign-in screen, they burn again")


func test_login_failure_brings_the_form_back():
	main.screens.login.visible = false
	main.session._on_login_failed("nope")
	assert_true(main.screens.login.visible)
	assert_string_contains(main.screens.login._status.text, "nope")


func test_packets_are_forwarded_into_the_realm_state():
	_login(1)
	transport.deliver(WireHelper.frame("LoadMapPacket", {
		"realmId": 5, "mapId": 1, "mapWidth": 32, "mapHeight": 32,
		"tiles": [WireHelper.tile(1, 0, 2, 3)],
	}))
	main.client._process(0.0)
	assert_eq(main.state.tiles.realm_id, 5)
	assert_eq(main.state.tiles.layers[0][Vector2i(2, 3)], 1)


func test_disconnect_clears_the_world_and_restores_the_form():
	_login(1)
	main.state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	main.session._on_disconnected("server went away")
	assert_eq(main.state.entities.players.size(), 0)
	assert_eq(main.state.local.id, 0)
	assert_true(main.screens.login.visible)
	assert_string_contains(main.screens.login._status.text, "server went away")


# --- per-frame loop --------------------------------------------------------

func test_no_input_is_sent_before_entering_the_game():
	main._process(1.0)
	assert_eq(transport.sent.size(), 0)


func test_held_input_is_predicted_and_sent_every_tick():
	_login(7)
	transport.clear_sent()
	Input.action_press("move_right")
	main._process(RealmState.TICK_DELTA * 3.0)
	Input.action_release("move_right")
	var sent := transport.sent_packets()
	assert_eq(sent.size(), 3, "one PlayerMovePacket per 64Hz tick while moving")
	assert_eq(sent[0]["name"], "PlayerMovePacket")
	assert_false(sent[0]["data"].has("entityId"), "v0.9.0 dropped the leading entity id")
	assert_eq(sent[0]["data"]["seq"], 1, "the sequence the ack is matched against")
	assert_almost_eq(sent[0]["data"]["vx"], 1.0, 0.001)
	assert_gt(main.state.local.position.x, 0.0, "the player actually moved")


func test_idle_input_is_not_spammed_at_64hz():
	_login(7)
	transport.clear_sent()
	# The predictor clamps a single frame to 8 ticks, so 16 ticks needs two
	# frames -- which is also what a real client does.
	main._process(RealmState.TICK_DELTA * 8.0)
	main._process(RealmState.TICK_DELTA * 8.0)
	var sent := transport.sent_packets()
	assert_eq(sent.size(), 1, "16 idle ticks collapse to a single keepalive")


func test_camera_follows_the_predicted_position():
	_login(7)
	main.state.local.position = Vector2(500, 500)
	main._process(0.0)
	var expected := Vector2(500, 500) + Vector2(RealmState.PLAYER_SIZE, RealmState.PLAYER_SIZE) * 0.5
	assert_eq(main._camera.position, expected, "the camera centres on the sprite, not its top-left")


# --- hotkeys ---------------------------------------------------------------

func _press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	main._unhandled_input(event)


func test_f2_toggles_the_collision_overlay():
	assert_false(main._world.show_collision)
	_press(KEY_F2)
	assert_true(main._world.show_collision)
	_press(KEY_F2)
	assert_false(main._world.show_collision)


func test_f1_dumps_the_packet_mix():
	main.client.stats.packet_counts = {"LoadPacket": 2}
	_press(KEY_F1)
	pass_test("printing the packet mix does not disturb the session")


func test_escape_opens_the_options_and_leave_game_disconnects():
	_press(KEY_ESCAPE)
	assert_false(main.screens.options.shown, "escape before login does nothing")
	assert_eq(transport.disconnect_count, 0)
	_login(1)
	_press(KEY_ESCAPE)
	assert_true(main.screens.options.shown, "in a realm, the menu -- not a disconnect")
	assert_eq(main.client.state, GraveBoundClient.State.IN_GAME)
	_press(KEY_ESCAPE)
	assert_false(main.screens.options.shown, "and escape again puts it away")
	_press(KEY_ESCAPE)
	main.screens.options.leave_button.pressed.emit()
	assert_eq(main.client.state, GraveBoundClient.State.CLOSED, "Leave game is what escape used to do")
	assert_false(main.screens.options.shown)


func test_main_keeps_no_settings_file_under_test():
	assert_eq(main.state.settings.path, "", "a test's config keeps nothing, so a player's choices never leak in")
	assert_eq(ClientConfig.from_command_line().settings_path, GameSettings.DEFAULT_PATH, "the real client keeps them")


func test_key_releases_and_echoes_are_ignored():
	var released := InputEventKey.new()
	released.keycode = KEY_F2
	released.pressed = false
	main._unhandled_input(released)

	var echoed := InputEventKey.new()
	echoed.keycode = KEY_F2
	echoed.pressed = true
	echoed.echo = true
	main._unhandled_input(echoed)

	assert_false(main._world.show_collision, "only fresh key presses toggle")


func test_non_key_events_are_ignored():
	main._unhandled_input(InputEventMouseButton.new())
	pass_test("mouse events fall through")


func test_config_falls_back_to_the_command_line():
	var node := Node.new()
	node.set_script(MainScript)
	add_child_autofree(node)
	assert_not_null(node.config, "a main with no injected config reads the command line")
	node.client.disconnect_from_server()


func test_a_death_raises_the_death_screen():
	# The wiring, not the handler: without this connection nothing in the
	# shipped app ever shows the screen, and every test of the screen itself
	# still passes because they wire the signal by hand.
	main.state.local.id = 7
	main.state.local.name = "Ruu"
	main.session._on_packet("PlayerDeathPacket", {"playerId": 7})
	assert_true(main.screens.death.visible)
	assert_string_contains(main.screens.death._detail.text, "Ruu")


func test_a_death_returns_to_a_picker_with_nothing_stale_in_it():
	# The server deletes the character as it kills it, so the list the picker
	# is holding names something that no longer exists.
	main.screens.login._stage.picker.show_characters([{"characterUuid": "dead-one"}])
	main.screens.death.fell("Ruu")
	assert_true(main.screens.death.visible)

	main.screens.death._button.pressed.emit()
	assert_false(main.screens.death.visible, "the button dismisses it")
	assert_eq(main.screens.login._stage.picker.alive_count(), 0, "and the stale list goes with it")
	assert_true(main.screens.login.visible)


func test_quit_on_the_death_screen_goes_back_to_signing_in():
	main.screens.login._stage.picker.show_characters([{"characterUuid": "dead-one"}])
	main.screens.death.fell("Ruu")
	main.screens.death._quit.pressed.emit()
	assert_false(main.screens.death.visible)
	assert_true(main.screens.login.visible)
	assert_eq(main.screens.login._stage.picker.alive_count(), 0)
	assert_eq(main.screens.login._status.text, "Signed out.")


func test_a_refused_command_lands_in_the_chat_as_the_web_client_shows_it():
	_login()
	transport.deliver(WireHelper.frame("CommandPacket", {
		"playerId": 99, "commandId": LoginHandshake.SERVER_ERROR,
		"command": JSON.stringify({"message": "Admin mode is OFF - type /admin to re-enable"}),
	}))
	main._process(0.016)
	var lines: Array = main.state.chat.lines
	assert_gt(lines.size(), 0, "the refusal is a chat line")
	var last: Dictionary = lines[-1]
	assert_true(ChatLog.is_system(last))
	assert_eq(last["message"], "Error: Admin mode is OFF - type /admin to re-enable")


# --- 2.5D view ---------------------------------------------------------------

func test_the_25d_option_swaps_the_views_both_ways():
	assert_null(main._view_3d, "flat by default")
	main.state.settings.set_on("view_25d", true)
	assert_not_null(main._view_3d)
	assert_false(main._world.visible)
	assert_false(main._lighting.visible)
	main.state.settings.set_on("view_25d", false)
	assert_null(main._view_3d)
	assert_true(main._world.visible)
	assert_true(main._world.is_processing())
	assert_true(main._lighting.is_processing())
	assert_true(main.screens.overlay.is_processing())
	assert_false(main.screens.overlay.project_3d, "names pinned through the 2D camera again")


func test_leaving_the_25d_view_hands_aim_back_to_the_flat_world():
	main.state.settings.set_on("view_25d", true)
	main.input.view_yaw = 1.2
	main.state.settings.set_on("view_25d", false)
	assert_eq(main.input.view_yaw, 0.0, "WASD is screen-aligned again")
	assert_null(main.input.world_mouse.call())
	assert_null(main.caster.world_mouse.call())
	assert_true(main.state.tiles.cleared, "the flat ground is drawn again whole")


func test_shift_wheel_lowers_the_camera_and_the_plain_wheel_still_tilts():
	main.state.settings.set_on("view_25d", true)
	var view: WorldView3D = main._view_3d
	var pitch := view._pitch
	view._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, true))
	assert_almost_eq(view._descent_goal, WorldView3D.DESCENT_STEP, 0.0001)
	assert_eq(view._pitch, pitch, "shift+wheel leaves the tilt alone")
	view._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP, true))
	view._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP, true))
	assert_eq(view._descent_goal, 0.0, "never above the sky view")
	view._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN, false))
	assert_lt(view._pitch, pitch)


func test_the_lowest_camera_sits_at_eye_height_and_still_aims():
	main.state.settings.set_on("view_25d", true)
	var view: WorldView3D = main._view_3d
	view._descent_goal = 1.0
	view._descent = 1.0
	view._follow_camera(Vector2(320.0, 320.0), 0.016)
	assert_eq(view._camera.projection, Camera3D.PROJECTION_PERSPECTIVE)
	assert_almost_eq(view._camera.position.y, WorldView3D.EYE_HEIGHT, 0.01)
	assert_true(view._bullets_upright)
	assert_true(main.screens.overlay.exact, "tags placed exactly in perspective")
	# The cursor's corner is above the horizon there: it aims along its direction.
	assert_not_null(view.get_ground_point())


func test_a_low_camera_still_shows_damage_numbers():
	_login()
	main.state.settings.set_on("view_25d", true)
	var view: WorldView3D = main._view_3d
	view._descent_goal = 1.0
	view._descent = 1.0
	var ahead: Vector2 = main.state.local.render_centre() + Vector2(0.0, -200.0)
	main.state.apply_packet("TextEffectPacket", {"textEffectId": 0, "entityType": 1,
		"targetEntityId": 0, "text": "42", "posX": ahead.x, "posY": ahead.y})
	var behind: Vector2 = main.state.local.render_centre() + Vector2(0.0, 200.0)
	main.state.apply_packet("TextEffectPacket", {"textEffectId": 0, "entityType": 1,
		"targetEntityId": 0, "text": "7", "posX": behind.x, "posY": behind.y})
	view._process(0.016)
	assert_eq(main.screens.overlay.texts, 1, "the hit ahead shows; the one behind the camera doesn't")


func test_looking_into_the_sun_fills_the_sprites():
	_login()
	main.state.settings.set_on("lighting", true)
	main.state.settings.set_on("view_25d", true)
	var view: WorldView3D = main._view_3d
	view._process(0.016)
	assert_eq(view._fill.light_energy, 0.0, "the sun behind the camera needs no fill")
	view._yaw += PI
	view._process(0.016)
	assert_gt(view._fill.light_energy, 0.0, "facing into it, the sprites are filled")


func test_leaving_the_25d_view_low_brings_the_tags_back():
	main.state.settings.set_on("view_25d", true)
	main._view_3d._descent_goal = 1.0
	main._view_3d._descent = 1.0
	main._view_3d._follow_camera(Vector2(320.0, 320.0), 0.016)
	main.state.settings.set_on("view_25d", false)
	assert_false(main.screens.overlay.exact)


static func _wheel(button: MouseButton, shift: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.shift_pressed = shift
	return event


func test_the_3d_flag_ticks_the_option():
	var flagged := _build(_config({"enable_3d": true}))
	assert_true(flagged.state.settings.is_on("view_25d"))
	assert_not_null(flagged._view_3d)
