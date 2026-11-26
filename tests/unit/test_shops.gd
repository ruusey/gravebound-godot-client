extends GutTest

## The tiles you use, and the two stores the server opens: their models.

var content: GameData
var state: RealmState


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	state.local.id = 9


func _tile(tile_id: int, x: int, y: int, layer := 1) -> void:
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(tile_id, layer, x, y)]})


func _open_store(items: Array, player_id := 9, kind := 0) -> void:
	state.apply_packet("OpenItemStorePacket", {"storeKind": kind, "playerId": player_id, "items": items})


# --- the tile in reach ------------------------------------------------------

func test_the_nearest_interactive_tile_within_three_tiles():
	_tile(300, 5, 5)          # a forge, on the collision layer
	_tile(301, 7, 5, 0)       # a fame store, on the ground layer
	state.local.position = Vector2(5 * 32 + 4, 5 * 32 + 4)
	var found := TileInteract.nearest(state.tiles, content, state.local.position)
	assert_eq(found.get("type"), "forge")
	assert_eq(found.get("tile_x"), 5)
	assert_eq(found.get("tile_y"), 5)
	state.local.position = Vector2(7 * 32 + 4, 5 * 32 + 4)
	assert_eq(TileInteract.nearest(state.tiles, content, state.local.position).get("type"), "fame_store",
		"either layer counts")


func test_reach_is_three_tiles_from_the_corner_to_the_tile_centre():
	# The server's check, and the web client's: further than that is refused.
	# Diagonally, so both points stay inside the five-by-five window and only
	# the distance decides.
	_tile(300, 5, 5)
	var centre := Vector2(5.5 * 32, 5.5 * 32)
	assert_false(TileInteract.nearest(state.tiles, content, centre + Vector2(2.0 * 32, 2.0 * 32)).is_empty(), "2.83 tiles")
	assert_true(TileInteract.nearest(state.tiles, content, centre + Vector2(2.2 * 32, 2.2 * 32)).is_empty(), "3.11 tiles")


func test_the_window_is_five_by_five_around_the_players_tile():
	_tile(300, 8, 5)
	# Two tiles over is inside the window; three is not, even if in reach by distance.
	assert_false(TileInteract.nearest(state.tiles, content, Vector2(6 * 32 + 30, 5 * 32)).is_empty())
	assert_true(TileInteract.nearest(state.tiles, content, Vector2(5 * 32 + 30, 5 * 32)).is_empty())


func test_nothing_without_content_or_an_interactive_tile():
	# The fixture's grass carries `interactionType: null`, as every shipped
	# floor tile does; a null is not a type, and once it read as one the
	# prompt offered to use the sand.
	_tile(1, 5, 5)
	assert_true(TileInteract.nearest(state.tiles, content, Vector2(5 * 32, 5 * 32)).is_empty())
	assert_true(TileInteract.nearest(state.tiles, null, Vector2(5 * 32, 5 * 32)).is_empty())


func test_the_prompts_words_are_the_web_clients():
	assert_eq(TileInteract.verb({"type": "forge"}), "Use Forge")
	assert_eq(TileInteract.verb({"type": "fame_store"}), "Open Fame Store")
	assert_eq(TileInteract.verb({"type": "potion_storage"}), "Open Potion Storage")
	assert_eq(TileInteract.verb({"type": "exchange_market"}), "Open Exchange Market")
	assert_eq(TileInteract.verb({"type": "vault_chest"}), "Buy Vault Chest")
	assert_eq(TileInteract.verb({"type": "shrine", "name": "Shrine of Might"}), "Use Shrine of Might")


# --- the potion store -------------------------------------------------------

func test_the_store_opens_with_its_shelves():
	_open_store([{"itemId": 200, "stackable": true, "stackCount": 4}, {"itemId": -1}, null])
	assert_true(state.store.is_open)
	assert_eq(state.store.kind, 0)
	assert_eq(int(state.store.item_at(0)["itemId"]), 200)
	assert_true(state.store.item_at(1).is_empty())
	assert_true(state.store.item_at(2).is_empty())
	assert_true(state.store.item_at(31).is_empty())
	assert_true(state.store.item_at(32).is_empty(), "out of range is empty, not an error")
	assert_eq(state.store.first_empty(), 1)


func test_another_players_store_is_not_ours():
	_open_store([{"itemId": 200}], 10)
	assert_false(state.store.is_open)


func test_an_update_replaces_the_shelves_only_while_open_and_for_the_same_kind():
	state.apply_packet("ItemStoreUpdatePacket", {"storeKind": 0, "playerId": 9, "items": [{"itemId": 200}]})
	assert_false(state.store.is_open, "an update does not open a store")
	assert_true(state.store.item_at(0).is_empty())
	_open_store([{"itemId": 200}])
	var version := state.store.version
	state.apply_packet("ItemStoreUpdatePacket", {"storeKind": 1, "playerId": 9, "items": [{"itemId": 201}]})
	assert_eq(int(state.store.item_at(0)["itemId"]), 200, "another kind's update is ignored")
	assert_eq(state.store.version, version)
	state.apply_packet("ItemStoreUpdatePacket", {"storeKind": 0, "playerId": 9, "items": [{"itemId": 201}]})
	assert_eq(int(state.store.item_at(0)["itemId"]), 201)
	assert_gt(state.store.version, version)


func test_closing_and_leaving_the_realm():
	_open_store([{"itemId": 200}])
	state.store.close()
	assert_false(state.store.is_open)
	_open_store([{"itemId": 200}])
	state.reset_world()
	assert_false(state.store.is_open)
	assert_true(state.store.item_at(0).is_empty())


func test_the_store_keeps_stackables_and_gems_only():
	# The server's ItemStoreKind.POTION whitelist.
	assert_true(ItemStore.accepts({"itemId": 1, "stackable": true}))
	assert_true(ItemStore.accepts({"itemId": 1, "category": "gem"}))
	assert_false(ItemStore.accepts({"itemId": 1, "category": "crystal"}))
	assert_false(ItemStore.accepts(content.item_definition(102)), "a wand")


func test_store_slots_live_above_the_bag_in_one_index_space():
	assert_true(ItemStore.is_slot(1000))
	assert_true(ItemStore.is_slot(1031))
	assert_false(ItemStore.is_slot(1032))
	assert_false(ItemStore.is_slot(44))
	assert_eq(ItemStore.slot_of(1005), 5)


# --- the fame store ---------------------------------------------------------

func test_the_fame_store_opens_with_a_balance():
	state.apply_packet("OpenFameStorePacket", {"playerId": 9, "accountFame": 1234})
	assert_true(state.fame.is_open)
	assert_eq(state.fame.balance, 1234)
	state.apply_packet("OpenFameStorePacket", {"playerId": 10, "accountFame": 9})
	assert_eq(state.fame.balance, 1234, "another player's")
	state.fame.close()
	assert_false(state.fame.is_open)


func test_the_catalogue_is_the_content_cheapest_first():
	var rows := FameStore.catalogue(content)
	assert_eq(rows, [[200, 100], [104, 500]], "9999 is priced but not an item")
	assert_eq(FameStore.catalogue(null), [])


func test_affording():
	state.fame.balance = 100
	assert_true(state.fame.can_afford(100))
	assert_false(state.fame.can_afford(101))
	assert_false(state.fame.can_afford(0), "nothing is free")
