extends GutTest

## The exchange market's rules: what is of a kind, what is held, what a
## request needs -- the server's, mirrored so only legal swaps are offered.

var content: GameData
var state: RealmState
var market: ExchangeMarket


func before_each():
	content = GameData.new()
	content.library.items = {
		800: {"name": "Vit Shard", "category": "shard", "stackable": true},
		801: {"name": "Wis Shard", "category": "shard", "stackable": true},
		808: {"name": "Vit Crystal", "category": "crystal"},
		809: {"name": "Wis Crystal", "category": "crystal"},
		816: {"name": "Weapon Essence", "category": "essence", "stackable": true},
		0: {"name": "Potion of Defense", "category": "generic", "consumable": true, "stackable": true},
		1: {"name": "Potion of Attack", "category": "generic", "consumable": true, "stackable": true},
		200: {"name": "Health Potion", "category": "generic", "consumable": true},
		100: {"name": "Short Bow", "category": "weapon"},
		320: {"name": "Crit Gem", "category": "gem"},
	}
	state = RealmState.new(content, func() -> int: return 0)
	state.local.id = 9
	market = state.market


func _hold(index: int, item_id: int, count := 1) -> void:
	var item := {"itemId": item_id, "stackCount": count,
		"stackable": bool(content.item_definition(item_id).get("stackable", false))}
	state.local.inventory.put(index, item)


# --- kinds -------------------------------------------------------------------

func test_a_shard_a_crystal_and_an_essence_are_each_their_own_kind():
	assert_eq(ExchangeMarket.group_key(content.item_definition(800)), "shard")
	assert_eq(ExchangeMarket.group_key(content.item_definition(808)), "crystal")
	assert_eq(ExchangeMarket.group_key(content.item_definition(816)), "essence")


func test_a_stat_potion_is_a_kind_and_a_heal_potion_is_not():
	# Both are generic consumables; only the stackable one is a stat potion.
	assert_eq(ExchangeMarket.group_key(content.item_definition(0)), "stat_potion")
	assert_eq(ExchangeMarket.group_key(content.item_definition(200)), "", "the heal potion does not stack")


func test_everything_else_cannot_be_exchanged():
	assert_eq(ExchangeMarket.group_key(content.item_definition(100)), "", "a weapon")
	assert_eq(ExchangeMarket.group_key(content.item_definition(320)), "", "a gem")
	assert_eq(ExchangeMarket.group_key({}), "", "nothing")


func test_what_could_be_received_is_the_rest_of_the_kind_by_id():
	assert_eq(ExchangeMarket.members(content, 800), [801])
	assert_eq(ExchangeMarket.members(content, 1), [0], "the other stat potion, not the heal potion")
	assert_eq(ExchangeMarket.members(content, 816), [], "the only essence")
	assert_eq(ExchangeMarket.members(content, 100), [], "not exchangeable at all")
	assert_eq(ExchangeMarket.members(null, 800), [])


# --- what is held ------------------------------------------------------------

func test_what_is_held_is_counted_across_the_backpack_by_stack():
	_hold(5, 800, 4)
	_hold(6, 800, 3)
	_hold(7, 808)
	_hold(8, 808)
	_hold(9, 100)
	assert_eq(ExchangeMarket.owned(state.local.inventory, content),
		{800: 7, 808: 2}, "stacks add up, singles count one each, the bow is not offered")


func test_the_equipment_is_not_offered():
	_hold(0, 800, 5)
	_hold(44, 800, 2)
	assert_eq(ExchangeMarket.owned(state.local.inventory, content), {800: 2}, "the last backpack slot only")
	assert_eq(ExchangeMarket.owned(state.local.inventory, null), {})


# --- the choice --------------------------------------------------------------

func test_choosing_what_to_give_drops_what_was_to_be_received():
	market.select_source(800, 7)
	market.select_target(801)
	assert_eq(market.target, 801)
	market.select_source(808, 2)
	assert_eq(market.target, -1, "a crystal is not swapped for a shard")


func test_the_quantity_stays_between_two_and_what_is_held():
	market.select_source(800, 7)
	market.set_quantity(1, 7)
	assert_eq(market.quantity, 2)
	market.set_quantity(100, 7)
	assert_eq(market.quantity, 7)
	market.set_quantity(5, 7)
	assert_eq(market.quantity, 5)
	market.select_source(801, 3)
	assert_eq(market.quantity, 3, "clamped to the new stack")
	market.set_quantity(5, 0)
	assert_eq(market.quantity, 2, "two when nothing is held, so the counter still reads")


func test_a_request_needs_both_sides_and_enough_held():
	assert_false(market.ready(9), "nothing chosen")
	market.select_source(800, 9)
	assert_false(market.ready(9), "nothing to receive")
	market.select_target(801)
	assert_true(market.ready(9))
	assert_false(market.ready(1), "one is not enough: one is the tax")
	market.set_quantity(9, 9)
	assert_false(market.ready(8), "a stack that shrank under the quantity")
	assert_eq(ExchangeMarket.output(9), 8, "one lost")


func test_worth_converts_after_the_tax():
	assert_eq(ExchangeMarket.output(6, 1, 5), 1, "five regular potions buy one life")
	assert_eq(ExchangeMarket.output(5, 1, 5), 0, "the tax leaves too few")
	assert_eq(ExchangeMarket.output(2, 5, 1), 5, "one life is worth five")
	assert_eq(ExchangeMarket.minimum(1, 5), 6)
	assert_eq(ExchangeMarket.minimum(5, 1), 2)
	assert_eq(ExchangeMarket.minimum(1, 1), 2)


# --- opening and closing -----------------------------------------------------

func test_the_server_opens_it_for_us_and_not_for_anyone_else():
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 3})
	assert_false(market.is_open)
	market.select_source(800, 5)
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	assert_true(market.is_open)
	assert_eq(market.source, -1, "opened fresh")
	assert_eq(market.quantity, 2)
	var seen := market.version
	market.close()
	assert_false(market.is_open)
	assert_gt(market.version, seen)


func test_it_goes_with_the_world():
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	state.reset_world()
	assert_false(market.is_open)


func test_leaving_the_region_shuts_it():
	# In a realm, with the market open...
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 31, "tiles": []})
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	assert_true(market.is_open)
	# ...a portal/nexus/vault move (a new realm's LoadMapPacket) shuts it so it
	# can't follow you out of the region still usable.
	state.apply_packet("LoadMapPacket", {"realmId": 2, "mapId": 31, "tiles": []})
	assert_false(market.is_open)


# --- the request -------------------------------------------------------------

func test_the_request_carries_the_choice_and_only_when_legal():
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
	state.local.enter_realm(client.login_response)
	transport.clear_sent()
	var shop := ShopActions.new(state, client, content)
	_hold(5, 800, 6)
	assert_false(shop.exchange(), "not open")
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	market.select_source(800, 6)
	assert_false(shop.exchange(), "nothing to receive")
	market.select_target(801)
	market.set_quantity(4, 6)
	assert_true(shop.exchange())
	var sent := transport.sent_packets()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["name"], "ExchangeItemsPacket")
	assert_eq(sent[0]["data"], {"sourceItemId": 800, "targetItemId": 801, "quantity": 4})
	_hold(5, 800, 3)
	assert_false(shop.exchange(), "the stack shrank under the quantity: the server would refuse")
