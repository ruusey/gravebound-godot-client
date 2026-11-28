class_name ControlsTab
extends VBoxContainer

## The Controls page of the options: an action and its key on a button,
## two to a row, so the page is half as tall, in a scroll -- one to a row,
## its eighteen rows ran off a phone held sideways.
##
## Click the button and the next key pressed is the new one -- Escape
## cancels. While it waits it owns the keyboard (OptionsPanel.capturing),
## so pressing W to bind it does not also walk the player forward. A key
## another action had moves over to it and that action takes this one's old
## key (KeyBindings.rebind). Reset puts every key back to the project's.

const WAITING := "Press a key ..."
const LIST_HEIGHT := 300.0

var settings: GameSettings
var buttons := {}   # action -> Button
var waiting_for := ""


func _init(game_settings: GameSettings = null) -> void:
	settings = game_settings
	name = "Controls"


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	scroll.add_child(grid)
	for action in KeyBindings.all_actions():
		var label := HudWidgets.label(KeyBindings.label(action), 13, Color.WHITE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 0)
		button.pressed.connect(listen.bind(action))
		grid.add_child(button)
		buttons[action] = button
	InventoryLayout.button(self, "Reset to defaults", func() -> void:
		if settings != null:
			settings.reset_keys()
		refresh())
	refresh()


## Waits for the next key for `action`.
func listen(action: String) -> void:
	refresh()
	waiting_for = action
	buttons[action].text = WAITING


func refresh() -> void:
	waiting_for = ""
	for action in buttons:
		buttons[action].text = KeyBindings.binding_name(action)


func _input(event: InputEvent) -> void:
	if waiting_for == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	take(event)


## A key pressed while waiting: Escape cancels, anything else binds.
func take(event: InputEventKey) -> void:
	var action := waiting_for
	if event.physical_keycode != KEY_ESCAPE and settings != null:
		settings.rebind(action, event.physical_keycode)
	refresh()
