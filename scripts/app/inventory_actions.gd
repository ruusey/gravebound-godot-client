class_name InventoryActions
extends RefCounted

## Turns what the player did to a slot into the packet the server expects.
##
## Nearly every gesture is a MoveItemPacket with a different corner of it set
## -- swap, drop and consume are one packet told apart by its flags. The
## mapping and the checks before a send are the web client's: the server
## refuses a bad move with a log line and nothing the client can see. Nothing
## here touches the bag; the next UpdatePacket is what moves the item. A
## gesture with a store slot at either end is the shop's.

## A full stack of shards forges into a crystal in place.
const SHARD_STACK := 10
const NONE := -1

var state: RealmState
var client: GraveBoundClient
var content: GameData
var shop: ShopActions


func _init(realm_state: RealmState, net_client: GraveBoundClient, game_data: GameData) -> void:
	state = realm_state
	client = net_client
	content = game_data


## A drag from one slot to another. The server swaps whatever is in the
## target, so a move into OR out of an equipment slot has to validate the
## item that ends up equipped -- which, for a move out, is the target's.
func move(from: int, to: int) -> bool:
	if ItemStore.is_slot(from) or ItemStore.is_slot(to):
		return shop != null and shop.move(from, to)
	if from == to or not _holds(from):
		return false
	if Inventory.is_ground_loot(from):
		return pick_up(from - Inventory.GROUND_LOOT_START)
	if Inventory.is_ground_loot(to):
		return drop(from)
	if not (Inventory.is_equipment(to) or Inventory.is_backpack(to)):
		return false
	if Inventory.is_equipment(to) and not _fits(item_in(from), to):
		return false
	if Inventory.is_equipment(from) and _holds(to) and not _fits(item_in(to), from):
		return false
	if Inventory.is_equipment(to):
		Sfx.event("item_equip")
	elif Inventory.is_equipment(from):
		Sfx.event("item_unequip")
	else:
		Sfx.event("item_move")
	return _send_move(to, from, false, false)


## Right-click while the potion store is open: onto its shelves instead.
func stash(from: int) -> bool:
	return shop != null and shop.stash(from)


## Right-click, or a drag that ends on the world: the server picks ground or bag.
func drop(from: int) -> bool:
	if Inventory.is_ground_loot(from) or not _holds(from):
		return false
	Sfx.event("item_drop")
	return _send_move(NONE, from, true, false)


func consume(from: int) -> bool:
	if Inventory.is_ground_loot(from) or not bool(item_in(from).get("consumable", false)):
		return false
	Sfx.event("item_use")
	return _send_move(from, from, false, true)


## Double-click: a full shard stack forges, a consumable is used, gear goes
## to its slot -- and gear the class cannot wear does nothing.
func activate(from: int) -> bool:
	if not Inventory.is_backpack(from) or not _holds(from):
		return false
	var item := item_in(from)
	if item.get("category", "") == "shard" and int(item.get("stackCount", 0)) >= SHARD_STACK:
		return _send("ConsumeShardStackPacket", {"fromSlotIndex": from})
	if bool(item.get("consumable", false)):
		return consume(from)
	var slot := int(item.get("targetSlot", NONE))
	if not _fits(item, slot):
		return false
	Sfx.event("item_equip")
	return _send_move(slot, from, false, false)


## Shift+right-click: half the stack into the first free backpack slot.
func split(from: int) -> bool:
	var item := item_in(from)
	if not Inventory.is_backpack(from) or not bool(item.get("stackable", false)):
		return false
	return int(item.get("stackCount", 0)) > 1 and _send("SplitStackPacket", {"fromSlot": from})


## One item out of the bag at our feet. The target is nominal (the server
## picks the first empty backpack slot) but is validated, so it must be real.
func pick_up(loot_index: int) -> bool:
	if not Inventory.holds(loot_item(loot_index)):
		return false
	# Same "into the bag" sound as moving an item between inventory slots.
	Sfx.event("item_move")
	return _send_move(Inventory.BACKPACK_START, Inventory.GROUND_LOOT_START + loot_index, false, false)


## The F key: the first thing in the bag.
func pick_up_first() -> bool:
	var items := loot_items()
	for i in items.size():
		if Inventory.holds(items[i]):
			return pick_up(i)
	return false


## Z and X. The pools are counts; the only check is that there is one.
func drink(hp: bool) -> bool:
	var bag := state.local.inventory
	if (bag.hp_potions if hp else bag.mp_potions) <= 0:
		return false
	Sfx.event("item_use")
	return _send_move(NONE, Inventory.HP_POTION_SLOT if hp else Inventory.MP_POTION_SLOT, false, true)


## What is in the bag at our feet, if one is in reach.
func loot_items() -> Array:
	return Inventory.nearest_loot(state.entities, state.local.position,
		GameConstants.PLAYER_SIZE).get("items", [])


func loot_item(index: int) -> Dictionary:
	var items := loot_items()
	return items[index] if index >= 0 and index < items.size() and items[index] is Dictionary else {}


## Anything a slot index can name, carried or on the ground.
func item_in(index: int) -> Dictionary:
	if Inventory.is_ground_loot(index):
		return loot_item(index - Inventory.GROUND_LOOT_START)
	return state.local.inventory.item_at(index)


func _holds(index: int) -> bool:
	return Inventory.holds(item_in(index))


func _fits(item: Dictionary, slot: int) -> bool:
	return ItemRules.can_equip(item, slot, state.local.class_id, content)


func _send_move(target: int, from: int, drop_flag: bool, consume_flag: bool) -> bool:
	return _send("MoveItemPacket", {"targetSlotIndex": target, "fromSlotIndex": from,
		"drop": drop_flag, "consume": consume_flag})


## A scripted capture has no client at all; nothing is sent, and nothing errs.
func _send(packet: String, data: Dictionary) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send(packet, data)
	return true
