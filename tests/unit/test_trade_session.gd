extends GutTest

## A trade from its opening to the swap, as the three packets drive it.

var state: RealmState
var now := 10_000
var trade: TradeSession


func before_each():
	now = 10_000
	state = RealmState.new(null, func() -> int: return now)
	state.local.id = 9
	state.local.name = "Ruu"
	trade = state.trade


func _bag(items: Array) -> Array:
	var out: Array = []
	out.resize(Inventory.SIZE)
	out.fill({"itemId": -1})
	for i in items.size():
		out[Inventory.BACKPACK_START + i] = items[i]
	return out


func _open(we_are_first := true) -> void:
	var us := WireHelper.player(9, "Ruu", Vector2.ZERO)
	var them := WireHelper.player(4, "Mingau", Vector2(64, 0))
	var theirs := _bag([{"itemId": 105, "stackCount": 3, "stackable": true}, {"itemId": 300}])
	state.apply_packet("AcceptTradeRequestPacket", {"accepted": true,
		"player0": us if we_are_first else them, "player1": them if we_are_first else us,
		"player0Inv": _bag([]) if we_are_first else theirs, "player1Inv": theirs if we_are_first else _bag([])})


func _selections(mine_flags: Array, mine_confirmed: bool, their_flags: Array, their_confirmed: bool) -> void:
	state.apply_packet("UpdateTradePacket", {"selections": {
		"player0Selection": {"playerId": 9, "selection": mine_flags, "itemRefs": [], "confirmed": mine_confirmed},
		"player1Selection": {"playerId": 4, "selection": their_flags, "itemRefs": [], "confirmed": their_confirmed}}})


func test_an_accepted_trade_opens_with_the_partner_and_their_bag_whichever_side_we_are():
	_open(true)
	assert_true(trade.active)
	assert_eq(trade.partner_name, "Mingau")
	assert_eq(trade.partner_id, 4)
	assert_eq(int(trade.partner_item(5)["itemId"]), 105, "their first page slot")
	assert_eq(trade.partner_item(6), {"itemId": 300})
	assert_eq(trade.partner_item(99), {}, "off the end")
	assert_eq(trade.my_selected.size(), 20)
	assert_false(trade.my_selected.any(func(f: bool) -> bool: return f), "nothing on the table")
	trade.clear()
	_open(false)
	assert_eq(trade.partner_name, "Mingau", "we were player1 this time")
	assert_eq(int(trade.partner_item(5)["itemId"]), 105)


func test_toggling_a_page_slot_and_the_packet_it_becomes():
	_open()
	assert_true(trade.toggle(5))
	assert_true(trade.toggle(24))
	assert_false(trade.toggle(4), "equipment is not on the table")
	assert_false(trade.toggle(25), "nor the second page")
	assert_true(trade.my_selected[0])
	assert_true(trade.my_selected[19])
	var packet := TradeStatus.selection_packet(9, trade.my_selected)
	assert_eq(int(packet["selection"]["playerId"]), 9)
	assert_eq(packet["selection"]["selection"].size(), 20)
	assert_true(packet["selection"]["selection"][0])
	assert_eq(packet["selection"]["itemRefs"], [])
	assert_false(packet["selection"]["confirmed"], "a change always un-confirms")
	assert_true(trade.toggle(5))
	assert_false(trade.my_selected[0], "off again")
	trade.clear()
	assert_false(trade.toggle(5), "nothing to put anything on")


func test_the_servers_selections_drive_the_status_line():
	_open()
	assert_eq(trade.status(), "Selecting items")
	_selections([true, false], false, [false, true], true)
	assert_true(trade.partner_selected(1))
	assert_false(trade.partner_selected(0))
	assert_false(trade.partner_selected(40), "past what they sent")
	assert_eq(trade.status(), "Mingau confirmed - confirm to trade")
	_selections([true], true, [true], false)
	assert_eq(trade.status(), "Waiting for Mingau to confirm")
	state.apply_packet("UpdatePlayerTradeSelectionPacket", {"selection": {"playerId": 4, "selection": [true], "itemRefs": [], "confirmed": true}})
	assert_eq(trade.status(), "Trade confirmed!")
	assert_true(trade.toggle(6))
	assert_false(trade.my_confirmed(), "our own change un-confirms us before the server says so")


func test_a_close_while_open_is_held_a_second_and_then_gone():
	_open()
	_selections([true], true, [true], false)
	state.apply_packet("AcceptTradeRequestPacket", {"accepted": false, "player0": {}, "player1": {}, "player0Inv": [], "player1Inv": []})
	assert_true(trade.active, "still on screen")
	assert_true(trade.closing())
	assert_eq(trade.status(), "Trade confirmed!", "both sides shown confirmed for the hold")
	assert_false(trade.toggle(5), "nothing changes during the hold")
	now += TradeSession.CLOSING_HOLD_MS - 1
	trade.expire()
	assert_true(trade.active)
	now += 1
	trade.expire()
	assert_false(trade.active)
	assert_eq(trade.partner_name, "")


func test_a_decline_before_anything_opened_just_clears():
	state.apply_packet("AcceptTradeRequestPacket", {"accepted": false, "player0": {}, "player1": {}, "player0Inv": [], "player1Inv": []})
	assert_false(trade.active)
	assert_false(trade.closing())


func test_it_goes_with_the_world():
	_open()
	state.reset_world()
	assert_false(trade.active)
