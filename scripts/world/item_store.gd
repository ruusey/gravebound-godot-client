class_name ItemStore
extends RefCounted

## A store the server opens for you: the vault's potion storage or the guild
## hall's shared one, thirty two slots of stackables and gems either way.
##
## Its slots share the bag's index space from SLOT_BASE up, so a drag between
## the two panels is one integer pair like any other and the two sides of an
## ItemStoreMovePacket are recovered from the indices. The server tells us
## what is in it on open and after every move; nothing here moves an item.

const KIND_POTION := 0
const KIND_GUILD_POTION := 1
const SIZE := 32
const SLOT_BASE := 1000
const SIDE_INVENTORY := 0
const SIDE_STORAGE := 1
## The quick-store sentinel: the server picks a mergeable stack, else the
## first empty slot.
const ANY_SLOT := -1

var kind := -1
var items: Array = []
var is_open := false
var version := 0


func _init() -> void:
	clear()


func clear() -> void:
	kind = -1
	items = []
	for i in SIZE:
		items.append({})
	is_open = false
	version += 1


## The server's ItemStoreKind.POTION whitelist: stackables and gems.
static func accepts(item: Dictionary) -> bool:
	return bool(item.get("stackable", false)) or str(item.get("category", "")) == "gem"


static func is_slot(index: int) -> bool:
	return index >= SLOT_BASE and index < SLOT_BASE + SIZE


static func slot_of(index: int) -> int:
	return index - SLOT_BASE


func apply_open(data: Dictionary, local_id: int) -> void:
	if int(data.get("playerId", 0)) != local_id:
		return
	kind = int(data.get("storeKind", KIND_POTION))
	_take(data.get("items", []))
	is_open = true
	version += 1


## After a move. Ignored while closed, or for a store of another kind.
func apply_update(data: Dictionary, local_id: int) -> void:
	if not is_open or int(data.get("playerId", 0)) != local_id \
			or int(data.get("storeKind", KIND_POTION)) != kind:
		return
	_take(data.get("items", []))
	version += 1


func close() -> void:
	is_open = false
	version += 1


func item_at(index: int) -> Dictionary:
	if index < 0 or index >= SIZE:
		return {}
	return items[index]


func first_empty() -> int:
	for i in SIZE:
		if items[i].is_empty():
			return i
	return -1


func _take(wire: Array) -> void:
	for i in SIZE:
		var item: Variant = wire[i] if i < wire.size() else null
		items[i] = item if Inventory.holds(item) else {}
