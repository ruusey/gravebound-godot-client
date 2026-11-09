class_name ShopActions
extends RefCounted

## The tiles you use, and what you do in the panels they open.
##
## F sends InteractTilePacket for the tile in reach and the server answers
## by opening something. A move between the bag and the potion store is one
## ItemStoreMovePacket with its two sides recovered from the slot indices;
## the checks before a send are the server's own, mirrored, because it
## refuses with a log line and nothing the client can see. A purchase is
## BuyFameItemPacket; the server spends and answers with the new balance.

var state: RealmState
var client: GraveBoundClient
var content: GameData


func _init(realm_state: RealmState, net_client: GraveBoundClient, game_data: GameData) -> void:
	state = realm_state
	client = net_client
	content = game_data


## The interactive tile in reach, or {}.
func candidate() -> Dictionary:
	return TileInteract.nearest(state.tiles, content, state.local.position)


## F: the tile in reach, if any. The web client tries this before a pickup.
func interact_nearby() -> bool:
	var found := candidate()
	if found.is_empty():
		return false
	return _send("InteractTilePacket", {"tileX": found["tile_x"], "tileY": found["tile_y"]})


## A drag with a store slot at either end. A bag item onto an occupied
## store slot is refused unless the two stacks merge -- the server refuses
## the same, since bag drags may only place, not displace -- and anything
## the store will not keep is never sent.
func move(from: int, to: int) -> bool:
	if not state.store.is_open or from == to or not _slot(from) or not _slot(to):
		return false
	var item := item_in(from)
	if not Inventory.holds(item):
		return false
	if ItemStore.is_slot(to) and not ItemStore.is_slot(from):
		if not ItemStore.accepts(item):
			return false
		var there := item_in(to)
		if Inventory.holds(there) and not _merges(item, there):
			return false
	return _send_move(from, side(from), ItemStore.slot_of(from) if ItemStore.is_slot(from) else from,
		side(to), ItemStore.slot_of(to) if ItemStore.is_slot(to) else to)


## Right-click on a bag item while the store is open: the server picks the
## slot, a mergeable stack first and the first empty one otherwise.
func stash(inventory_index: int) -> bool:
	if not state.store.is_open or ItemStore.is_slot(inventory_index):
		return false
	var item := state.local.inventory.item_at(inventory_index)
	if not Inventory.holds(item) or not ItemStore.accepts(item):
		return false
	return _send_move(inventory_index, ItemStore.SIDE_INVENTORY, inventory_index,
		ItemStore.SIDE_STORAGE, ItemStore.ANY_SLOT)


## A click on a store item: into the first free backpack slot.
func take(store_index: int) -> bool:
	if not ItemStore.is_slot(store_index) or not Inventory.holds(item_in(store_index)):
		return false
	var free := state.local.inventory.first_empty_backpack()
	if free < 0:
		return false
	return move(store_index, free)


func buy(item_id: int) -> bool:
	if not state.fame.is_open or content == null:
		return false
	var cost := int(content.library.fame_store.get(item_id, 0))
	if not state.fame.can_afford(cost):
		return false
	return _send("BuyFameItemPacket", {"itemId": item_id})


## The exchange the panel has set up, as ExchangeItemsPacket: give
## `quantity` of the source for one fewer of the target. Only when the
## server would accept it, since a refusal is a SYSTEM line and nothing
## else.
func exchange() -> bool:
	var market := state.market
	if not market.is_open or not market.ready(int(ExchangeMarket.owned(state.local.inventory, content).get(market.source, 0))):
		return false
	return _send("ExchangeItemsPacket", {"sourceItemId": market.source,
		"targetItemId": market.target, "quantity": market.quantity})


## Anything a slot index can name, in the bag or on the shelf.
func item_in(index: int) -> Dictionary:
	if ItemStore.is_slot(index):
		return state.store.item_at(ItemStore.slot_of(index))
	return state.local.inventory.item_at(index)


static func side(index: int) -> int:
	return ItemStore.SIDE_STORAGE if ItemStore.is_slot(index) else ItemStore.SIDE_INVENTORY


## The server's isValidIdx: any bag slot, equipment included, or a store slot.
static func _slot(index: int) -> bool:
	return ItemStore.is_slot(index) or Inventory.is_equipment(index) or Inventory.is_backpack(index)


static func _merges(incoming: Dictionary, resident: Dictionary) -> bool:
	return int(incoming.get("itemId", -1)) == int(resident.get("itemId", -2)) \
		and bool(incoming.get("stackable", false)) and bool(resident.get("stackable", false)) \
		and int(resident.get("stackCount", 1)) < int(resident.get("maxStack", 1))


func _send_move(_from: int, from_side: int, from_idx: int, to_side: int, to_idx: int) -> bool:
	return _send("ItemStoreMovePacket", {"storeKind": state.store.kind, "fromSide": from_side,
		"fromIdx": from_idx, "toSide": to_side, "toIdx": to_idx})


func _send(packet: String, data: Dictionary) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send(packet, data)
	return true
