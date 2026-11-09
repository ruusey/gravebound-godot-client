class_name ForgeActions
extends RefCounted

## What the player does at the forge, as packets.
##
## Two of them. ForgeEnchantPacket names the three bag slots on the bench,
## the crystal's id as a check, and the pixel the crystal paints;
## ForgeDisenchantPacket names the item to strip. Both are gated by
## ForgeRules first, since the server refuses with nothing the client can
## see, and the next UpdatePacket is what shows the result.

var state: RealmState
var client: GraveBoundClient
var content: GameData


func _init(realm_state: RealmState, net_client: GraveBoundClient, game_data: GameData) -> void:
	state = realm_state
	client = net_client
	content = game_data


## A bag item dropped on a zone. Returns what to tell the player -- the
## web client's words -- or "" when the item was taken.
func place(zone: String, bag_index: int) -> String:
	var item := state.local.inventory.item_at(bag_index)
	if not state.forge.is_open or not Inventory.holds(item):
		return "Drag an item from the bag."
	match zone:
		"target":
			if not ForgeRules.is_equipment(item):
				return "Only equipment can be enchanted."
		"crystal":
			if not (ForgeRules.is_crystal(item) or ForgeRules.is_gem(item)):
				return "That isn't a crystal or gem."
		"essence":
			if not ForgeRules.is_essence(item):
				return "That isn't essence."
		_:
			return "Drag an item from the bag."
	state.forge.assign(zone, bag_index)
	return ""


func item_on(zone: String) -> Dictionary:
	return state.forge.item_on(zone, state.local.inventory)


## The first reason a forge would be refused, or "".
func problem() -> String:
	return ForgeRules.problem(item_on("target"), item_on("crystal"), item_on("essence"), content)


func enchant() -> bool:
	if not state.forge.is_open or problem() != "":
		return false
	var target := item_on("target")
	var crystal := item_on("crystal")
	var texture: Texture2D = content.item_texture(int(target.get("itemId", -1))) if content else null
	# The pixel the player picked on the forge grid, if it's still a valid mount;
	# otherwise fall back to the first free opaque pixel.
	var pixel: Vector2i = state.forge.selected_pixel
	if not ForgePixel.is_pickable(texture, target, pixel):
		pixel = ForgePixel.pick(texture, target)
	return _send("ForgeEnchantPacket", {
		"targetItemSlot": state.forge.index_of("target"),
		"crystalItemId": int(crystal.get("itemId", -1)),
		"crystalSlotIndex": state.forge.index_of("crystal"),
		"essenceSlotIndex": state.forge.index_of("essence"),
		"pixelX": pixel.x, "pixelY": pixel.y,
	})


func disenchant() -> bool:
	if not state.forge.is_open or not ForgeRules.can_disenchant(item_on("target")):
		return false
	return _send("ForgeDisenchantPacket", {"targetItemSlot": state.forge.index_of("target")})


func _send(packet: String, data: Dictionary) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send(packet, data)
	return true
