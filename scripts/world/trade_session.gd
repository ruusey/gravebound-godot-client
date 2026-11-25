class_name TradeSession
extends RefCounted

## A trade with another player, once both have agreed to it (the request
## itself lives in InteractionState).
##
## Three packets: AcceptTradeRequestPacket opens the trade with both players
## and both bags, or closes it;
## UpdateTradePacket carries both sides' selections and confirmations,
## UpdatePlayerTradeSelectionPacket one side's. The web client's rules: only
## the bag's first page is on the table; a trade closed while open is held a second, both sides shown
## confirmed, before it goes (the native's scheduleTradeOverlayClose too).

const SLOTS := 20
const FIRST_SLOT := Inventory.BACKPACK_START
const CLOSING_HOLD_MS := 1_000

var active := false
var partner_name := ""
var partner_id := 0
## The partner's whole bag as the wire sent it, by slot.
var partner_inventory: Array = []
## What we have put on the table, by page slot.
var my_selected: Array = []
## Each side's NetInventorySelection as last sent by the server.
var mine := {}
var theirs := {}
var version := 0

var _clock: Callable
var _closing_at := 0


func _init(clock: Callable = func() -> int: return Time.get_ticks_msec()) -> void:
	_clock = clock


func clear() -> void:
	active = false
	partner_name = ""
	partner_id = 0
	partner_inventory = []
	my_selected = []
	mine = {}
	theirs = {}
	_closing_at = 0
	version += 1


func apply(name: String, data: Dictionary, local_id: int) -> void:
	match name:
		"AcceptTradeRequestPacket":
			_apply_accept(data, local_id)
		"UpdateTradePacket":
			var both: Dictionary = data.get("selections", {})
			_take(both.get("player0Selection", {}), local_id)
			_take(both.get("player1Selection", {}), local_id)
		"UpdatePlayerTradeSelectionPacket":
			_take(data.get("selection", {}), local_id)
	version += 1


func _apply_accept(data: Dictionary, local_id: int) -> void:
	if bool(data.get("accepted", false)):
		var first: Dictionary = data.get("player0", {})
		var second: Dictionary = data.get("player1", {})
		var we_are_first := int(first.get("id", 0)) == local_id
		var partner: Dictionary = second if we_are_first else first
		partner_name = String(partner.get("name", ""))
		partner_id = int(partner.get("id", 0))
		partner_inventory = data.get("player1Inv" if we_are_first else "player0Inv", [])
		my_selected = []
		my_selected.resize(SLOTS)
		my_selected.fill(false)
		mine = {}
		theirs = {}
		active = true
		_closing_at = 0
	elif active:
		_closing_at = _clock.call()
	else:
		clear()


func _take(selection: Dictionary, local_id: int) -> void:
	if selection.is_empty():
		return
	if int(selection.get("playerId", 0)) == local_id:
		mine = selection
	else:
		theirs = selection


## Puts a page slot on the table or takes it off; any change un-confirms us.
func toggle(slot_index: int) -> bool:
	var page := slot_index - FIRST_SLOT
	if not active or page < 0 or page >= SLOTS or closing():
		return false
	my_selected[page] = not my_selected[page]
	mine["confirmed"] = false
	version += 1
	return true


## What the partner's bag holds at a slot, or nothing.
func partner_item(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= partner_inventory.size():
		return {}
	var item: Variant = partner_inventory[slot_index]
	return item if item is Dictionary else {}


func partner_selected(page: int) -> bool:
	var flags: Array = theirs.get("selection", [])
	return page < flags.size() and bool(flags[page])


func closing() -> bool:
	return _closing_at > 0


func my_confirmed() -> bool:
	return TradeStatus.confirmed(mine, closing())


func partner_confirmed() -> bool:
	return TradeStatus.confirmed(theirs, closing())


func status() -> String:
	return TradeStatus.line(mine, theirs, closing(), partner_name)


## A closed trade that has been held on screen long enough.
func expire() -> void:
	if closing() and int(_clock.call()) - _closing_at >= CLOSING_HOLD_MS:
		clear()
