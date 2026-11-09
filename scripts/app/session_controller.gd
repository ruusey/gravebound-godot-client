class_name SessionController
extends RefCounted

## Owns the login-to-in-game flow: credentials in, realm out.
##
## Keeps the connection lifecycle in one place so Main is only construction
## and the frame loop, and so the login screen has a single thing to talk to.

signal entered_realm(response: Dictionary)
signal died(player_name: String)
signal arena_ended(results: Dictionary)

var client: GraveBoundClient
var state: RealmState
var login_screen: LoginScreen
var config: ClientConfig
## Set by Main: the handshake prefers this live session token (from an interactive
## sign-in or a desktop resume) over config.token, so the game server authenticates
## by token and the password is never needed on a resumed launch.
var data_service: DataService

var credentials := {}

var _death_acked := false


func _init(net_client: GraveBoundClient, realm_state: RealmState,
		screen: LoginScreen, client_config: ClientConfig) -> void:
	client = net_client
	state = realm_state
	login_screen = screen
	config = client_config

	client.connected.connect(_on_connected)
	client.connection_failed.connect(_on_connection_failed)
	client.login_succeeded.connect(_on_login_succeeded)
	client.login_failed.connect(_on_login_failed)
	client.packet_received.connect(_on_packet)
	client.server_error.connect(_on_server_error)
	client.disconnected.connect(_on_disconnected)
	login_screen.character_chosen.connect(begin)


## Connects and authenticates. The game server does its own lookup against the
## data service, so a character uuid is all it needs beyond the credentials.
func begin(email: String, password: String, character_uuid: String) -> void:
	credentials = {"email": email, "password": password, "character_uuid": character_uuid}
	_death_acked = false
	print("[net] connecting to %s:%d" % [ServerAddress.game_host(config), ServerAddress.game_port(config)])
	client.connect_to_server(ServerAddress.game_host(config), ServerAddress.game_port(config))


## True once a config carries enough to skip the character picker entirely.
func can_autoconnect() -> bool:
	return config.autoconnect and config.character_uuid != "" and config.email != ""


func _on_connected() -> void:
	login_screen.set_status("Connected. Authenticating ...")
	var token := config.token
	if data_service != null and data_service.token != "":
		token = data_service.token
	client.login(credentials["email"], credentials["password"],
		credentials["character_uuid"], token)


func _on_connection_failed(reason: String) -> void:
	login_screen.set_status("Could not reach %s:%d -- %s" % [ServerAddress.game_host(config), ServerAddress.game_port(config), reason], true)


func _on_login_succeeded(response: Dictionary) -> void:
	state.local.enter_realm(response)
	login_screen.visible = false
	print("[net] logged in as playerId=%d class=%d at (%.1f, %.1f)" % [
		state.local.id, state.local.class_id, state.local.position.x, state.local.position.y])
	entered_realm.emit(response)


func _on_login_failed(reason: String) -> void:
	login_screen.visible = true
	login_screen.set_status("Login rejected: %s" % reason, true)


func _on_packet(name: String, data: Dictionary) -> void:
	state.apply_packet(name, data)
	if name == "PlayerDeathPacket":
		_note_death(data)
	elif name == "ArenaResultsPacket":
		# Not a death: the server has already revived + teleported us to the nexus.
		# Show the run scoreboard over the top.
		arena_ended.emit(data)


## Acknowledges a death, once, for us.
##
## The ack is what ends the session: the server disconnects us in response to
## it rather than on its own, so a client that closes first never acks and its
## session lingers behind its own heartbeat. We deliberately do not close from
## here -- on the web path a send is queued rather than written, and closing
## before the next poll drops it.
##
## It is acked even though the server may have just revived us with a Crown of
## Resurrection: the death packet is sent before that branch, both references
## ack unconditionally, and staying connected is worse than a trip through the
## character picker -- our id is already in the server's expired list, which
## only a realm reset clears, and a player left in it stops dying at all.
func _note_death(data: Dictionary) -> void:
	if _death_acked or int(data.get("playerId", 0)) != state.local.id:
		return
	_death_acked = true
	client.send("DeathAckPacket", {})
	# Stop playing immediately. Not closing the socket is not the same as
	# carrying on: without this the client keeps predicting, keeps firing --
	# the click that dismisses the death screen is also a shot -- and keeps
	# heartbeating for a player the server has already removed from its
	# realm, which is precisely what stops the server timing the session out
	# if the ack or the close is lost.
	client.stop_playing()
	died.emit(state.local.name)


## A refused command reads in the chat log as the web client shows it --
## a SYSTEM line "Error: ..." -- rather than only in the console.
func _on_server_error(reason: String) -> void:
	state.chat.apply_text({"from": ChatLog.SYSTEM, "to": state.local.name, "message": "Error: %s" % reason})


func _on_disconnected(reason: String) -> void:
	print("[net] disconnected: %s" % reason)
	state.reset_world()
	state.local.reset()
	# After a death the disconnect is the server answering our ack, and the
	# death screen is already up saying so. Raising the login screen over it
	# would replace the explanation with "Disconnected: ...".
	if _death_acked:
		return
	login_screen.visible = true
	login_screen.set_status("Disconnected: %s" % reason, true)
