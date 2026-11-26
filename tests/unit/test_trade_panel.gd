extends GutTest

## The request popup and the trade panel, and what they send.

var content: GameData
var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var actions: TradeActions
var popup: InteractionRequestPopup
var panel: TradePanel


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	actions = TradeActions.new(state, client)
	popup = InteractionRequestPopup.new()
	popup.setup(state, actions.interactions, Interaction.Kind.TRADE)
	add_child_autofree(popup)
	panel = TradePanel.new()
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


func _sent() -> Array:
	return transport.sent_packets()


func _open() -> void:
	var theirs: Array = []
	theirs.resize(Inventory.SIZE)
	theirs.fill({"itemId": -1})
	theirs[5] = {"itemId": 105, "stackCount": 3, "stackable": true}
	theirs[7] = {"itemId": 300}
	state.apply_packet("AcceptTradeRequestPacket", {"accepted": true,
		"player0": WireHelper.player(9, "Ruu", Vector2.ZERO), "player1": WireHelper.player(4, "Mingau", Vector2.ZERO),
		"player0Inv": [], "player1Inv": theirs})


func test_the_popup_names_who_asked_and_its_buttons_answer():
	_in_game()
	popup._process(0.0)
	assert_false(popup.visible)
	state.apply_packet("InteractionPacket", WireHelper.interaction(Interaction.Kind.TRADE,
		Interaction.Event.REQUESTED, "Mingau", "", 15_000))
	popup._process(0.0)
	assert_true(popup.visible)
	assert_eq(popup._line.text, "Mingau wants to trade")
	assert_true(actions.accept())
	popup._process(0.0)
	assert_false(popup.visible, "answered, so gone at once")
	assert_true(actions.decline())
	assert_eq(WireHelper.interaction_actions(transport), ["TRADE ACCEPT", "TRADE DECLINE"])


func test_the_panel_shows_both_pages_and_lights_what_is_on_the_table():
	_in_game()
	state.local.inventory.put(5, {"itemId": 310, "stackCount": 2, "stackable": true})
	panel._process(0.0)
	assert_false(panel.visible)
	_open()
	panel._process(0.0)
	assert_true(panel.visible)
	assert_eq(panel._my_name.text, "Ruu")
	assert_eq(panel._their_name.text, "Mingau")
	assert_eq(panel._status.text, "Selecting items")
	assert_eq(int(panel._mine[0].item.get("itemId", -1)), 310)
	assert_eq(int(panel._theirs[0].item.get("itemId", -1)), 105)
	assert_eq(int(panel._theirs[2].item.get("itemId", -1)), 300)
	assert_eq(panel._theirs[0].mouse_filter, Control.MOUSE_FILTER_PASS, "theirs are read-only but still hover for the tooltip")
	assert_eq(panel._mine[0].self_modulate, Color.WHITE)
	state.apply_packet("UpdateTradePacket", {"selections": {
		"player0Selection": {"playerId": 9, "selection": [true], "itemRefs": [], "confirmed": false},
		"player1Selection": {"playerId": 4, "selection": [false, false, true], "itemRefs": [], "confirmed": true}}})
	panel._process(0.0)
	assert_eq(panel._theirs[2].self_modulate, TradePanel.SELECTED, "their crystal is on the table")
	assert_eq(panel._status.text, "Mingau confirmed - confirm to trade")
	assert_false(panel._confirm.disabled)


func test_both_players_equipment_shows_under_the_grids():
	_in_game()
	state.local.inventory.put(0, {"itemId": 100})
	var theirs: Array = []
	theirs.resize(Inventory.SIZE)
	theirs.fill({"itemId": -1})
	theirs[0] = {"itemId": 102}
	theirs[2] = {"itemId": 300}
	state.apply_packet("AcceptTradeRequestPacket", {"accepted": true,
		"player0": WireHelper.player(9, "Ruu", Vector2.ZERO), "player1": WireHelper.player(4, "Mingau", Vector2.ZERO),
		"player0Inv": [], "player1Inv": theirs})
	panel._process(0.0)
	assert_eq(panel._my_gear.size(), Inventory.EQUIPMENT_SLOTS)
	assert_eq(panel._their_gear.size(), Inventory.EQUIPMENT_SLOTS)
	assert_eq(int(panel._my_gear[0].item.get("itemId", -1)), 100, "our weapon")
	assert_eq(int(panel._their_gear[0].item.get("itemId", -1)), 102, "their weapon")
	assert_eq(int(panel._their_gear[2].item.get("itemId", -1)), 300, "their armour")
	assert_false(Inventory.holds(panel._their_gear[1].item), "an empty slot stays empty")
	for slot in panel._my_gear + panel._their_gear:
		assert_eq(slot.mouse_filter, Control.MOUSE_FILTER_PASS, "read-only, but hovers")
	var gear_box: Node = panel._their_gear[0].get_parent().get_parent()
	var grid_box: Node = panel._theirs[0].get_parent()
	assert_gt(gear_box.get_index(), grid_box.get_index(), "below the trade grid")


func test_hovering_any_slot_with_an_item_shows_its_card():
	_in_game()
	state.local.inventory.put(0, {"itemId": 100})
	_open()
	panel._process(0.0)
	for slot in [panel._theirs[0], panel._my_gear[0]]:
		panel._on_hover(slot, true)
		assert_true(panel._tooltip.visible, "slot %d" % slot.index)
		panel._on_hover(slot, false)
		assert_false(panel._tooltip.visible)
	panel._on_hover(panel._their_gear[1], true)
	assert_false(panel._tooltip.visible, "nothing to show for an empty slot")


func test_a_click_on_our_slot_puts_it_on_the_table_and_sends_the_selection():
	_in_game()
	state.local.inventory.put(5, {"itemId": 310, "stackCount": 2, "stackable": true})
	_open()
	panel._process(0.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel._on_slot_input(5, click)
	panel._process(0.0)
	assert_eq(panel._mine[0].self_modulate, TradePanel.SELECTED)
	var packets := _sent()
	assert_eq(packets.size(), 1)
	assert_eq(packets[0]["name"], "UpdatePlayerTradeSelectionPacket")
	var selection: Dictionary = packets[0]["data"]["selection"]
	assert_eq(int(selection["playerId"]), 9)
	assert_eq(selection["selection"].size(), 20)
	assert_true(selection["selection"][0])
	assert_false(selection["confirmed"])
	# Confirm and cancel go as commands; confirm is refused once confirmed.
	transport.clear_sent()
	assert_true(actions.confirm())
	assert_string_contains(_sent()[0]["data"]["command"], "confirm")
	state.apply_packet("UpdateTradePacket", {"selections": {
		"player0Selection": {"playerId": 9, "selection": [true], "itemRefs": [], "confirmed": true},
		"player1Selection": {"playerId": 4, "selection": [], "itemRefs": [], "confirmed": false}}})
	panel._process(0.0)
	assert_eq(panel._confirm.text, "Confirmed")
	assert_true(panel._confirm.disabled)
	assert_eq(panel._status.text, "Waiting for Mingau to confirm")


func test_nothing_is_sent_outside_a_realm():
	assert_false(actions.request("Mingau"))
	assert_false(actions.accept())
	assert_false(actions.toggle(5))
	assert_false(actions.request("   "), "no name, no request")
	assert_false(actions.confirm(), "no trade to confirm")
	assert_false(panel.captures_mouse())
	assert_false(popup.captures_mouse())


func test_a_request_goes_out_as_an_interaction_action():
	_in_game()
	assert_true(actions.request("Mingau"))
	assert_eq(WireHelper.interaction_actions(transport), ["TRADE REQUEST Mingau"])
