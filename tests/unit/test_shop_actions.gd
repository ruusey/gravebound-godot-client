extends GutTest

## What the player does at a tile and in the panels it opens, as packets.

var state: RealmState
var content: GameData
var client: GraveBoundClient
var transport: FakeTransport
var shop: ShopActions
var actions: InventoryActions


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
	transport.deliver(WireHelper.login_response(9, 2, Vector2(5 * 32, 5 * 32)))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	transport.clear_sent()
	shop = ShopActions.new(state, client, content)
	actions = InventoryActions.new(state, client, content)
	actions.shop = shop


func _open_store(items: Array) -> void:
	var shelves: Array = []
	shelves.resize(ItemStore.SIZE)
	shelves.fill({"itemId": -1})
	for i in items.size():
		shelves[i] = items[i]
	state.apply_packet("OpenItemStorePacket", {"storeKind": 0, "playerId": 9, "items": shelves})


func _put(slot: int, item_id: int, extra := {}) -> void:
	var item := content.item_definition(item_id).duplicate()
	item.merge(extra, true)
	state.local.inventory.put(slot, item)


func _sent() -> Array:
	return transport.sent_packets()


func _only(name: String) -> Dictionary:
	var packets := _sent()
	assert_eq(packets.size(), 1, "exactly one packet")
	if packets.size() != 1:
		return {}
	assert_eq(packets[0]["name"], name)
	return packets[0]["data"]


func _store_move(from_side: int, from_idx: int, to_side: int, to_idx: int) -> void:
	var data := _only("ItemStoreMovePacket")
	assert_eq(int(data.get("storeKind", -9)), 0)
	assert_eq(int(data.get("fromSide", -9)), from_side, "fromSide")
	assert_eq(int(data.get("fromIdx", -9)), from_idx, "fromIdx")
	assert_eq(int(data.get("toSide", -9)), to_side, "toSide")
	assert_eq(int(data.get("toIdx", -9)), to_idx, "toIdx")


# --- the tile ----------------------------------------------------------------

func test_f_uses_the_tile_in_reach():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(300, 1, 6, 5)]})
	assert_true(shop.interact_nearby())
	var data := _only("InteractTilePacket")
	assert_eq(int(data["tileX"]), 6)
	assert_eq(int(data["tileY"]), 5)


func test_no_tile_in_reach_sends_nothing_so_f_falls_through_to_the_bag():
	assert_false(shop.interact_nearby())
	assert_eq(_sent().size(), 0)
	var input := InventoryInput.new(client, actions, InventoryPanel.new())
	input.shop = shop
	state.entities.apply_load({"containers": [{"lootContainerId": 3, "uid": "", "isChest": false,
		"tier": 0, "items": [{"itemId": 100}], "pos": {"x": 5 * 32 + 4.0, "y": 5 * 32.0},
		"spawnedTime": 0, "contentsChanged": false, "soulboundPlayerId": 0}]})
	Input.action_press("pick_up")
	input.tick(0.0)
	Input.action_release("pick_up")
	assert_eq(_only("MoveItemPacket").get("fromSlotIndex"), Inventory.GROUND_LOOT_START)


func test_the_tile_comes_before_the_bag_on_f():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(300, 1, 6, 5)]})
	state.entities.apply_load({"containers": [{"lootContainerId": 3, "uid": "", "isChest": false,
		"tier": 0, "items": [{"itemId": 100}], "pos": {"x": 5 * 32 + 4.0, "y": 5 * 32.0},
		"spawnedTime": 0, "contentsChanged": false, "soulboundPlayerId": 0}]})
	var input := InventoryInput.new(client, actions, InventoryPanel.new())
	input.shop = shop
	Input.action_press("pick_up")
	input.tick(0.0)
	Input.action_release("pick_up")
	assert_eq(_sent().size(), 1)
	assert_eq(_sent()[0]["name"], "InteractTilePacket")


# --- the potion store --------------------------------------------------------

func test_a_bag_item_onto_an_empty_shelf():
	_open_store([])
	_put(5, 105, {"stackCount": 3})
	assert_true(actions.move(5, 1002), "through the bag's own move")
	_store_move(ItemStore.SIDE_INVENTORY, 5, ItemStore.SIDE_STORAGE, 2)


func test_the_shelves_keep_stackables_and_gems_only():
	_open_store([])
	_put(5, 102)
	assert_false(shop.move(5, 1000), "a wand")
	assert_false(shop.stash(5))
	assert_eq(_sent().size(), 0)


func test_a_bag_item_onto_an_occupied_shelf_only_when_the_stacks_merge():
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4, "maxStack": 10},
		{"itemId": 200, "stackable": true, "stackCount": 1, "maxStack": 10},
		{"itemId": 105, "stackable": true, "stackCount": 10, "maxStack": 10}])
	_put(5, 105, {"stackCount": 3})
	assert_false(shop.move(5, 1001), "a different item there: the server would refuse to displace it")
	assert_false(shop.move(5, 1002), "the same item, but the stack is full")
	assert_eq(_sent().size(), 0)
	assert_true(shop.move(5, 1000), "the same item with room")
	_store_move(ItemStore.SIDE_INVENTORY, 5, ItemStore.SIDE_STORAGE, 0)


func test_a_shelf_item_onto_the_bag_swaps_freely():
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4}])
	_put(7, 102)
	assert_true(shop.move(1000, 7), "onto an occupied bag slot: storage drags may displace")
	_store_move(ItemStore.SIDE_STORAGE, 0, ItemStore.SIDE_INVENTORY, 7)


func test_between_two_shelves():
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4}])
	assert_true(shop.move(1000, 1017))
	_store_move(ItemStore.SIDE_STORAGE, 0, ItemStore.SIDE_STORAGE, 17)


func test_nothing_moves_while_the_store_is_closed_or_from_nowhere():
	_put(5, 105)
	assert_false(shop.move(5, 1000))
	_open_store([])
	assert_false(shop.move(6, 1000), "an empty bag slot")
	assert_false(shop.move(1000, 1000), "onto itself")
	assert_false(shop.move(5, 50), "a slot that is neither")
	assert_false(shop.move(45, 1000), "a loot slot is not the bag")
	assert_eq(_sent().size(), 0)


func test_a_right_click_stashes_and_lets_the_server_pick_the_shelf():
	_open_store([])
	_put(5, 105, {"stackCount": 3})
	assert_true(actions.stash(5))
	_store_move(ItemStore.SIDE_INVENTORY, 5, ItemStore.SIDE_STORAGE, ItemStore.ANY_SLOT)
	transport.clear_sent()
	state.store.close()
	assert_false(actions.stash(5), "closed: the right-click is a drop again")


func test_a_click_on_a_shelf_takes_it_into_the_first_free_backpack_slot():
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4}])
	_put(5, 200)
	assert_true(shop.take(1000))
	_store_move(ItemStore.SIDE_STORAGE, 0, ItemStore.SIDE_INVENTORY, 6)
	transport.clear_sent()
	assert_false(shop.take(1001), "an empty shelf")
	for i in range(5, 45):
		_put(i, 200)
	assert_false(shop.take(1000), "a full bag")
	assert_eq(_sent().size(), 0)


func test_item_in_reads_both_sides():
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4}])
	_put(5, 200)
	assert_eq(int(shop.item_in(1000)["itemId"]), 105)
	assert_eq(int(shop.item_in(5)["itemId"]), 200)
	assert_true(shop.item_in(1001).is_empty())


# --- the fame store ----------------------------------------------------------

func test_buying_sends_the_item_id_when_the_balance_covers_it():
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 500})
	assert_true(shop.buy(104))
	assert_eq(int(_only("BuyFameItemPacket")["itemId"]), 104)
	transport.clear_sent()
	assert_true(shop.buy(200))
	assert_eq(_sent().size(), 1)


func test_no_purchase_the_server_would_refuse():
	assert_false(shop.buy(200), "the store is not open")
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 99})
	assert_false(shop.buy(200), "100 fame, 99 held")
	assert_false(shop.buy(102), "not for sale")
	assert_eq(_sent().size(), 0)


func test_nothing_is_sent_outside_a_realm():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(300, 1, 6, 5)]})
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4}])
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 500})
	client.stop_playing()
	assert_false(shop.interact_nearby())
	assert_false(shop.take(1000))
	assert_false(shop.buy(200))
	assert_eq(_sent().size(), 0)
