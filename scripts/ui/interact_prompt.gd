class_name InteractPrompt
extends CanvasLayer

## "Use Forge (F)" while a tile that can be used is in reach, "Enter
## Testing Arena (Space)" while a portal is -- and the line is a button,
## so on a phone, where there is no F and no Space, a tap on it does what
## the key would. The web client's prompt bar, as one line over the
## ability bar. It asks the same question every frame that the key would
## ask on the way down, so what it names is exactly what will be sent:
## the tile first, as F tries the tile before a pickup.

const MARGIN_BOTTOM := 100.0
## On a phone the bottom is the sticks' and buttons', so the prompt sits
## just over the player's head, near the middle, instead: under the player
## are their name and bars and the portal's card.
const PHONE_ABOVE_CENTRE := 24.0
const FONT_SIZE := 14
const GOLD := Color(1.0, 0.92, 0.6)

var state: RealmState
var shop: ShopActions
var portals: PortalInput
## No key to name on a phone.
var touch := false

var _button: Button
var _found := {}


func setup(realm_state: RealmState, shop_actions: ShopActions, portal_input: PortalInput = null) -> void:
	state = realm_state
	shop = shop_actions
	portals = portal_input


func _ready() -> void:
	layer = 11
	visible = false
	# A button that looks like one: as bare text a player took it for a label.
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	for look in ["normal", "hover", "pressed", "focus"]:
		_button.add_theme_stylebox_override(look, box(look == "pressed"))
	_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_button.offset_bottom = -MARGIN_BOTTOM
	if PhoneLayout.on:
		_button.set_anchors_preset(Control.PRESET_CENTER)
		_button.offset_top = -PHONE_ABOVE_CENTRE
		_button.offset_bottom = -PHONE_ABOVE_CENTRE
	_button.add_theme_font_size_override("font_size", FONT_SIZE)
	for look in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_button.add_theme_color_override(look, GOLD)
	_button.add_theme_color_override("font_outline_color", Color.BLACK)
	_button.add_theme_constant_override("outline_size", 4)
	_button.pressed.connect(use)
	add_child(_button)
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	_found = candidate()
	visible = not _found.is_empty()
	if visible:
		# Scanned every frame so the prompt and what the key sends stay in sync, but
		# the Button text (which re-shapes on assignment) is set only when it changes.
		var text: String = _found["text"] if touch else "%s (%s)" % [_found["text"], _found["key"]]
		if text != _button.text:
			_button.text = text


static func box(pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.2, 0.1, 0.95) if pressed else Color(0.1, 0.08, 0.06, 0.9)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


## What is in reach: {text, key, tile | portal}, or nothing.
func candidate() -> Dictionary:
	if state == null or not state.local.is_present():
		return {}
	var tile: Dictionary = shop.candidate() if shop != null else {}
	if not tile.is_empty():
		return {"text": TileInteract.verb(tile), "key": "F", "tile": tile}
	var portal: Dictionary = portals.nearest() if portals != null else {}
	if portal.is_empty():
		return {}
	var label := "the vault" if int(portal.get("portal_id", -1)) == PortalInput.VAULT_PORTAL \
		else String(portal.get("label", "portal"))
	return {"text": "Enter %s" % label, "key": "Space", "portal": portal}


## What the key would do.
func use() -> void:
	if _found.has("tile"):
		shop.interact_nearby()
	elif _found.has("portal"):
		portals.use_nearest()


## A click on the line is a use, not a shot at the world behind it.
func captures_mouse() -> bool:
	return visible and _button.get_global_rect().has_point(_button.get_global_mouse_position())
