extends GutTest

## The party panel and the invite prompt, and what they send.

var content: GameData
var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var actions: PartyActions
var popup: PartyInvitePopup
var panel: PartyPanel
var wall := 1_700_000_000_000


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	state.party.wall_clock = func() -> int: return wall
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	actions = PartyActions.new(state, client)
	popup = PartyInvitePopup.new()
	popup.setup(state, actions)
	add_child_autofree(popup)
	panel = PartyPanel.new()
	panel.setup(state, content, actions)
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


## Each CommandPacket sent, back as the line it was typed as.
func _commands() -> Array:
	return transport.sent_packets().filter(func(p: Dictionary) -> bool: return p["name"] == "CommandPacket") \
		.map(func(p: Dictionary) -> String:
			var parsed: Dictionary = JSON.parse_string(p["data"]["command"])
			return "/" + " ".join([parsed["command"]] + Array(parsed["args"])))


func _member(id: int, name: String, class_id := 0, extra := {}) -> Dictionary:
	var m := {"playerId": id, "name": name, "classId": class_id, "health": 50, "maxHealth": 200,
		"mana": 30, "maxMana": 60, "level": 4, "realmId": 0, "effectIds": [],
		"hotbarBindings": [13000, 0, 13002, 0], "abilityCooldownEnds": [0, 0, 0, 0],
		"hotbarInvested": [0, 0, 0, 0], "stats": {"str": 12, "def": 3}, "equipment": []}
	m.merge(extra, true)
	return m


func _party(leader: int, members: Array) -> void:
	state.apply_packet("PartyUpdatePacket", {"partyId": 7, "leaderId": leader, "members": members})
	panel._process(0.0)


func _invited() -> void:
	state.apply_packet("TextPacket", {"from": "SYSTEM", "to": "Ruu",
		"message": "Zed invited you to a party. Type /party accept or /party decline."})
	popup._process(0.0)


func test_the_prompt_names_who_asked_and_its_buttons_answer():
	_in_game()
	popup._process(0.0)
	assert_false(popup.visible)
	_invited()
	assert_true(popup.visible)
	assert_eq(popup._line.text, "Zed wants you in their party")
	assert_true(actions.accept())
	assert_eq(_commands(), ["/party accept"])
	popup._process(0.0)
	assert_false(popup.visible, "answered, so gone at once")
	assert_false(actions.accept(), "nothing to answer now")
	_invited()
	transport.clear_sent()
	assert_true(actions.decline())
	assert_eq(_commands(), ["/party decline"])


func test_the_panel_lists_everyone_but_you_and_counts_the_whole_party():
	_in_game()
	panel._process(0.0)
	assert_false(panel.visible, "no party")
	_party(4, [_member(9, "Ruu"), _member(4, "Mingau", 2), _member(5, "Bort")])
	assert_true(panel.visible)
	assert_eq(panel._count.text, "Party 3/4")
	assert_eq(panel._rows.size(), 2, "not ourselves")
	assert_eq(panel._rows[0].member_name, "Mingau")
	assert_eq(panel._rows[0]._name.text, "* Mingau", "starred: the leader")
	assert_eq(panel._rows[1]._name.text, "Bort")
	assert_false(panel._rows[0]._kick.visible, "we are not the leader")
	assert_almost_eq(panel._rows[0]._hp.value, 0.25, 0.001)
	assert_almost_eq(panel._rows[0]._mp.value, 0.5, 0.001)
	assert_eq(panel._rows[0].tooltip_text.split("\n")[1], "Lv 4 Wizard")
	assert_eq(panel._rows[0].tooltip_text.split("\n")[4], "STR 12  DEF 3  SPD 0  DEX 0")


func test_rows_are_rebuilt_on_the_shape_and_only_patched_between():
	_in_game()
	_party(4, [_member(9, "Ruu"), _member(4, "Mingau")])
	var row: PartyRow = panel._rows[0]
	_party(4, [_member(9, "Ruu"), _member(4, "Mingau", 0, {"health": 200})])
	assert_true(is_instance_valid(row) and panel._rows[0] == row, "same shape, same row")
	assert_eq(row._hp.value, 1.0, "but the bar moved")
	_party(4, [_member(9, "Ruu"), _member(4, "Mingau", 0, {"hotbarBindings": [13000, 13002, 0, 0]})])
	assert_true(panel._rows[0] != row, "a hotbar change is a new shape")


func test_the_leader_can_kick_and_only_the_leader():
	_in_game()
	_party(9, [_member(9, "Ruu"), _member(4, "Mingau")])
	assert_true(panel._rows[0]._kick.visible)
	panel._rows[0]._kick.pressed.emit()
	assert_eq(_commands(), ["/party kick Mingau"])
	transport.clear_sent()
	_party(4, [_member(9, "Ruu"), _member(4, "Mingau")])
	assert_false(actions.kick("Mingau"), "refused here, as the server would refuse it")
	assert_eq(_commands(), [])


func test_leave_invite_and_the_gates():
	_in_game()
	assert_false(actions.leave(), "not in a party")
	assert_false(actions.invite("  "))
	assert_true(actions.invite("Mingau"))
	_party(4, [_member(9, "Ruu"), _member(4, "Mingau")])
	assert_true(actions.leave())
	assert_eq(_commands(), ["/party invite Mingau", "/party leave"])
	state.apply_packet("PartyUpdatePacket", {"partyId": 0, "leaderId": 0, "members": []})
	panel._process(0.0)
	assert_false(panel.visible, "partyId 0: gone")


func test_a_cooldown_shades_the_slot_and_another_realm_dims_the_row():
	_in_game()
	state.apply_packet("LoadMapPacket", {"realmId": 5, "mapId": 1, "tiles": [WireHelper.tile(1, 0, 0, 0)]})
	var total := content.abilities.cooldown_ms(13000, 0)
	assert_gt(total, 0, "the fixture's barbarian ability has a cooldown")
	_party(4, [_member(9, "Ruu"), _member(4, "Mingau", 0, {"abilityCooldownEnds": [wall + total / 2, 0, 0, 0], "realmId": 6}),
		_member(5, "Bort", 0, {"realmId": 5})])
	var row: PartyRow = panel._rows[0]
	assert_almost_eq(row._cells[0][1].size.y, PartyRow.CELL * 0.5, 0.01, "half the cell shaded")
	assert_eq(row._cells[1][1].size.y, 0.0, "nothing bound, nothing shaded")
	assert_almost_eq(row.modulate.a, PartyRow.OTHER_REALM_ALPHA, 0.001, "elsewhere")
	assert_eq(panel._rows[1].modulate.a, 1.0, "here")


func test_nothing_is_sent_outside_a_realm():
	assert_false(actions.invite("Mingau"))
	assert_false(actions.leave())
	assert_eq(transport.sent_packets(), [])
