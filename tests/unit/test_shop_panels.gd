extends GutTest

## The potion storage, the fame store and the prompt, on screen.

var state: RealmState
var content: GameData
var client: GraveBoundClient
var transport: FakeTransport
var shop: ShopActions
var actions: InventoryActions
var store: ItemStorePanel
var fame: FameStorePanel
var market: ExchangeMarketPanel
var prompt: InteractPrompt


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	shop = ShopActions.new(state, client, content)
	actions = InventoryActions.new(state, client, content)
	actions.shop = shop
	store = ItemStorePanel.new()
	store.setup(state, content, actions, shop)
	add_child_autofree(store)
	fame = FameStorePanel.new()
	fame.setup(state, content, shop)
	add_child_autofree(fame)
	market = ExchangeMarketPanel.new()
	market.setup(state, content, shop)
	add_child_autofree(market)
	prompt = InteractPrompt.new()
	prompt.setup(state, shop)
	add_child_autofree(prompt)


func _enter() -> void:
	state.local.id = 9
	state.local.class_id = 2
	state.local.position = Vector2(5 * 32, 5 * 32)


func _in_game() -> void:
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 2, Vector2(5 * 32, 5 * 32)))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	transport.clear_sent()


func _open_store(items: Array) -> void:
	var shelves: Array = []
	shelves.resize(ItemStore.SIZE)
	shelves.fill({"itemId": -1})
	for i in items.size():
		shelves[i] = items[i]
	state.apply_packet("OpenItemStorePacket", {"storeKind": 0, "playerId": 9, "items": shelves})


func _names() -> Array:
	var out: Array = []
	for packet in transport.sent_packets():
		out.append(packet["name"])
	return out


# --- the shelves -------------------------------------------------------------

func test_the_store_shows_when_the_server_opens_it_and_goes_when_closed():
	_enter()
	store._process(0.0)
	assert_false(store.visible)
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4}])
	store._process(0.0)
	assert_true(store.visible)
	assert_eq(store._slots.size(), 32)
	assert_eq(store._slots[0].index, ItemStore.SLOT_BASE)
	assert_eq(store._slots[31].index, ItemStore.SLOT_BASE + 31)
	assert_not_null(store._slots[0]._icon.texture)
	assert_eq(store._slots[0]._count.text, "x4")
	assert_null(store._slots[1]._icon.texture)
	state.store.close()
	store._process(0.0)
	assert_false(store.visible)


func test_an_update_redraws_the_shelves():
	_enter()
	_open_store([])
	store._process(0.0)
	assert_null(store._slots[3]._icon.texture)
	state.apply_packet("ItemStoreUpdatePacket", {"storeKind": 0, "playerId": 9,
		"items": [{"itemId": -1}, {"itemId": -1}, {"itemId": -1}, {"itemId": 200}]})
	store._process(0.0)
	assert_not_null(store._slots[3]._icon.texture)


func test_shelf_gestures_reach_the_server():
	_in_game()
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4}])
	state.local.inventory.put(5, content.item_definition(105).duplicate())
	store._process(0.0)
	store._slots[0].activated.emit(ItemStore.SLOT_BASE)
	store._slots[0].secondary.emit(ItemStore.SLOT_BASE, false)
	store._slots[2].dropped.emit(5, ItemStore.SLOT_BASE + 2)
	assert_eq(_names(), ["ItemStoreMovePacket", "ItemStoreMovePacket", "ItemStoreMovePacket"])
	var data: Dictionary = transport.sent_packets()[2]["data"]
	assert_eq(int(data["fromSide"]), ItemStore.SIDE_INVENTORY)
	assert_eq(int(data["toIdx"]), 2)


func test_the_card_opens_over_a_shelf_item():
	_enter()
	_open_store([{"itemId": 105, "stackable": true, "stackCount": 4, "name": "Vit Crystal Shard"}])
	store._process(0.0)
	store._slots[0].hovered.emit(ItemStore.SLOT_BASE, true)
	assert_true(store._tooltip.visible)
	assert_string_contains(store._tooltip._lines.get_child(0).text, "Vit Crystal Shard")
	store._slots[1].hovered.emit(ItemStore.SLOT_BASE + 1, true)
	assert_false(store._tooltip.visible)


func test_a_bag_right_click_stashes_while_the_store_is_open():
	_in_game()
	var bag := InventoryPanel.new()
	bag.setup(state, content, actions)
	add_child_autofree(bag)
	state.local.inventory.put(5, content.item_definition(105).duplicate())
	_open_store([])
	bag._process(0.0)
	bag._backpack[0].secondary.emit(5, false)
	assert_eq(_names(), ["ItemStoreMovePacket"], "a stash, not a drop")
	transport.clear_sent()
	state.store.close()
	bag._backpack[0].secondary.emit(5, false)
	assert_eq(_names(), ["MoveItemPacket"], "closed, the right-click drops again")


func test_the_store_panel_owns_no_mouse_while_hidden():
	assert_false(store.captures_mouse())
	assert_false(fame.captures_mouse())


# --- the fame store ----------------------------------------------------------

func test_the_fame_store_lists_the_catalogue_with_the_balance():
	_enter()
	fame._process(0.0)
	assert_false(fame.visible)
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 120})
	fame._process(0.0)
	assert_true(fame.visible)
	assert_string_contains(fame._balance.text, "120")
	assert_eq(fame._rows.size(), 2, "the two priced items the fixture knows")
	assert_eq(fame._rows[0]["item_id"], 200, "cheapest first")
	assert_false(fame._rows[0]["button"].disabled, "100 fame, 120 held")
	assert_true(fame._rows[1]["button"].disabled, "500 fame")
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 20})
	fame._process(0.0)
	assert_true(fame._rows[0]["button"].disabled, "after a purchase the new balance disables it")
	state.fame.close()
	fame._process(0.0)
	assert_false(fame.visible)


func test_a_buy_button_sends_the_purchase():
	_in_game()
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 1000})
	fame._process(0.0)
	fame._rows[1]["button"].pressed.emit()
	assert_eq(_names(), ["BuyFameItemPacket"])
	assert_eq(int(transport.sent_packets()[0]["data"]["itemId"]), 104)


func test_the_rows_wait_for_content_and_carry_a_card():
	_enter()
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 1000})
	fame._process(0.0)
	fame._rows[0]["button"].get_parent().mouse_entered.emit()
	assert_true(fame._tooltip.visible)
	assert_string_contains(fame._tooltip._lines.get_child(0).text, "Health Potion")
	fame._rows[0]["button"].get_parent().mouse_exited.emit()
	assert_false(fame._tooltip.visible)


# --- the prompt --------------------------------------------------------------

func test_the_prompt_names_the_tile_in_reach():
	_enter()
	prompt._process(0.0)
	assert_false(prompt.visible)
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(301, 1, 6, 5)]})
	prompt._process(0.0)
	assert_true(prompt.visible)
	assert_eq(prompt._label.text, "Open Fame Store (F)")
	state.local.position = Vector2(20 * 32, 20 * 32)
	prompt._process(0.0)
	assert_false(prompt.visible)


func test_the_prompt_is_silent_outside_a_realm():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(301, 1, 6, 5)]})
	state.local.position = Vector2(5 * 32, 5 * 32)
	prompt._process(0.0)
	assert_false(prompt.visible, "no local player yet")
	var bare := InteractPrompt.new()
	add_child_autofree(bare)
	bare._process(0.0)
	assert_false(bare.visible)


# --- the exchange market -----------------------------------------------------

func _stock(index: int, item_id: int, count: int) -> void:
	state.local.inventory.put(index, {"itemId": item_id, "stackCount": count, "stackable": true})


func test_the_market_lists_what_you_hold_and_what_it_swaps_for():
	_enter()
	_stock(5, 310, 5)
	_stock(6, 105, 3)
	market._process(0.0)
	assert_false(market.visible)
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	market._process(0.0)
	assert_true(market.visible)
	assert_eq(market._rows["give"].map(func(r: Dictionary) -> int: return r["item_id"]), [105, 310], "by id")
	assert_string_contains(market._rows["give"][1]["button"].text, "x5")
	assert_eq(market._rows["receive"], [])
	assert_eq(market._summary.text, "Select an item to give and one to receive.")
	assert_true(market._confirm.disabled)

	market._rows["give"][1]["button"].pressed.emit()
	market._process(0.0)
	assert_true(market._rows["give"][1]["button"].button_pressed, "stays down while chosen")
	assert_eq(market._rows["receive"].map(func(r: Dictionary) -> int: return r["item_id"]), [311], "the other essence")
	market._rows["receive"][0]["button"].pressed.emit()
	market._process(0.0)
	assert_eq(market._summary.text, "2 Weapon Essence -> 1 Armor Essence")
	assert_false(market._confirm.disabled)
	assert_eq(market._count.text, "2")

	market._rows["give"][0]["button"].pressed.emit()
	market._process(0.0)
	assert_eq(market._rows["receive"], [], "the only shard has nothing to swap for")
	assert_eq(market._receive.get_child_count(), 1, "and says so")
	state.market.close()
	market._process(0.0)
	assert_false(market.visible)


func test_the_counter_runs_from_two_to_what_you_hold():
	_enter()
	_stock(5, 310, 5)
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	market._process(0.0)
	market._rows["give"][0]["button"].pressed.emit()
	market._process(0.0)
	market._rows["receive"][0]["button"].pressed.emit()
	market._adjust(999_999)
	market._process(0.0)
	assert_eq(market._count.text, "5", "Max")
	assert_eq(market._summary.text, "5 Weapon Essence -> 4 Armor Essence")
	market._adjust(-1)
	market._adjust(-1)
	market._process(0.0)
	assert_eq(market._count.text, "3")
	for i in 5:
		market._adjust(-1)
	market._process(0.0)
	assert_eq(market._count.text, "2", "never under two")


func test_exchange_sends_the_request_and_a_swap_answered_rebuilds_the_rows():
	_in_game()
	_stock(5, 310, 5)
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	market._process(0.0)
	market._rows["give"][0]["button"].pressed.emit()
	market._process(0.0)
	market._rows["receive"][0]["button"].pressed.emit()
	market._adjust(1)
	market._process(0.0)
	market._confirm.pressed.emit()
	assert_eq(_names(), ["ExchangeItemsPacket"])
	assert_eq(transport.sent_packets()[0]["data"], {"sourceItemId": 310, "targetItemId": 311, "quantity": 3})
	# The server's answer: the essence is gone and the other has arrived.
	state.local.inventory.put(5, {"itemId": -1})
	_stock(6, 311, 2)
	market._process(0.0)
	assert_eq(market._rows["give"].map(func(r: Dictionary) -> int: return r["item_id"]), [311])
	assert_eq(state.market.source, -1, "a stack given away entirely is no longer a choice")
	assert_true(market._confirm.disabled)


func test_the_market_shows_a_card_and_owns_no_mouse_while_hidden():
	_enter()
	assert_false(market.captures_mouse())
	_stock(5, 310, 5)
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": 9})
	market._process(0.0)
	market._rows["give"][0]["button"].get_parent().mouse_entered.emit()
	assert_true(market._tooltip.visible)
	market._rows["give"][0]["button"].get_parent().mouse_exited.emit()
	assert_false(market._tooltip.visible)
