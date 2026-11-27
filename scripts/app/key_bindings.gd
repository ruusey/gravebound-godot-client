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
}


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


## Points the action at a key. The key's old action, if another here had
## it, takes this one's old key instead -- a swap, so nothing is left
## unbound. Returns every action whose key changed.
static func rebind(action: String, key: int) -> Array:
	var before := key_of(action)
	if key == before:
		return []
	var changed: Array = [action]
	for other in ACTIONS:
		if other != action and key_of(other) == key:
			_assign(other, before)
			changed.append(other)
	_assign(action, key)
	return changed


## Every action to the given keys, and the rest to the project's defaults.
static func apply(saved: Dictionary) -> void:
	for action in ACTIONS:
		_assign(action, int(saved.get(action, default_key(action))))


## What differs from the defaults, for keeping.
static func custom() -> Dictionary:
	var out := {}
	for action in ACTIONS:
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
		InputMap.action_add_event(action, event)
