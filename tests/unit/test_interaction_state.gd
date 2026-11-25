extends GutTest

## Trade/party/PvP requests and what became of them, as InteractionPacket drives
## them: prompts per kind with the server's time limit, and short-lived notices
## that never pass through the chat.

var state: RealmState
var now := 10_000


func before_each():
	now = 10_000
	state = RealmState.new(null, func() -> int: return now)


func _event(kind: int, event: int, other := "", detail := "", duration := 0) -> void:
	state.apply_packet("InteractionPacket", WireHelper.interaction(kind, event, other, detail, duration))


func _texts() -> Array:
	return state.interactions.notices.map(func(n: Dictionary) -> String: return n["text"])


func test_a_request_stands_for_the_servers_duration_one_per_kind():
	_event(Interaction.Kind.TRADE, Interaction.Event.REQUESTED, "Mingau", "", 15_000)
	_event(Interaction.Kind.PVP, Interaction.Event.REQUESTED, "Zed", "", 30_000)
	assert_eq(state.interactions.request_from(Interaction.Kind.TRADE), "Mingau")
	assert_eq(state.interactions.request_from(Interaction.Kind.PVP), "Zed")
	assert_eq(state.interactions.request_from(Interaction.Kind.PARTY), "")
	now += 14_999
	state.interactions.expire()
	assert_eq(state.interactions.request_from(Interaction.Kind.TRADE), "Mingau", "still standing")
	now += 1
	state.interactions.expire()
	assert_eq(state.interactions.request_from(Interaction.Kind.TRADE), "", "the server's limit")
	assert_eq(state.interactions.request_from(Interaction.Kind.PVP), "Zed", "its own limit")
	assert_eq(_texts(), [], "a request is a prompt, not a notice")


func test_closed_or_a_started_match_takes_the_prompt_down():
	_event(Interaction.Kind.PARTY, Interaction.Event.REQUESTED, "Zed", "", 60_000)
	_event(Interaction.Kind.PARTY, Interaction.Event.CLOSED)
	assert_eq(state.interactions.request_from(Interaction.Kind.PARTY), "")
	_event(Interaction.Kind.PVP, Interaction.Event.REQUESTED, "Zed", "", 30_000)
	_event(Interaction.Kind.PVP, Interaction.Event.STARTED, "Zed")
	assert_eq(state.interactions.request_from(Interaction.Kind.PVP), "")


func test_events_read_as_notices_and_a_failure_as_its_reason():
	_event(Interaction.Kind.TRADE, Interaction.Event.DECLINED, "Mingau")
	_event(Interaction.Kind.PARTY, Interaction.Event.DISBANDED)
	_event(Interaction.Kind.PVP, Interaction.Event.FAILED, "", "Zed is already in a PvP match.")
	assert_eq(_texts(), ["Mingau declined your trade.", "Your party has disbanded.", "Zed is already in a PvP match."])
	assert_true(state.interactions.notices[2]["failed"])
	assert_false(state.interactions.notices[0]["failed"])
	_event(Interaction.Kind.TRADE, Interaction.Event.CLOSED)
	assert_eq(_texts().size(), 3, "closing a prompt says nothing")


func test_nothing_reaches_the_chat():
	_event(Interaction.Kind.TRADE, Interaction.Event.CANCELLED, "Mingau")
	_event(Interaction.Kind.PVP, Interaction.Event.WON, "Zed")
	assert_eq(state.chat.lines, [])


func test_notices_fade_and_only_the_latest_few_stand():
	for i in InteractionState.MAX_NOTICES + 2:
		_event(Interaction.Kind.PARTY, Interaction.Event.LEFT, "P%d" % i)
	assert_eq(_texts().size(), InteractionState.MAX_NOTICES)
	assert_eq(_texts()[-1], "P%d left the party." % (InteractionState.MAX_NOTICES + 1))
	now += InteractionState.NOTICE_MS
	state.advance(0.016, Vector2.ZERO, 0.0)
	assert_eq(_texts(), [])


func test_the_world_reset_drops_the_prompts():
	_event(Interaction.Kind.TRADE, Interaction.Event.REQUESTED, "Mingau", "", 15_000)
	state.reset_world()
	assert_eq(state.interactions.request_from(Interaction.Kind.TRADE), "")


func test_the_notice_view_draws_the_lines():
	var view := InteractionNotices.new()
	view.setup(state)
	add_child_autofree(view)
	_event(Interaction.Kind.TRADE, Interaction.Event.COMPLETED, "Mingau")
	view._process(0.0)
	assert_eq(view.lines(), ["Trade with Mingau complete."])


func test_cancel_on_an_open_trade_leaves_it_and_on_a_request_declines_it():
	var transport := FakeTransport.new()
	var client := GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	transport.clear_sent()
	var actions := TradeActions.new(state, client)
	assert_true(actions.decline())
	state.apply_packet("AcceptTradeRequestPacket", {"accepted": true,
		"player0": WireHelper.player(9, "Ruu", Vector2.ZERO), "player1": WireHelper.player(4, "Mingau", Vector2.ZERO),
		"player0Inv": [], "player1Inv": []})
	assert_true(actions.decline())
	assert_eq(WireHelper.interaction_actions(transport), ["TRADE DECLINE", "TRADE LEAVE"])
