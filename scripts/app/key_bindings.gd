class_name KeyBindings
extends RefCounted

## Which key does what: the web client's rebindable controls, as Godot
## input actions.
##
## Every action here is already how the game reads its key -- the project's
## input map -- so a rebinding is only a change to that map, and nothing
## that polls the action needs to know. Keys are physical (the position on
## the keyboard, not the letter), as the project's own defaults are, so a
## binding means the same place on any layout. Escape and Enter are not
## here: the menu and the chat line must always be reachable. Neither are
## the mouse buttons for firing and casting.
##
## The bag's quick slots are Shift plus a key (SHIFTED), since a bare digit
## casts. They are their own group: Shift+1 and 1 never take each other's key.

## Action -> label, in the order the Controls tab lists them.
const ACTIONS := {
	"move_up": "Move up", "move_down": "Move down",
	"move_left": "Move left", "move_right": "Move right",
	"ability_1": "Ability 1", "ability_2": "Ability 2", "ability_3": "Ability 3",
	"use_portal": "Use portal", "go_nexus": "Go to the nexus", "go_vault": "Go to the vault",
	"pick_up": "Pick up / interact", "drink_hp": "Drink HP potion", "drink_mp": "Drink MP potion",
	"summon_companion": "Summon / recall companion",
	"toggle_inventory": "Bag", "toggle_skills": "Character sheet", "toggle_masteries": "Skills",
	"toggle_quests": "Quest log",
	"toggle_minimap": "Minimap",
	"reply_tell": "Reply to last PM",
	"guild_chat": "Guild chat",
	"open_command": "Chat on a command",
	"toggle_social": "Friends & guild",
	"orbit_left": "3D view: turn left", "orbit_right": "3D view: turn right",
	"toggle_lighting": "Lighting on/off",
	"screenshot": "Screenshot",
	"debug_packet_mix": "Debug: packet mix",
	"toggle_collision_view": "Debug: collision",
	"record_hitches": "Debug: record hitches",
}

## Action -> label, for the keys held with Shift.
const SHIFTED := {
	"quick_slot_1": "Use bag slot 1", "quick_slot_2": "Use bag slot 2",
	"quick_slot_3": "Use bag slot 3", "quick_slot_4": "Use bag slot 4",
	"quick_slot_5": "Use bag slot 5", "quick_slot_6": "Use bag slot 6",
	"quick_slot_7": "Use bag slot 7", "quick_slot_8": "Use bag slot 8",
}


## Every rebindable action, in the order the Controls tab lists them.
static func all_actions() -> Array:
	return ACTIONS.keys() + SHIFTED.keys()


static func label(action: String) -> String:
	return String(ACTIONS.get(action, SHIFTED.get(action, action)))


## The key as the Controls tab writes it, with Shift for a shifted action.
static func binding_name(action: String) -> String:
	var name := key_name(key_of(action))
	return "Shift+" + name if action in SHIFTED and key_of(action) != 0 else name


## The project's own key for an action.
static func default_key(action: String) -> int:
	var setting: Dictionary = ProjectSettings.get_setting("input/" + action, {})
	for event in setting.get("events", []):
		if event is InputEventKey:
			return event.physical_keycode
	return 0


## The key the action answers to now.
static func key_of(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.physical_keycode
	return 0


## Points the action at a key. The key's old action, if another in its group
## had it, takes this one's old key instead -- a swap, so nothing is left
## unbound. Returns every action whose key changed.
static func rebind(action: String, key: int) -> Array:
	var before := key_of(action)
	if key == before:
		return []
	var changed: Array = [action]
	for other in (SHIFTED if action in SHIFTED else ACTIONS):
		if other != action and key_of(other) == key:
			_assign(other, before)
			changed.append(other)
	_assign(action, key)
	return changed


## Every action to the given keys, and the rest to the project's defaults.
static func apply(saved: Dictionary) -> void:
	for action in all_actions():
		_assign(action, int(saved.get(action, default_key(action))))


## What differs from the defaults, for keeping.
static func custom() -> Dictionary:
	var out := {}
	for action in all_actions():
		if key_of(action) != default_key(action):
			out[action] = key_of(action)
	return out


static func key_name(key: int) -> String:
	if key == 0:
		return "(none)"
	# The layout lookup is the letter this keyboard prints there; headless
	# (the unit suite) has no keyboard and logs an error for asking.
	if DisplayServer.get_name() == "headless":
		return OS.get_keycode_string(key)
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(key))


static func _assign(action: String, key: int) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	if key != 0:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.shift_pressed = action in SHIFTED
		InputMap.action_add_event(action, event)
