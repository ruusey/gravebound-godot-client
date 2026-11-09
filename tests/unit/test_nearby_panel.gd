extends GutTest

## The nearby list under the party panel, and the menu a row opens.

var content: GameData
var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var party_panel: PartyPanel
var panel: NearbyPanel


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	var party_actions := PartyActions.new(state, client)
	party_panel = PartyPanel.new()
	party_panel.setup(state, content, party_actions)
	add_child_autofree(party_panel)
	panel = NearbyPanel.new()
	panel.setup(state, content, TradeActions.new(state, client), party_actions,
		ChatActions.new(state, client), GuildActions.new(state, client, null), party_panel)
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


func _commands() -> Array:
	return transport.sent_packets().filter(func(p: Dictionary) -> bool: return p["name"] == "CommandPacket") \
		.map(func(p: Dictionary) -> String:
			var parsed: Dictionary = JSON.parse_string(p["data"]["command"])
			return "/" + " ".join([parsed["command"]] + Array(parsed["args"])))


func _others(names: Array, role := "") -> void:
	var players: Array = [WireHelper.player(9, "Ruu", Vector2.ZERO)]
	for i in names.size():
		var wire := WireHelper.player(20 + i, names[i], Vector2(i * 10, 0))
		wire["chatRole"] = role
		players.append(wire)
	state.apply_packet("LoadPacket", {"players": players})
	panel._process(0.0)


func _rows() -> Array:
	return panel._rows_box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())


func test_hidden_without_a_player_and_empty_says_so():
	panel._process(0.0)
	assert_false(panel.visible)
	_in_game()
	_others([])
	assert_true(panel.visible)
	assert_true(panel._empty.visible)
	assert_eq(_rows().size(), 0)


func test_lists_the_others_with_their_role_colour_and_tooltip():
	_in_game()
	_others(["Mingau", "Sable"], "admin")
	assert_false(panel._empty.visible)
	var rows := _rows()
	assert_eq(rows.size(), 2)
	var name: Label = rows[0].get_child(1)
	assert_eq(name.text, "Mingau")
	assert_eq(name.get_theme_color("font_color"), Color("4080e0"))
	rows[0].mouse_entered.emit()
	assert_true(panel._inspect.visible, "a hover brings up the inspect card")
	assert_eq(panel._inspect._name.text, "Mingau  [admin]")


func test_rebuilds_only_when_who_is_listed_changes():
	_in_game()
	_others(["Mingau"])
	var row: Node = _rows()[0]
	panel._process(0.0)
	assert_eq(_rows()[0], row, "nothing changed, same row")
	_others(["Mingau", "Bort"])
	assert_eq(_rows().size(), 2)
	assert_true(_rows()[0] != row, "rebuilt")


func test_a_party_member_leaves_the_list_and_the_panel_moves_under_the_party():
	_in_game()
	_others(["Mingau", "Bort"])
	assert_eq(panel._root.offset_top, float(PartyPanel.TOP))
	state.apply_packet("PartyUpdatePacket", {"partyId": 7, "leaderId": 9, "members": [
		{"playerId": 9, "name": "Ruu", "classId": 0}, {"playerId": 20, "name": "Mingau", "classId": 0}]})
	party_panel._process(0.0)
	await wait_process_frames(1)
	panel._process(0.0)
	assert_eq(_rows().size(), 1)
	assert_eq((_rows()[0].get_child(1) as Label).text, "Bort")
	assert_gt(panel._root.offset_top, float(PartyPanel.TOP) + NearbyPanel.GAP, "under the party panel")


func test_the_menu_opens_on_a_click_and_each_choice_is_the_chats_command():
	_in_game()
	_others(["Mingau"])
	assert_false(panel.menu.visible)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	panel._on_row_input(press, state.entities.players[20])
	assert_true(panel.menu.visible)
	assert_eq(panel.menu._header.text, "Mingau")
	assert_true(panel.menu.choose("trade"))
	assert_false(panel.menu.visible, "closed on a choice")
	panel.open_menu(state.entities.players[20])
	assert_true(panel.menu.choose("teleport"))
	panel.open_menu(state.entities.players[20])
	assert_true(panel.menu.choose("invite"))
	panel.open_menu(state.entities.players[20])
	assert_true(panel.menu.choose("pvp"))
	assert_eq(_commands(), ["/trade Mingau", "/tp Mingau", "/party invite Mingau", "/pvp Mingau"])
	assert_false(panel.menu.choose("pvp"), "nothing open")


func test_guild_invite_shows_only_when_your_rank_allows_and_sends_a_guild_action():
	_in_game()
	_others(["Mingau"])
	panel.open_menu(state.entities.players[20])
	assert_false(panel.menu._guild_button.visible, "not in a guild, no guild invite")
	panel.menu.close()
	state.guild.in_guild = true
	state.guild.your_rank = GuildState.RANK_OWNER
	panel.open_menu(state.entities.players[20])
	assert_true(panel.menu._guild_button.visible, "an owner can invite to the guild")
	assert_true(panel.menu.choose("guild"))
	var sent := transport.sent_packets().filter(func(p: Dictionary) -> bool: return p["name"] == "GuildActionPacket")
	assert_eq(sent.size(), 1)
	assert_eq(int(sent[0]["data"]["action"]), int(GuildActions.Action.INVITE))
	assert_eq(sent[0]["data"]["targetName"], "Mingau")


func test_the_menu_closes_when_its_player_leaves_or_the_panel_hides():
	_in_game()
	_others(["Mingau"])
	panel.open_menu(state.entities.players[20])
	state.apply_packet("UnloadPacket", {"players": [20], "bullets": [], "enemies": [], "containers": [], "portals": []})
	panel._process(0.0)
	assert_false(panel.menu.visible, "gone with the player")
	_others(["Mingau"])
	panel.open_menu(state.entities.players[20])
	panel.shown = false
	panel._process(0.0)
	assert_false(panel.menu.visible)


func test_a_press_outside_the_menu_closes_it_and_the_menu_is_the_panels_to_own():
	_in_game()
	_others(["Mingau"])
	assert_false(panel.captures_mouse(), "the mouse is not over the list")
	panel.open_menu(state.entities.players[20])
	await wait_process_frames(1)
	var on_menu: Vector2 = panel.menu.get_global_rect().get_center()
	assert_true(panel.owns(on_menu), "the menu is the panel's")
	assert_true(panel.owns(panel._root.get_global_rect().get_center()))
	assert_false(panel.owns(Vector2(2000, 2000)))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = on_menu
	panel._unhandled_input(press)
	assert_true(panel.menu.visible, "a press on the menu is a choice, not a dismissal")
	press.position = Vector2(2000, 2000)
	panel._unhandled_input(press)
	assert_false(panel.menu.visible)
	panel.menu.close()
	assert_false(panel.owns(on_menu), "closed, the menu owns nothing")
