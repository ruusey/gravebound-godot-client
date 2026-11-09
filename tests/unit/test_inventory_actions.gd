extends GutTest

## Gestures on the bag, and the packets they become.

var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var actions: InventoryActions
var content: GameData


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	# Class 2: a wizard, who wields the fixture's wand and not its bow.
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	transport.clear_sent()
	actions = InventoryActions.new(state, client, content)


func _put(slot: int, item_id: int, extra := {}) -> void:
	var item := content.item_definition(item_id).duplicate()
	item.merge(extra, true)
	state.local.inventory.put(slot, item)


func _bag_at_feet(items: Array) -> void:
	state.entities.apply_load({"containers": [{"lootContainerId": 3, "uid": "", "isChest": false,
		"tier": 0, "items": items, "pos": {"x": 4.0, "y": 0.0}, "spawnedTime": 0,
		"contentsChanged": false, "soulboundPlayerId": 0}]})


func _sent() -> Array:
	return transport.sent_packets()


## The one packet sent, or nothing.
func _only() -> Dictionary:
	var packets := _sent()
	assert_eq(packets.size(), 1, "exactly one packet")
	return packets[0] if packets.size() == 1 else {}


func _move(target: int, from: int, drop: bool, consume: bool) -> void:
	var packet := _only()
	assert_eq(packet.get("name", ""), "MoveItemPacket")
	var data: Dictionary = packet.get("data", {})
	assert_eq(int(data.get("targetSlotIndex", 99)), target, "target")
	assert_eq(int(data.get("fromSlotIndex", 99)), from, "from")
	assert_eq(bool(data.get("drop", not drop)), drop, "drop")
	assert_eq(bool(data.get("consume", not consume)), consume, "consume")


# --- moving --------------------------------------------------------------

func test_a_move_between_backpack_slots_is_sent_as_is():
	_put(5, 200)
	assert_true(actions.move(5, 6))
	_move(6, 5, false, false)


func test_a_move_to_the_same_slot_or_from_an_empty_one_is_nothing():
	_put(5, 200)
	assert_false(actions.move(5, 5))
	assert_false(actions.move(6, 5))
	assert_false(actions.move(5, 60), "nor to a slot that is not a slot")
	assert_eq(_sent().size(), 0)


func test_equipping_checks_the_slot_and_the_class_before_sending():
	_put(5, 102)
	assert_true(actions.move(5, 0), "a wizard's wand into the weapon slot")
	_move(0, 5, false, false)
	transport.clear_sent()
	_put(6, 100)
	assert_false(actions.move(6, 0), "a bow the wizard cannot wield")
	assert_false(actions.move(5, 1), "the wand into the armor slot")
	assert_eq(_sent().size(), 0, "neither is sent to be refused")


func test_unequipping_onto_an_item_checks_what_comes_back():
	# The server swaps, so the backpack item ends up equipped.
	_put(0, 102)
	_put(5, 100)
	assert_false(actions.move(0, 5))
	assert_eq(_sent().size(), 0)
	state.local.inventory.put(5, {})
	assert_true(actions.move(0, 5), "onto an empty slot nothing comes back")
	_move(5, 0, false, false)


func test_swapping_two_equipment_slots_checks_both():
	_put(0, 102)
	_put(1, 103)
	assert_false(actions.move(0, 1), "the wand does not fit the armor slot")
	assert_eq(_sent().size(), 0)


# --- dropping and using ----------------------------------------------------

func test_dropping_is_a_move_to_nowhere():
	_put(5, 200)
	assert_true(actions.drop(5))
	_move(-1, 5, true, false)


func test_the_nowhere_slot_survives_the_wire_as_a_signed_byte():
	# Decoded back off the bytes the fake transport saw, not read from the
	# dictionary we built.
	_put(0, 102)
	actions.drop(0)
	var data: Dictionary = _only().get("data", {})
	assert_eq(int(data["targetSlotIndex"]), -1)


func test_an_empty_slot_cannot_be_dropped():
	assert_false(actions.drop(5))
	assert_eq(_sent().size(), 0)


func test_only_a_consumable_is_consumed():
	_put(5, 200)
	assert_true(actions.consume(5))
	_move(5, 5, false, true)
	transport.clear_sent()
	_put(6, 102)
	assert_false(actions.consume(6))
	assert_eq(_sent().size(), 0)


func test_activating_does_what_the_item_is_for():
	_put(5, 105, {"stackCount": 10})
	assert_true(actions.activate(5))
	var packet := _only()
	assert_eq(packet["name"], "ConsumeShardStackPacket")
	assert_eq(int(packet["data"]["fromSlotIndex"]), 5)
	transport.clear_sent()

	_put(6, 105, {"stackCount": 9})
	assert_false(actions.activate(6), "a short stack is neither forged nor consumed")
	assert_eq(_sent().size(), 0)

	_put(7, 200)
	assert_true(actions.activate(7))
	_move(7, 7, false, true)
	transport.clear_sent()

	_put(8, 102)
	assert_true(actions.activate(8))
	_move(0, 8, false, false)
	transport.clear_sent()

	_put(9, 100)
	assert_false(actions.activate(9), "gear the class cannot wear does nothing")
	_put(0, 102)
	assert_false(actions.activate(0), "and equipment has nowhere to go")
	assert_eq(_sent().size(), 0)


func test_splitting_needs_a_stack_of_at_least_two():
	_put(5, 105, {"stackCount": 4})
	assert_true(actions.split(5))
	var packet := _only()
	assert_eq(packet["name"], "SplitStackPacket")
	assert_eq(int(packet["data"]["fromSlot"]), 5)
	transport.clear_sent()
	_put(6, 105, {"stackCount": 1})
	_put(7, 102)
	assert_false(actions.split(6))
	assert_false(actions.split(7))
	assert_eq(_sent().size(), 0)


# --- the bag at our feet ---------------------------------------------------

func test_picking_up_names_the_loot_slot():
	_bag_at_feet([{"itemId": 100}, {"itemId": -1}, {"itemId": 102}])
	assert_true(actions.pick_up(2))
	_move(Inventory.BACKPACK_START, 47, false, false)
	transport.clear_sent()
	assert_false(actions.pick_up(1), "an empty loot slot")
	assert_false(actions.pick_up(10), "or one past the end")
	assert_eq(_sent().size(), 0)


func test_the_first_thing_in_the_bag():
	assert_false(actions.pick_up_first(), "no bag")
	_bag_at_feet([{"itemId": -1}, {"itemId": 100}])
	assert_true(actions.pick_up_first())
	_move(Inventory.BACKPACK_START, 46, false, false)


func test_a_drag_out_of_the_bag_is_a_pickup_and_a_drag_into_it_is_a_drop():
	_bag_at_feet([{"itemId": 100}])
	assert_true(actions.move(45, 20), "wherever it is dropped")
	_move(Inventory.BACKPACK_START, 45, false, false)
	transport.clear_sent()
	_put(5, 200)
	assert_true(actions.move(5, 46))
	_move(-1, 5, true, false)


func test_item_in_reads_the_bag_and_the_ground_alike():
	_put(5, 200)
	_bag_at_feet([{"itemId": 100}])
	assert_eq(int(actions.item_in(5)["itemId"]), 200)
	assert_eq(int(actions.item_in(45)["itemId"]), 100)
	assert_true(actions.item_in(46).is_empty())
	assert_true(actions.item_in(-3).is_empty())


func test_loot_is_neither_dropped_nor_consumed_where_it_lies():
	_bag_at_feet([{"itemId": 200, "consumable": true}])
	assert_false(actions.drop(45))
	assert_false(actions.consume(45))
	assert_eq(_sent().size(), 0)


func test_drinking_needs_something_in_the_pool():
	assert_false(actions.drink(true))
	assert_eq(_sent().size(), 0)
	state.local.inventory.hp_potions = 2
	assert_true(actions.drink(true))
	_move(-1, Inventory.HP_POTION_SLOT, false, true)
	transport.clear_sent()
	state.local.inventory.mp_potions = 1
	assert_true(actions.drink(false))
	_move(-1, Inventory.MP_POTION_SLOT, false, true)


func test_nothing_is_sent_outside_a_realm():
	_put(5, 200)
	state.local.inventory.hp_potions = 1
	client.stop_playing()
	assert_false(actions.consume(5))
	assert_false(actions.drop(5))
	assert_false(actions.drink(true))
	assert_eq(_sent().size(), 0)
