extends GutTest

## Leaving a realm: what gets sent, in what order, and what is torn down.

var portals: PortalInput
var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var now := 10_000


func before_each():
	now = 10_000
	var content := GameData.new()
	await content.load_from(FileContentSource.new(
		ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return now)

	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)

	portals = PortalInput.new(state, client, content)

	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 0, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	state.apply_packet("LoadMapPacket", {"realmId": 77, "mapId": 2,
		"tiles": [WireHelper.tile(1, 0, 0, 0)]})
	transport.clear_sent()


func after_each():
	Input.action_release("use_portal")
	Input.action_release("go_nexus")


func test_a_key_typed_into_the_chat_line_is_not_a_portal():
	portals.keyboard_captured = func() -> bool: return true
	Input.action_press("go_nexus")
	portals.tick(0.0)
	assert_eq(transport.sent_packets().size(), 0, "an r in the chat line is a letter")
	Input.action_release("go_vault")


func _load_portal(id: int, portal_id: int, position: Vector2) -> void:
	state.apply_packet("LoadPacket", {"portals": [
		WireHelper.portal(id, portal_id, position)]})


func _sent(name: String) -> Array:
	var out: Array = []
	for packet in transport.sent_packets():
		if packet["name"] == name:
			out.append(packet["data"])
	return out


# --- picking a portal ------------------------------------------------------

func test_the_portal_under_your_feet_is_the_one_used():
	# BOTH in reach, the farther one loaded first: the nexus packs portals in
	# rows, so two inside the reach is the normal case, and a version that
	# simply took the last one it saw would pass against a distant decoy.
	_load_portal(5, 1, Vector2(10, 10))
	_load_portal(6, 1, Vector2(40, 30))
	portals.use_nearest()
	assert_eq(_sent("UsePortalPacket")[0]["portalId"], 5, "the closest, not the last seen")
	assert_eq(state.transition_difficulty, 0.0, "a portal with no difficulty on the wire")


func test_the_portal_hands_its_difficulty_to_the_transition():
	var wire := WireHelper.portal(7, 1, Vector2(10, 10))
	wire["targetDifficulty"] = 4.5
	state.apply_packet("LoadPacket", {"portals": [wire]})
	portals.use_nearest()
	assert_eq(state.transition_difficulty, 4.5, "what the splash shows while it loads")
	portals._cooldown = 0.0
	portals.to_nexus()
	assert_eq(state.transition_difficulty, 0.0, "the nexus shortcut has no portal, so none")


func test_the_reach_is_the_web_clients():
	# Named in pixels rather than derived from the constant, so shrinking the
	# constant is a failure here instead of a quietly smaller reach.
	assert_eq(PortalInput.REACH_PX, 64.0,
		"the web client's 64; the native's 32 is stricter than the server needs")


func test_a_portal_out_of_reach_is_not_used():
	_load_portal(5, 1, Vector2(65.0, 0))
	portals.use_nearest()
	assert_eq(_sent("UsePortalPacket").size(), 0, "nothing is in reach")
	assert_false(state.transition_pending, "and the realm is left alone")


func test_reach_is_measured_from_corner_to_corner():
	# Both references compare the wire positions directly. Measured from the
	# player's centre instead, a portal 63px to the LEFT falls outside the
	# reach while one 63px to the right still fits -- so the westward case is
	# the one that pins the convention.
	_load_portal(5, 1, Vector2(-63.0, 0))
	portals.use_nearest()
	assert_eq(_sent("UsePortalPacket").size(), 1, "63 px west is in reach")

	transport.clear_sent()
	portals.tick(PortalInput.COOLDOWN + 0.1)
	_load_portal(6, 1, Vector2(63.0, 0))
	portals.use_nearest()
	assert_eq(_sent("UsePortalPacket").size(), 1, "and so is 63 px east")


func test_nothing_happens_without_a_portal():
	portals.use_nearest()
	assert_eq(transport.sent_packets().size(), 0)


# --- the sentinels ---------------------------------------------------------

func test_an_ordinary_portal_travels_with_both_flags_off():
	_load_portal(5, 1, Vector2.ZERO)
	portals.use_nearest()
	var packet: Dictionary = _sent("UsePortalPacket")[0]
	assert_eq(packet["portalId"], 5)
	assert_eq(packet["fromRealmId"], 77, "the realm being left")
	assert_eq(packet["toVault"], -1, "-1, not 0: the server tests != -1")
	assert_eq(packet["toNexus"], -1)


func test_the_vault_portal_travels_as_a_vault_request():
	# Portal id 2 is the vault. Sent as an ordinary portal the server routes
	# it by toRealmId and never runs the branch that sets the chests up.
	_load_portal(5, PortalInput.VAULT_PORTAL, Vector2.ZERO)
	portals.use_nearest()
	var packet: Dictionary = _sent("UsePortalPacket")[0]
	assert_eq(packet["portalId"], -1)
	assert_eq(packet["toVault"], 1)
	assert_eq(packet["toNexus"], -1)


func test_the_nexus_is_asked_for_without_a_portal():
	portals.to_nexus()
	var packet: Dictionary = _sent("UsePortalPacket")[0]
	assert_eq(packet["portalId"], -1)
	assert_eq(packet["toNexus"], 1)
	assert_eq(packet["toVault"], -1)


# --- the sequence ----------------------------------------------------------

func test_the_ack_follows_the_portal_in_that_order():
	# LoginAck is what asks the server for the next map's tiles, and it has to
	# come after the portal request, not before it.
	_load_portal(5, 1, Vector2.ZERO)
	portals.use_nearest()
	var names: Array = []
	for packet in transport.sent_packets():
		names.append(packet["name"])
	assert_eq(names, ["UsePortalPacket", "LoginAckPacket"])


func test_the_realm_is_torn_down_locally():
	_load_portal(5, 1, Vector2.ZERO)
	state.apply_packet("LoadPacket", {
		"enemies": [WireHelper.enemy(3, 1, Vector2.ZERO)],
		"bullets": [{"id": 8, "pos": {"x": 0, "y": 0}, "angle": 0.0,
			"magnitude": 1.0, "range": 100.0, "flags": []}],
	})
	portals.use_nearest()
	assert_true(state.transition_pending)
	assert_eq(state.entities.enemies.size(), 0, "enemies do not cross")
	assert_eq(state.entities.portals.size(), 0, "nor does the portal itself")
	assert_eq(state.projectiles.bullets.size(), 0)
	assert_eq(state.tiles.tile_count(), 0, "the map we are leaving goes too")


func test_prediction_starts_over():
	# Replaying inputs made on the old map into the new one would only fight
	# the spawn position that follows.
	state.advance(RealmState.TICK_DELTA * 3.0, Vector2.RIGHT, 0.0)
	assert_gt(state.movement.pending_input_count(), 0)
	_load_portal(5, 1, Vector2.ZERO)
	portals.use_nearest()
	assert_eq(state.movement.pending_input_count(), 0)


func test_the_load_map_that_answers_clears_the_flag():
	_load_portal(5, 1, Vector2.ZERO)
	portals.use_nearest()
	state.apply_packet("LoadMapPacket", {"realmId": 78, "mapId": 4,
		"tiles": [WireHelper.tile(1, 0, 0, 0)]})
	assert_false(state.transition_pending)


# --- guards ----------------------------------------------------------------

func test_the_cooldown_suppresses_a_second_use():
	_load_portal(5, 1, Vector2.ZERO)
	portals.use_nearest()
	_load_portal(5, 1, Vector2.ZERO)
	portals.tick(PortalInput.COOLDOWN * 0.5)
	portals.use_nearest()
	assert_eq(_sent("UsePortalPacket").size(), 1)

	portals.tick(PortalInput.COOLDOWN)
	portals.use_nearest()
	assert_eq(_sent("UsePortalPacket").size(), 2, "and lifts once it expires")


func test_the_nexus_is_not_re_entered():
	state.apply_packet("LoadMapPacket", {"realmId": 77, "mapId": 31, "tiles": []})
	portals.to_nexus()
	assert_eq(transport.sent_packets().size(), 0, "map 31 is Nexus_Auru_V1")


func test_the_vault_is_not_re_entered():
	state.apply_packet("LoadMapPacket", {"realmId": 77, "mapId": 30, "tiles": []})
	portals.to_vault()
	assert_eq(transport.sent_packets().size(), 0, "map 30 is Vault_Auru_V1")


func test_a_vault_portal_inside_the_vault_does_nothing():
	state.apply_packet("LoadMapPacket", {"realmId": 77, "mapId": 30, "tiles": []})
	_load_portal(5, PortalInput.VAULT_PORTAL, Vector2.ZERO)
	portals.use_nearest()
	assert_eq(transport.sent_packets().size(), 0)


func test_nothing_is_sent_before_the_game_starts():
	# The state the guard protects is socket OPEN with the login still in
	# flight -- pressing the key at the login screen. Testing it against a
	# closed transport instead proves nothing: the send fails on the transport
	# whether the guard is there or not.
	var pending := GraveBoundClient.new()
	var wire := FakeTransport.new()
	pending.connection.transport = wire
	add_child_autofree(pending)
	pending.connect_to_server("h", 1)
	wire.become_connected()
	pending._process(0.0)
	assert_true(pending.connection.is_open(), "the socket is up")
	assert_false(pending.is_in_game(), "and the handshake is not finished")

	var early := PortalInput.new(state, pending, GameData.new())
	_load_portal(5, 1, Vector2.ZERO)
	early.use_nearest()
	assert_eq(wire.sent_packets().size(), 0)


# --- keys ------------------------------------------------------------------

func test_the_portal_key_fires_once_while_held():
	_load_portal(5, 1, Vector2.ZERO)
	Input.action_press("use_portal")
	portals.tick(0.016)
	# Held past the cooldown, with a portal back in reach: without edge
	# detection this is a second transition, so the cooldown alone cannot be
	# what makes this pass.
	_load_portal(5, 1, Vector2.ZERO)
	portals.tick(PortalInput.COOLDOWN + 0.1)
	assert_eq(_sent("UsePortalPacket").size(), 1, "the edge, not the hold")


func test_releasing_the_key_arms_it_again():
	_load_portal(5, 1, Vector2.ZERO)
	Input.action_press("use_portal")
	portals.tick(0.016)
	Input.action_release("use_portal")
	portals.tick(PortalInput.COOLDOWN + 0.1)
	_load_portal(5, 1, Vector2.ZERO)
	Input.action_press("use_portal")
	portals.tick(0.016)
	assert_eq(_sent("UsePortalPacket").size(), 2)


func test_the_nexus_key_asks_for_the_nexus():
	Input.action_press("go_nexus")
	portals.tick(0.016)
	assert_eq(_sent("UsePortalPacket")[0]["toNexus"], 1)


func test_the_vault_key_asks_for_the_vault():
	Input.action_press("go_vault")
	portals.tick(0.016)
	assert_eq(_sent("UsePortalPacket")[0]["toVault"], 1)
