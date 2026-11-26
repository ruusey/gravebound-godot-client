extends GutTest

## Dying: the one packet that ends a session.

var session: SessionController
var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var login: LoginScreen
var screen: DeathScreen
var fell_as := ""


func before_each():
	fell_as = ""
	state = RealmState.new(null)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)

	login = LoginScreen.new()
	login.data_service = DataService.new()
	add_child_autofree(login)
	screen = DeathScreen.new()
	add_child_autofree(screen)

	session = SessionController.new(client, state, login, ClientConfig.new())
	session.died.connect(func(who: String, _grave: Dictionary) -> void: fell_as = who)
	session.died.connect(screen.fell)

	_sign_in()
	state.local.name = "Ruu"


## A whole session from connect to in-game, as the fake transport sees it.
func _sign_in() -> void:
	session.begin("a", "b", "c")
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 0, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	transport.clear_sent()


func _dies(player_id: int) -> void:
	client.packet_received.emit("PlayerDeathPacket", {"playerId": player_id})


func _acks() -> int:
	var count := 0
	for packet in transport.sent_packets():
		if packet["name"] == "DeathAckPacket":
			count += 1
	return count


func test_our_own_death_is_acknowledged():
	# The ack is what ends the session: the server disconnects in response to
	# it, not on its own.
	_dies(state.local.id)
	assert_eq(_acks(), 1)


func test_another_players_death_is_not_ours_to_answer():
	_dies(state.local.id + 1)
	assert_eq(_acks(), 0)
	assert_eq(fell_as, "")


func test_a_repeated_death_is_acknowledged_once():
	# It can arrive twice; the native client logs the duplicate and drops it.
	_dies(state.local.id)
	_dies(state.local.id)
	_dies(state.local.id)
	assert_eq(_acks(), 1)


func test_the_connection_is_left_for_the_server_to_close():
	# Closing from here would race the ack out of the socket -- on the web
	# path a send is queued, not written, and the close wipes the queue.
	var closes_before := transport.disconnect_count
	_dies(state.local.id)
	assert_eq(transport.disconnect_count, closes_before, "nothing closed from our side")
	assert_eq(client.state, GraveBoundClient.State.ENDED,
		"but not playing either: the socket stays up only to carry the ack")


func test_nothing_is_played_after_the_ack():
	# Not closing the socket is not the same as carrying on. Both references
	# stop the loop at the ack, and the heartbeat is the one that matters: it
	# is what keeps the server from reaping a session whose close was lost.
	var aim := Node2D.new()
	add_child_autofree(aim)
	var input := PlayerInput.new(state, client, aim)
	var portals := PortalInput.new(state, client, GameData.new())
	state.local.stats = {"spd": 20}
	_dies(state.local.id)
	transport.clear_sent()

	Input.action_press("move_right")
	for i in 60:
		input.tick(RealmState.TICK_DELTA)
	Input.action_release("move_right")
	portals.to_nexus()
	for i in 4:
		client._process(2.0)

	assert_eq(transport.sent_packets().size(), 0,
		"no movement, no shots, no portal, no heartbeat")
	assert_eq(state.local.position, Vector2.ZERO, "and we have not walked anywhere")


func test_the_screen_names_the_character_that_fell():
	_dies(state.local.id)
	assert_eq(fell_as, "Ruu")
	assert_true(screen.visible)
	assert_string_contains(screen._detail.text, "Ruu")


func test_the_screen_reads_out_the_grave():
	client.packet_received.emit("PlayerDeathPacket", {"playerId": state.local.id, "grave": [
		{"name": "Ruu", "classId": 0, "level": 17, "maxedStats": 6, "killedBy": "Dragon King",
			"killingBlow": 412, "diedAt": 0}]})
	assert_string_contains(screen._detail.text, "level 17")
	assert_true(screen._record.visible)
	assert_string_contains(screen._record.text, "6/8 maxed")
	assert_string_contains(screen._record.text, "Killed by Dragon King")
	assert_string_contains(screen._record.text, "Final blow: 412 damage")


func test_no_grave_no_record():
	_dies(state.local.id)
	assert_false(screen._record.visible)


func test_a_nameless_character_still_gets_a_line():
	state.local.name = ""
	_dies(state.local.id)
	assert_string_contains(screen._detail.text, "Your character")


func test_the_disconnect_that_follows_does_not_bury_the_reason():
	# The server closes the socket in answer to the ack. Raising the login
	# screen over the death screen would replace "you died" with
	# "Disconnected: closed by remote".
	_dies(state.local.id)
	client.disconnected.emit("closed by remote")
	assert_false(login.visible, "the death screen keeps the screen")
	assert_true(screen.visible)


func test_an_ordinary_disconnect_still_says_so():
	client.disconnected.emit("connection reset")
	assert_true(login.visible)
	assert_string_contains(login._status.text, "connection reset")


func test_the_world_is_torn_down_either_way():
	state.apply_packet("LoadPacket", {"enemies": [WireHelper.enemy(3, 1, Vector2.ZERO)]})
	_dies(state.local.id)
	client.disconnected.emit("closed by remote")
	assert_eq(state.entities.enemies.size(), 0)
	assert_eq(state.local.id, 0, "and we are nobody until the next login")


## A teammate and a passer-by in view, and the party the two of us are in.
func _among_company() -> void:
	state.apply_packet("LoadPacket", {"players": [
		WireHelper.player(41, "Ally", Vector2.ZERO), WireHelper.player(42, "Passerby", Vector2.ZERO)]})
	state.apply_packet("PartyUpdatePacket", {"partyId": 7, "leaderId": 41,
		"members": [{"playerId": 41}, {"playerId": state.local.id}]})


func test_choosing_again_before_the_hangup_leaves_no_phantoms():
	# The server hangs up in answer to the ack, but the picker can beat that, and the
	# next session never unloads players or a party it did not send itself.
	_among_company()
	_dies(state.local.id)
	_sign_in()
	assert_true(state.entities.players.is_empty(), "no one from the last realm in the nearby list")
	assert_false(state.party.in_party(), "and no party the new character never joined")


func test_a_new_character_never_inherits_the_last_ones_world():
	_among_company()
	_sign_in()
	assert_true(state.entities.players.is_empty())
	assert_false(state.party.in_party())


func test_the_session_being_replaced_is_hung_up_quietly():
	_dies(state.local.id)
	var closes_before := transport.disconnect_count
	_sign_in()
	assert_gt(transport.disconnect_count, closes_before, "the old socket is ours to close now")
	assert_false(login._status.text.contains("Disconnected"), "a close we asked for is not news")
	assert_true(client.is_in_game(), "and the new session still comes up")


func test_the_next_session_can_die_again():
	_dies(state.local.id)
	assert_eq(_acks(), 1)
	client.disconnected.emit("closed by remote")
	_sign_in()
	_dies(state.local.id)
	assert_eq(_acks(), 1, "the once-only latch is per session, not per process")


func test_the_picker_forgets_a_character_that_no_longer_exists():
	# The server deletes it against the data service, so the list we hold is
	# stale -- offering it again means picking a uuid login will reject.
	login._stage.picker.show_characters([{"characterUuid": "dead-one"}])
	# Shown first, or "hidden afterwards" is a state they were already in and
	# the assertions below pass against a function that does nothing.
	login._stage.picker.visible = true
	login._stage.play_button.visible = true
	login.forget_characters("Your character was lost.")
	assert_false(login._stage.picker.visible)
	assert_eq(login._stage.picker.alive_count(), 0)
	assert_eq(login._stage.picker.list.item_count, 0)
	assert_false(login._stage.play_button.visible)
	assert_true(login.visible)


func test_dismissing_the_screen_asks_for_somewhere_to_go():
	var asked := [false]
	screen.dismissed.connect(func() -> void: asked[0] = true)
	screen.fell("Ruu")
	screen._button.pressed.emit()
	assert_false(screen.visible)
	assert_true(asked[0], "nothing else knows the player is ready to move on")


func test_the_death_screen_sits_above_the_transition_cover():
	# Dying during a realm change is reachable, and the cover must not be what
	# the player is left looking at.
	var cover := TransitionScreen.new()
	add_child_autofree(cover)
	assert_gt(screen.layer, cover.layer)
