class_name CreateGuildDialog
extends CanvasLayer

## The nexus "found a guild" dialog: a name to type and what it costs. The
## server owns the rules -- unique name, 10,000 fame, not already in a guild --
## and answers with a SYSTEM line and a guild update; this only gates the
## obvious cases so the common mistake is caught before a round-trip.

const COST := 10000

var state: RealmState
var actions: GuildActions

var _root: PanelContainer
var _info: Label
var _input: LineEdit
var _error: Label
var _create: Button
var _shown := false


func setup(realm_state: RealmState, guild_actions: GuildActions) -> void:
	state = realm_state
	actions = guild_actions


func _ready() -> void:
	layer = 17
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(380, 0)
	centre.add_child(_root)
	var column := InventoryLayout.column(_root)
	InventoryLayout.heading(column, "FOUND A GUILD")
	_info = InventoryLayout.heading(column, "")
	_info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	InventoryLayout.heading(column, "Guild name")
	_input = LineEdit.new()
	_input.placeholder_text = "My Guild"
	_input.max_length = 24
	_input.text_submitted.connect(_submit)
	column.add_child(_input)
	_error = InventoryLayout.heading(column, "")
	_error.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_error.visible = false
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_create = InventoryLayout.button(buttons, "Create (10,000 Fame)", _submit)
	InventoryLayout.button(buttons, "Cancel", func() -> void: state.guild.close_create())
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	visible = state != null and state.guild.create_open and state.local.is_present()
	if not visible:
		_shown = false
		return
	PanelFit.shrink(_root)
	if not _shown:
		_shown = true
		_input.text = ""
		_input.grab_focus()
		_info.text = "Cost: %d fame     You have: %d" % [COST, state.guild.create_fame]
		if state.guild.create_in_guild:
			_error.text = already_in(state.guild.guild_name if state.guild.in_guild else "")
			_error.visible = true
			_create.disabled = true
		else:
			_error.visible = false
			_create.disabled = state.guild.create_fame < COST


func _submit(_text: String = "") -> void:
	if state.guild.create_in_guild:
		return
	var name := _input.text.strip_edges()
	if name.length() < 3 or name.length() > 24:
		_error.text = "Name must be 3-24 characters."
		_error.visible = true
		return
	if actions != null:
		actions.create_guild(name)
	state.guild.close_create()


## The refusal for a player who already has a guild, naming it when known.
static func already_in(guild_name: String) -> String:
	return "You are already in %s." % guild_name if guild_name != "" else "You are already in a guild."


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())


## Modal: while the name dialog is open, keystrokes are text, not game input.
func is_typing() -> bool:
	return visible
