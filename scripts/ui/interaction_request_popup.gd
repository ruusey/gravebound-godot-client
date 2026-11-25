class_name InteractionRequestPopup
extends CanvasLayer

## A trade request, party invite or PvP challenge waiting on an answer, with
## Accept and Decline: up while the request stands, gone once it is answered,
## closed by the server or out of time. One per kind, each at its own height so
## two standing at once both show.

const TOPS := {Interaction.Kind.TRADE: 120.0, Interaction.Kind.PARTY: 200.0, Interaction.Kind.PVP: 240.0}
const TITLE_COLOURS := {Interaction.Kind.PVP: Color("ff8a8a")}

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
	_root.offset_top = TOPS.get(kind, 120.0)
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
	var from := state.interactions.request_from(kind) if state != null else ""
	visible = from != "" and state.local.is_present()
	if visible and _shown_for != from:
		_shown_for = from
		_line.text = Interaction.PROMPTS[kind] % from
	elif not visible:
		_shown_for = ""


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())
