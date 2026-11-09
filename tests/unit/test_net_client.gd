extends GutTest

## GraveBoundClient driven through a fake socket: handshake sequencing, frame
## reassembly across arbitrary read boundaries, and every failure exit.

var client: GraveBoundClient
var transport: FakeTransport
var now := 0


func before_each():
	now = 0
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	client.clock = func() -> int: return now
	watch_signals(client)


func after_each():
	client.free()


func _connect_and_login(player_id := 4242) -> void:
	client.connect_to_server("127.0.0.1", 2222)
	transport.become_connected()
	client._process(0.0)
	client.login("a@b.c", "pw", "char-uuid")
	transport.deliver(WireHelper.login_response(player_id, 2, Vector2(100, 200)))
	client._process(0.0)


# --- connecting ------------------------------------------------------------

func test_connect_opens_the_socket_with_no_delay():
	client.connect_to_server("example.test", 2222)
	assert_eq(transport.last_host, "example.test")
	assert_eq(transport.last_port, 2222)
	assert_true(transport.no_delay_set, "TCP_NODELAY matches the server's own socket setup")
	assert_eq(client.state, GraveBoundClient.State.CONNECTING)


func test_connect_failure_is_reported():
	transport.connect_error = ERR_CANT_CONNECT
	client.connect_to_server("nowhere", 2222)
	assert_signal_emitted(client, "connection_failed")
	assert_eq(client.state, GraveBoundClient.State.CLOSED)


func test_connected_signal_fires_once_the_socket_comes_up():
	client.connect_to_server("h", 1)
	client._process(0.0)
	assert_signal_not_emitted(client, "connected", "still connecting")
	transport.become_connected()
	client._process(0.0)
	assert_signal_emitted(client, "connected")
	assert_eq(client.state, GraveBoundClient.State.AWAITING_LOGIN)


func test_connect_times_out():
	client.connect_to_server("h", 1)
	now = int((GraveBoundClient.LOGIN_TIMEOUT + 1.0) * 1000.0)
	client._process(0.0)
	assert_signal_emitted(client, "disconnected")
	assert_eq(client.state, GraveBoundClient.State.CLOSED)


func test_idle_client_does_nothing():
	client._process(1.0)
	assert_eq(transport.poll_count, 0, "an unconnected client does not touch the socket")


# --- login -----------------------------------------------------------------

func test_login_sends_a_login_command_packet():
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("me@example.com", "secret", "char-1", "tok-1")

	var sent := transport.sent_packets()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["name"], "CommandPacket")
	assert_eq(sent[0]["data"]["commandId"], LoginHandshake.LOGIN_REQUEST)
	assert_eq(sent[0]["data"]["playerId"], 0, "no player id is known yet")

	var body: Dictionary = JSON.parse_string(sent[0]["data"]["command"])
	assert_eq(body["email"], "me@example.com")
	assert_eq(body["password"], "secret")
	assert_eq(body["characterUuid"], "char-1")
	assert_eq(body["token"], "tok-1")
	assert_eq(client.state, GraveBoundClient.State.AWAITING_LOGIN)


func test_login_without_a_token_sends_null():
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	var body: Dictionary = JSON.parse_string(transport.sent_packets()[0]["data"]["command"])
	assert_null(body["token"], "an absent token is null, as the Java DTO expects")


func test_successful_login_enters_the_game():
	_connect_and_login(777)
	assert_signal_emitted(client, "login_succeeded")
	assert_eq(client.player_id, 777)
	assert_eq(client.state, GraveBoundClient.State.IN_GAME)
	assert_true(client.is_in_game())
	assert_eq(int(client.login_response["classId"]), 2)


func test_rejected_login_closes_the_connection():
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(0, 0, Vector2.ZERO, false))
	client._process(0.0)
	assert_signal_emitted(client, "login_failed")
	assert_eq(client.state, GraveBoundClient.State.CLOSED)


func test_server_error_in_game_is_a_signal_not_a_login_failure():
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.frame("CommandPacket", {
		"playerId": 7, "commandId": LoginHandshake.LOGIN_RESPONSE,
		"command": JSON.stringify({"success": true, "playerId": 7}),
	}))
	client._process(0.0)
	transport.deliver(WireHelper.frame("CommandPacket", {
		"playerId": 7, "commandId": LoginHandshake.SERVER_ERROR,
		"command": JSON.stringify({"message": "Player lacks required provision for command /spawn"}),
	}))
	client._process(0.0)
	assert_signal_emitted_with_parameters(client, "server_error",
		["Player lacks required provision for command /spawn"])
	assert_signal_not_emitted(client, "login_failed")
	assert_eq(client.state, GraveBoundClient.State.IN_GAME, "still in the game")


func test_server_error_during_login_is_surfaced():
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.frame("CommandPacket", {
		"playerId": 0,
		"commandId": LoginHandshake.SERVER_ERROR,
		"command": JSON.stringify({"message": "bad credentials"}),
	}))
	client._process(0.0)
	assert_signal_emitted(client, "login_failed")


func test_unparseable_command_body_is_ignored():
	_connect_and_login()
	transport.deliver(WireHelper.frame("CommandPacket",
		{"playerId": 1, "commandId": LoginHandshake.SERVER_COMMAND, "command": "not json"}))
	client._process(0.0)
	assert_eq(client.state, GraveBoundClient.State.IN_GAME, "a malformed command body is not fatal")


func test_send_server_command_uses_the_assigned_player_id():
	_connect_and_login(55)
	transport.clear_sent()
	client.send_server_command("/tp 10 10")
	var sent := transport.sent_packets()
	assert_eq(sent[0]["data"]["playerId"], 55)
	assert_eq(sent[0]["data"]["commandId"], LoginHandshake.SERVER_COMMAND)
	var body: Dictionary = JSON.parse_string(sent[0]["data"]["command"])
	assert_eq(body["command"], "tp", "the word after the slash, as ServerCommandMessage.parseFromInput reads it")
	assert_eq(body["args"], ["10", "10"])
	client.send_server_command("loadout")
	body = JSON.parse_string(transport.sent_packets()[1]["data"]["command"])
	assert_eq(body, {"command": "loadout", "args": []}, "no slash: the whole line is the command")


# --- stream handling -------------------------------------------------------

func test_reassembles_a_frame_delivered_one_byte_at_a_time():
	_connect_and_login()
	var frame := WireHelper.frame("PlayerStatePacket",
		{"playerId": 1, "health": 42, "mana": 7, "effectIds": [], "effectTimes": []})
	transport.deliver(frame)
	transport.chunk_size = 1
	for i in frame.size():
		client._process(0.0)
	var packets: Array = get_signal_parameters(client, "packet_received", -1)
	assert_eq(packets[0], "PlayerStatePacket")
	assert_eq(packets[1]["health"], 42)


func test_handles_several_frames_in_one_read():
	_connect_and_login()
	transport.deliver(WireHelper.frame("PlayerStatePacket",
		{"playerId": 1, "health": 1, "mana": 1, "effectIds": [], "effectTimes": []}))
	transport.deliver(WireHelper.frame("PlayerStatePacket",
		{"playerId": 1, "health": 2, "mana": 2, "effectIds": [], "effectTimes": []}))
	transport.deliver(WireHelper.frame("UnloadPacket", {}))
	client._process(0.0)
	assert_eq(client.stats.packets_in, 4, "login response plus three more")


func test_partial_trailing_frame_is_buffered_not_dropped():
	_connect_and_login()
	var frame := WireHelper.frame("PlayerStatePacket",
		{"playerId": 1, "health": 99, "mana": 0, "effectIds": [], "effectTimes": []})
	transport.deliver(frame.slice(0, frame.size() - 3))
	client._process(0.0)
	var before: int = client.stats.packets_in
	transport.deliver(frame.slice(frame.size() - 3))
	client._process(0.0)
	assert_eq(client.stats.packets_in, before + 1, "the frame completes on the next read")


func test_compressed_frames_are_decoded():
	_connect_and_login()
	var tiles := []
	for i in 200:
		tiles.append(WireHelper.tile(i % 20, 0, i, i))
	var frame := WireHelper.frame("LoadMapPacket",
		{"realmId": 1, "mapId": 1, "mapWidth": 256, "mapHeight": 256, "tiles": tiles})
	assert_true(NetFrame.is_compressed(frame[0]), "precondition: this frame is deflated")
	transport.deliver(frame)
	client._process(0.0)
	var params: Array = get_signal_parameters(client, "packet_received", -1)
	assert_eq(params[0], "LoadMapPacket")
	assert_eq(params[1]["tiles"].size(), 200)


func test_unknown_packet_id_is_counted_and_survived():
	_connect_and_login()
	transport.deliver(PackedByteArray([120, 0, 0, 0, 6, 1]))  # id 120 is unassigned
	client._process(0.0)
	assert_eq(client.stats.unknown_packets, 1)
	assert_eq(client.state, GraveBoundClient.State.IN_GAME, "an unknown id is skipped, not fatal")


func test_desynced_stream_disconnects():
	_connect_and_login()
	transport.deliver(PackedByteArray([1, 0x7F, 0xFF, 0xFF, 0xFF, 0, 0]))
	client._process(0.0)
	assert_signal_emitted(client, "disconnected")
	assert_eq(client.state, GraveBoundClient.State.CLOSED)


func test_socket_error_disconnects():
	_connect_and_login()
	transport.status = StreamPeerTCP.STATUS_ERROR
	client._process(0.0)
	assert_signal_emitted(client, "disconnected")


func test_server_hangup_disconnects():
	_connect_and_login()
	transport.status = StreamPeerTCP.STATUS_NONE
	client._process(0.0)
	assert_signal_emitted(client, "disconnected")


func test_read_failure_disconnects():
	_connect_and_login()
	transport.deliver(PackedByteArray([1, 2, 3]))
	transport.read_error = ERR_CONNECTION_ERROR
	client._process(0.0)
	assert_signal_emitted(client, "disconnected")


func test_write_failure_disconnects():
	_connect_and_login()
	transport.put_error = ERR_CONNECTION_ERROR
	client.send("HeartbeatPacket", {"playerId": 1, "timestamp": 1})
	assert_signal_emitted(client, "disconnected")


func test_disconnect_is_idempotent():
	_connect_and_login()
	client.disconnect_from_server()
	client.disconnect_from_server()
	assert_signal_emit_count(client, "disconnected", 1)


# --- steady state ----------------------------------------------------------

func test_heartbeat_is_sent_on_the_interval():
	_connect_and_login()
	transport.clear_sent()
	now = 5
	client._process(GraveBoundClient.HEARTBEAT_INTERVAL * 0.5)
	assert_eq(transport.sent_packets().size(), 0, "not yet due")
	client._process(GraveBoundClient.HEARTBEAT_INTERVAL * 0.6)
	var sent := transport.sent_packets()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["name"], "HeartbeatPacket")
	assert_false(sent[0]["data"].has("playerId"), "v0.9.0 heartbeat is a bare timestamp")
	assert_gt(sent[0]["data"]["timestamp"], 0)


func test_no_heartbeat_before_login():
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(10.0)
	assert_eq(transport.sent_packets().size(), 0)


func test_send_move_carries_the_sequence_and_no_entity_id():
	_connect_and_login(321)
	transport.clear_sent()
	client.send_move(7, 1.0, 0.0)
	var sent := transport.sent_packets()
	assert_eq(sent[0]["name"], "PlayerMovePacket")
	assert_eq(sent[0]["data"]["seq"], 7)
	assert_false(sent[0]["data"].has("entityId"), "v0.9.0 dropped it; the server takes the id from the connection")
	assert_almost_eq(sent[0]["data"]["vx"], 1.0, 0.0001)


func test_position_ack_produces_an_rtt_sample():
	_connect_and_login()
	client.send_move(1, 1.0, 0.0)
	now = 50
	transport.deliver(WireHelper.frame("PlayerPosAckPacket", {"seq": 1, "posX": 0.0, "posY": 0.0}))
	client._process(0.0)
	assert_almost_eq(client.stats.rtt_ms, 50.0, 0.001, "first sample is used directly")


func test_rtt_is_smoothed_across_samples():
	_connect_and_login()
	client.send_move(1, 1.0, 0.0)
	now = 100
	transport.deliver(WireHelper.frame("PlayerPosAckPacket", {"seq": 1, "posX": 0.0, "posY": 0.0}))
	client._process(0.0)
	client.send_move(2, 1.0, 0.0)
	now = 300
	transport.deliver(WireHelper.frame("PlayerPosAckPacket", {"seq": 2, "posX": 0.0, "posY": 0.0}))
	client._process(0.0)
	assert_between(client.stats.rtt_ms, 100.0, 200.0, "smoothed, not snapped to the new sample")


func _echo_heartbeat(after_ms: int) -> void:
	client._process(GraveBoundClient.HEARTBEAT_INTERVAL)
	var sent := transport.sent_packets()
	var stamp: int = sent[sent.size() - 1]["data"]["timestamp"]
	assert_eq(stamp, now, "the heartbeat carries our own clock")
	now += after_ms
	transport.deliver(WireHelper.frame("HeartbeatPacket", {"timestamp": stamp}))
	client._process(0.0)


func test_heartbeat_echo_measures_ping_one_way_as_both_references_do():
	_connect_and_login()
	_echo_heartbeat(40)
	assert_eq(client.stats.ping_ms, 20, "half the round trip")
	assert_eq(client.stats.jitter_ms, 0)
	_echo_heartbeat(80)
	assert_eq(client.stats.ping_ms, 30, "mean of 40 and 80, halved")
	assert_eq(client.stats.jitter_ms, 10, "one-way samples 20 and 40 spread 10 about 30")
	assert_almost_eq(client.stats.round_trip_ms(), 60.0, 0.001)


func test_ping_averages_only_the_last_ten_echoes():
	_connect_and_login()
	for i in 10:
		_echo_heartbeat(200)
	for i in 10:
		_echo_heartbeat(100)
	assert_eq(client.stats.ping_ms, 50, "the 200ms trips have all aged out")


func test_an_implausible_echo_is_not_a_sample():
	_connect_and_login()
	_echo_heartbeat(0)
	assert_eq(client.stats.ping_ms, 0, "a trip that took no time is clock skew")
	_echo_heartbeat(5000)
	assert_eq(client.stats.ping_ms, 0, "and so is one that took five seconds")
	assert_eq(client.stats.round_trip_ms(), 0.0)


func test_the_round_trip_falls_back_to_movement_acks_until_an_echo_lands():
	_connect_and_login()
	client.send_move(1, 1.0, 0.0)
	now = 50
	transport.deliver(WireHelper.frame("PlayerPosAckPacket", {"seq": 1, "posX": 0.0, "posY": 0.0}))
	client._process(0.0)
	assert_almost_eq(client.stats.round_trip_ms(), 50.0, 0.001, "the ack's figure")
	_echo_heartbeat(90)
	assert_almost_eq(client.stats.round_trip_ms(), 90.0, 0.001, "the heartbeat's, once there is one")
	client.disconnect_from_server()
	client.connect_to_server("127.0.0.1", 2222)
	assert_eq(client.stats.ping_ms, 0, "a new connection starts unmeasured")


func test_ack_for_an_unknown_sequence_is_ignored():
	_connect_and_login()
	transport.deliver(WireHelper.frame("PlayerPosAckPacket", {"seq": 999, "posX": 0.0, "posY": 0.0}))
	client._process(0.0)
	assert_eq(client.stats.rtt_ms, 0.0)


func test_pending_ack_table_is_bounded():
	_connect_and_login()
	for i in 400:
		client.send_move(i, 0.0, 0.0)
	assert_lte(client.stats.pending_count(), 256)


func test_send_of_an_unknown_packet_is_refused():
	_connect_and_login()
	transport.clear_sent()
	client.send("NotARealPacket", {})
	assert_eq(transport.sent.size(), 0)


func test_send_while_disconnected_is_dropped():
	client.send("HeartbeatPacket", {"playerId": 1, "timestamp": 1})
	assert_eq(transport.sent.size(), 0)


func test_byte_and_packet_counters_track_both_directions():
	_connect_and_login()
	assert_gt(client.stats.bytes_out, 0)
	assert_gt(client.stats.bytes_in, 0)
	assert_eq(client.stats.packets_out, 1, "the login command")
	assert_eq(client.stats.packets_in, 1, "the login response")
	assert_eq(client.stats.packet_counts["CommandPacket"], 1)


func test_reconnect_clears_previous_session_state():
	_connect_and_login(11)
	client.disconnect_from_server()
	client.connect_to_server("h", 1)
	assert_eq(client.player_id, 0)
	assert_eq(client.login_response, {})


func test_reconnecting_after_a_disconnect_succeeds():
	# A live socket refuses a fresh connect, so without resetting it every
	# retry fails with ERR_ALREADY_IN_USE and the client can never recover.
	_connect_and_login(5)
	client.disconnect_from_server()
	client.connect_to_server("127.0.0.1", 2222)
	assert_ne(client.state, GraveBoundClient.State.CLOSED, "the retry opened a socket")
	assert_signal_emit_count(client, "connection_failed", 0)


func test_a_second_connect_attempt_while_connecting_still_works():
	# What a user does when the first attempt looks stuck: press it again.
	client.connect_to_server("127.0.0.1", 2222)
	client.connect_to_server("127.0.0.1", 2222)
	assert_signal_emit_count(client, "connection_failed", 0)
	assert_eq(client.state, GraveBoundClient.State.CONNECTING)
