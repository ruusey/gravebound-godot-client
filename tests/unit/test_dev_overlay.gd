extends GutTest

## /dev, /debug and /clear: answered by the client, never sent, and the
## compact readout /dev brings up.

var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var actions: ChatActions
var dev: DevOverlay
var hud: DebugHud


func before_each():
	state = RealmState.new(null, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	dev = DevOverlay.new()
	dev.setup(client)
	add_child_autofree(dev)
	hud = DebugHud.new()
	hud.setup(client, state)
	add_child_autofree(hud)
	actions = ChatActions.new(state, client)
	actions.commands = ClientCommands.new(state, dev, hud)


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


func test_dev_toggles_the_readout_says_so_and_sends_nothing():
	_in_game()
	assert_true(dev.shown, "on by default, as on the web")
	assert_true(actions.say("/dev"))
	assert_false(dev.shown)
	assert_eq(transport.sent_packets(), [], "a client command never goes on the wire")
	var said: Dictionary = state.chat.lines[-1]
	assert_eq(said["from"], "SYSTEM")
	assert_eq(said["message"], "Dev overlay OFF (FPS / ping / jitter / res / draw)")
	actions.say("/DEV")
	assert_true(dev.shown, "any case, as the web lower-cases it")
	assert_string_contains(state.chat.lines[-1]["message"], "ON")


func test_debug_brings_back_the_diagnostics_and_clear_empties_the_log():
	_in_game()
	assert_false(hud.shown, "off by default")
	actions.say("/debug")
	assert_true(hud.shown)
	assert_eq(state.chat.lines[-1]["message"], "Diagnostics ON")
	actions.say("/clear")
	assert_eq(state.chat.lines.size(), 0)
	assert_eq(transport.sent_packets(), [])


func test_any_other_command_still_goes_to_the_server():
	_in_game()
	assert_true(actions.say("/tp Ruu"))
	var sent := transport.sent_packets()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["name"], "CommandPacket")
	assert_true(dev.shown, "left as it was")
	assert_false(ClientCommands.new(state, dev, hud).run("/"), "a bare slash is not ours")


func test_the_readout_shows_only_in_a_realm_and_only_when_asked():
	dev.shown = true
	dev._process(1.0)
	assert_false(dev.visible, "not at the sign-in screen")
	_in_game()
	dev.shown = false
	dev._process(1.0)
	assert_false(dev.visible)
	assert_eq(dev._text.text, "", "and builds nothing while off")
	dev.shown = true
	dev._process(1.0)
	assert_true(dev.visible)
	assert_string_contains(dev._text.text, "FPS [color=")
	assert_string_contains(dev._text.text, "DRAW [color=")


func test_the_line_and_the_webs_thresholds():
	assert_eq(DevOverlay.line(60.4, 12, 3, Vector2i(2560, 1440), 2.0, 212),
		"FPS [color=#66ff66]60[/color]  |  PING [color=#66ff66]12ms[/color]  |  JITTER 3ms"
		+ "  |  RES 2560x1440 @2x  |  DRAW [color=#66ff66]212[/color]")
	assert_eq(DevOverlay.fps_colour(55.0), "#66ff66")
	assert_eq(DevOverlay.fps_colour(54.9), "#ffff66")
	assert_eq(DevOverlay.fps_colour(30.0), "#ffff66")
	assert_eq(DevOverlay.fps_colour(29.9), "#ff6666")
	assert_eq(DevOverlay.ping_colour(49), "#66ff66")
	assert_eq(DevOverlay.ping_colour(50), "#ffff66")
	assert_eq(DevOverlay.ping_colour(119), "#ffff66")
	assert_eq(DevOverlay.ping_colour(120), "#ff6666")
	assert_eq(DevOverlay.draw_colour(599), "#66ff66")
	assert_eq(DevOverlay.draw_colour(600), "#ffff66")
	assert_eq(DevOverlay.draw_colour(1500), "#ff6666")


func test_the_left_column_starts_at_the_top_and_moves_under_the_diagnostics():
	var party := PartyPanel.new()
	party.setup(state, null, null, hud)
	add_child_autofree(party)
	assert_eq(party.top(), 8.0, "the diagnostics are off: the top of the screen")
	hud.shown = true
	hud._process(1.0)
	await wait_process_frames(2)
	assert_gt(hud.bottom(), 100.0, "the diagnostics run a good way down")
	assert_eq(party.top(), hud.bottom() + 10.0, "just under them")
	hud.shown = false
	hud._process(1.0)
	assert_eq(hud.bottom(), 0.0)
	assert_eq(party.top(), 8.0, "and back up when they go")
