class_name OptionsPanel
extends CanvasLayer

## The options: Escape in a realm opens it, as the web client's menu does.
##
## Godot's own controls, on three tabs, so that no tab is taller than a
## phone held sideways: Display (VSync, the UI scale and the world zoom),
## Graphics (a checkbox a setting, in two columns), each flipping its
## GameSettings switch the moment it is clicked (and kept for next time);
## and Controls, a key an action (ControlsTab). Leave game is what Escape used to do on its
## own: an accidental Escape now opens a menu instead of dropping the
## session. Close, or Escape again, puts it away.

const WIDTH := 560
const HEADING := Color(1.0, 0.85, 0.42)

var settings: GameSettings
var client: GraveBoundClient
var shown := false

var _root: PanelContainer
var boxes := {}   # key -> CheckBox
var controls: ControlsTab
var scale_row: ScaleRow
var zoom_row: ScaleRow
var leave_button: Button
var close_button: Button


func setup(game_settings: GameSettings, net_client: GraveBoundClient) -> void:
	settings = game_settings
	client = net_client


func _ready() -> void:
	# Over the HUD, the bag and the chat; under the transition cover.
	layer = 14
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(WIDTH, 0)
	# Opaque, as the item card is: the default panel lets the realm and its
	# names show through the text.
	var style := StyleBoxFlat.new()
	style.bg_color = ItemTooltip.BACKGROUND
	style.border_color = ItemTooltip.EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_root.add_theme_stylebox_override("panel", style)
	centre.add_child(_root)
	var column := InventoryLayout.column(_root)
	var title := HudWidgets.label("Options", 18, HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var tabs := TabContainer.new()
	column.add_child(tabs)
	var display := VBoxContainer.new()
	display.name = "Display"
	tabs.add_child(display)
	_boxes(display, GameSettings.DISPLAY)
	scale_row = ScaleRow.new(settings, ScaleRow.UI)
	display.add_child(scale_row)
	zoom_row = ScaleRow.new(settings, ScaleRow.WORLD)
	display.add_child(zoom_row)
	var graphics := GridContainer.new()
	graphics.name = "Graphics"
	graphics.columns = 2
	graphics.add_theme_constant_override("h_separation", 16)
	tabs.add_child(graphics)
	_boxes(graphics, GameSettings.GRAPHICS)
	var audio := VBoxContainer.new()
	audio.name = "Audio"
	tabs.add_child(audio)
	_boxes(audio, GameSettings.AUDIO)
	_volume_row(audio)
	controls = ControlsTab.new(settings)
	tabs.add_child(controls)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	leave_button = InventoryLayout.button(buttons, "Leave game", leave)
	close_button = InventoryLayout.button(buttons, "Close", close)
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	visible = shown and client != null and client.is_in_game()
	if visible:
		PanelFit.shrink(_root)


func toggle() -> void:
	shown = not shown
	refresh()


func close() -> void:
	shown = false
	refresh()


## Waiting for a key to bind: the keyboard is the panel's, not the game's.
func capturing() -> bool:
	return visible and controls != null and controls.waiting_for != ""


## Leaves the realm, as Escape alone used to.
func leave() -> void:
	shown = false
	if client != null and client.is_in_game():
		client.disconnect_from_server()


## Every box to what the settings say now.
func refresh() -> void:
	if settings == null:
		return
	for key in boxes:
		boxes[key].set_pressed_no_signal(settings.is_on(key))
	if scale_row != null:
		scale_row.refresh()
	if controls != null and controls.is_inside_tree():
		controls.refresh()


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())


## A labelled 0..100% slider for the master SFX volume, kept the moment it moves.
func _volume_row(into: Container) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(HudWidgets.label("Volume", 14, Color(0.85, 0.85, 0.85)))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = settings.sound_volume if settings != null else 0.8
	slider.value_changed.connect(func(value: float) -> void: if settings != null: settings.set_sound_volume(value))
	row.add_child(slider)
	into.add_child(row)


func _boxes(into: Container, table: Dictionary) -> void:
	for key in table:
		var box := CheckBox.new()
		box.text = table[key][0]
		box.button_pressed = settings.is_on(key) if settings != null else bool(table[key][1])
		box.toggled.connect(func(on: bool) -> void: if settings != null: settings.set_on(key, on))
		into.add_child(box)
		boxes[key] = box
