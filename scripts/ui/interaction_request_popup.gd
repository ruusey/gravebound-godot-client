class_name InteractionRequestPopup
extends CanvasLayer

## A trade request, party invite, PvP challenge or guild invite waiting on an
## answer, with Accept and Decline: up while the request stands, gone once it is
## answered, closed by the server or out of time. One per kind; the ones standing
## stack down from TOP in kind order, so any number at once all show.

## Under the notices, which hold at most InteractionState.MAX_NOTICES lines from their own TOP.
const TOP := 150.0
const STACK_GAP := 8.0
const TITLE_COLOURS := {Interaction.Kind.PVP: Color("ff8a8a"), Interaction.Kind.GUILD: TagStyles.GUILD_BLUE}

var state: RealmState
var actions: InteractionActions
var kind := Interaction.Kind.TRADE

var _root: PanelContainer
var _line: Label
var _shown_for := ""


func setup(realm_state: RealmState, interaction_actions: InteractionActions, interaction_kind: int) -> void:
	state = realm_state
	actions = interaction_actions
	kind = interaction_kind


func _ready() -> void:
	layer = 16
	visible = false
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.offset_top = TOP
	add_child(_root)
	var column := InventoryLayout.column(_root)
	_line = InventoryLayout.heading(column, "")
	_line.add_theme_color_override("font_color", TITLE_COLOURS.get(kind, Color.WHITE))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	InventoryLayout.button(buttons, "Accept", func() -> void: if actions != null: actions.accept(kind))
	InventoryLayout.button(buttons, "Decline", func() -> void: if actions != null: actions.decline(kind))
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	var line := state.interactions.prompt(kind) if state != null else ""
	visible = line != "" and state.local.is_present()
	if visible and _shown_for != line:
		_shown_for = line
		_line.text = line
	elif not visible:
		_shown_for = ""
	if visible:
		_root.offset_top = TOP + _slot() * (_root.size.y + STACK_GAP)


## How many requests of an earlier kind stand above this one.
func _slot() -> int:
	var slot := 0
	for other in Interaction.Kind.values():
		if other == kind:
			break
		if state.interactions.request_from(other) != "":
			slot += 1
	return slot


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())
