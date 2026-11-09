class_name GraveBoundClient
extends Node

## The game session: handshake, heartbeat and the state machine around them,
## mirroring the flow in the server repo's StressTestClient. Framing lives in
## NetConnection, inbound interpretation in SessionInbox, status transitions
## in ConnectionPhase. Packets surface here as (name, Dictionary).

signal connected()
signal connection_failed(reason: String)
signal login_succeeded(response: Dictionary)
signal login_failed(reason: String)
signal packet_received(name: String, data: Dictionary)
## The server refusing a command once in game -- a /spawn without the
## provision for it, say. During the login it is a login_failed instead.
signal server_error(reason: String)
signal disconnected(reason: String)

enum State { IDLE, CONNECTING, AWAITING_LOGIN, IN_GAME, ENDED, CLOSED }

const HEARTBEAT_INTERVAL := 2.0
## Pre-login sockets idle beyond GlobalConstants.SOCKET_READ_TIMEOUT are reaped.
const LOGIN_TIMEOUT := 15.0

var state: State = State.IDLE
var player_id := 0
var login_response := {}
var connection := NetConnection.new()
var clock: Callable = func() -> int: return Time.get_ticks_msec()

var stats: NetStats:
	get: return connection.stats

var _heartbeat := Heartbeat.new(HEARTBEAT_INTERVAL)
var _connect_deadline := 0.0


func connect_to_server(host: String, port := 2222) -> void:
	player_id = 0
	login_response = {}
	var err := connection.open(host, port)
	if err != OK:
		state = State.CLOSED
		connection_failed.emit("connect_to_host failed: %s" % error_string(err))
		return
	state = State.CONNECTING
	_connect_deadline = float(clock.call()) / 1000.0 + LOGIN_TIMEOUT


func login(email: String, password: String, character_uuid: String, token := "") -> void:
	send("CommandPacket", LoginHandshake.login_request(email, password, character_uuid, token))
	state = State.AWAITING_LOGIN


func send_server_command(text: String) -> void:
	send("CommandPacket", LoginHandshake.server_command(player_id, text))


func send(packet_name: String, data: Dictionary) -> void:
	var err := connection.send(packet_name, data)
	if err != OK and err != ERR_UNAVAILABLE and err != ERR_INVALID_PARAMETER:
		_close("write failed: %s" % error_string(err))


## Sends movement input, recording the sequence so the matching
## PlayerPosAckPacket becomes an RTT sample.
func send_move(seq: int, vx: float, vy: float) -> void:
	connection.stats.expect_ack(seq, clock.call())
	send("PlayerMovePacket", {"seq": seq, "vx": vx, "vy": vy})


func disconnect_from_server() -> void:
	_close("closed by client")


func is_in_game() -> bool:
	return state == State.IN_GAME


## Stops playing without hanging up.
##
## Death ends the session, but the socket has to stay open a moment longer:
## the server disconnects us in answer to the ack, and on the web path a send
## is queued rather than written, so closing here would drop it. Everything
## that drives the game reads is_in_game(), so leaving that state is what
## stops prediction, shooting, portals and the heartbeat at once -- both
## references stop the loop at the ack rather than at the close, and the
## heartbeat is the one that matters: it is what keeps the server's own
## timeout from reaping a client that never hears the close.
func stop_playing() -> void:
	if state == State.IN_GAME:
		state = State.ENDED


func _process(delta: float) -> void:
	tick(delta)


## One frame of the connection: status, inbound packets, the heartbeat.
##
## Main calls this itself at its own point in the frame and switches the
## engine's _process off: the acks have to land BEFORE prediction places
## the camera, or a correction moves the sprite after the camera was set
## and the frame is drawn with the two apart -- a one-frame flick at every
## correction.
func tick(delta: float) -> void:
	if state == State.IDLE or state == State.CLOSED:
		return
	if not _advance_connection():
		return
	_receive()
	_send_heartbeat(delta)


## Resolves the socket's status into our own state. Returns false when there
## is nothing further to do this frame.
func _advance_connection() -> bool:
	connection.poll()
	var past_deadline: bool = float(clock.call()) / 1000.0 > _connect_deadline
	match ConnectionPhase.evaluate(connection.status(), state == State.CONNECTING, past_deadline):
		ConnectionPhase.ERROR:
			_close("socket error")
		ConnectionPhase.HANGUP:
			_close("connection closed by server")
		ConnectionPhase.TIMED_OUT:
			_close("connect timed out")
		ConnectionPhase.OPENED:
			state = State.AWAITING_LOGIN
			connected.emit()
			return true
		ConnectionPhase.READY:
			return true
	return false


func _receive() -> void:
	for event in SessionInbox.process(connection.read(), connection.stats, clock.call()):
		_apply(event)
		if state == State.CLOSED:
			return


func _apply(event: Dictionary) -> void:
	match event["kind"]:
		"packet":
			packet_received.emit(event["name"], event["data"])
		"unknown":
			push_warning("GraveBoundClient: unknown packet id %d" % event["id"])
		"login_ok":
			login_response = event["body"]
			player_id = int(login_response.get("playerId", 0))
			state = State.IN_GAME
			login_succeeded.emit(login_response)
		"login_rejected":
			login_failed.emit(event["reason"])
			_close("login rejected")
		"server_error":
			if state == State.AWAITING_LOGIN:
				login_failed.emit(event["reason"])
			else:
				server_error.emit(event["reason"])
			push_warning("GraveBound server error: %s" % event["reason"])
		"desync":
			_close(event["reason"])


## The timestamp is ours to choose: the server only echoes it, and the echo
## against the same clock is the ping measurement.
func _send_heartbeat(delta: float) -> void:
	if state != State.IN_GAME or not _heartbeat.tick(delta):
		return
	# rttMs lets the server lag-compensate our shots against the enemy positions we
	# actually saw; 0 until the first echo measures a round trip.
	send("HeartbeatPacket", {"timestamp": int(clock.call()), "rttMs": int(stats.round_trip_ms())})


func _close(reason: String) -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	connection.close()
	disconnected.emit(reason)
