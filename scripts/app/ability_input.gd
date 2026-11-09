class_name AbilityInput
extends RefCounted

## The keys that cast: 1, 2 and 3 for the three hotbar slots, and the right
## mouse button as the web client's shortcut for the first.
##
## Shift with a digit is the bag's (InventoryInput), so a digit only casts
## with Shift up -- the web client gates the same way, after pressing 1 to
## cast also swapped the weapon. K opens the skills panel -- in a realm only,
## since a K typed into the password field is not a request for it.

const SLOTS := AbilityCatalog.SLOTS

var client: GraveBoundClient
var caster: AbilityCaster
var skills: SkillsPanel
## Whether something on screen owns the mouse; a right-click there is a
## gesture on it, not a cast.
var mouse_captured: Callable = func() -> bool: return false
## Whether the chat line has the keyboard; a digit then is a digit.
var keyboard_captured: Callable = func() -> bool: return false

var _held := {}


func _init(net_client: GraveBoundClient, ability_caster: AbilityCaster,
		skills_panel: SkillsPanel) -> void:
	client = net_client
	caster = ability_caster
	skills = skills_panel


func tick(_delta: float) -> void:
	if not client.is_in_game() or keyboard_captured.call():
		_held.clear()
		return
	if _pressed("toggle_skills"):
		skills.toggle()
	var shift := Input.is_key_pressed(KEY_SHIFT)
	for slot in SLOTS:
		if _pressed("ability_%d" % (slot + 1)) and not shift:
			caster.cast_at_cursor(slot)
	var right := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var edge: bool = right and not _held.get("right", false)
	_held["right"] = right
	if edge and not mouse_captured.call():
		caster.cast_at_cursor(0)


## True on the frame the key goes down, not while it is held.
func _pressed(action: String) -> bool:
	var down := Input.is_action_pressed(action)
	var edge: bool = down and not _held.get(action, false)
	_held[action] = down
	return edge
