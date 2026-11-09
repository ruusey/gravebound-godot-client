class_name ArenaResults
extends CanvasLayer

## The run summary the server sends when a Colosseum run ends (ArenaResultsPacket).
##
## Unlike the death screen, an arena run is NOT a permadeath: by the time this
## arrives the server has already restored the character and teleported them back
## to the nexus, so this is a dismissible scoreboard, not a game-over. Continue
## just hides it and leaves the player standing in the nexus.

signal dismissed

const TITLE := "COLOSSEUM"

var _panel: ColorRect
var _detail: Label
var _waves: Label
var _kills: Label
var _time: Label
var _fame: Label


func _ready() -> void:
	# Above the realm-transition cover, like the death screen: the results arrive
	# as the player is teleported out, and the cover must not hide them.
	layer = 18
	visible = false

	_panel = ColorRect.new()
	_panel.color = Color(0.03, 0.02, 0.0, 0.94)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(column)

	_line(column, TITLE, 34, Color(0.95, 0.76, 0.26))
	_detail = _line(column, "", 17, Color(0.85, 0.8, 0.75))
	_spacer(column, 10)
	_waves = _line(column, "", 20, Color(0.95, 0.9, 0.8))
	_kills = _line(column, "", 15, Color(0.8, 0.78, 0.72))
	_time = _line(column, "", 15, Color(0.8, 0.78, 0.72))
	_spacer(column, 6)
	_fame = _line(column, "", 19, Color(0.98, 0.82, 0.3))
	_spacer(column, 14)

	var button := Button.new()
	button.text = "Continue"
	button.custom_minimum_size = Vector2(160, 0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(_on_continue)
	column.add_child(button)


## Fills and shows the scoreboard from an ArenaResultsPacket payload.
func show_results(data: Dictionary) -> void:
	var waves := int(data.get("wavesCompleted", 0))
	var kills := int(data.get("enemiesKilled", 0))
	var seconds := int(data.get("timeSurvivedSec", 0))
	var fame := int(data.get("fameAwarded", 0))
	_detail.text = "You fell after clearing %d wave%s." % [waves, "" if waves == 1 else "s"]
	_waves.text = "Waves cleared:  %d" % waves
	_kills.text = "Enemies slain:  %d" % kills
	_time.text = "Time survived:  %s" % _format_time(seconds)
	_fame.text = "+ %d Fame" % fame
	visible = true


func _on_continue() -> void:
	visible = false
	dismissed.emit()


func _format_time(seconds: int) -> String:
	var minutes := seconds / 60
	var secs := seconds % 60
	return "%d:%02d" % [minutes, secs]


func _spacer(column: VBoxContainer, height: int) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	column.add_child(gap)


func _line(column: VBoxContainer, text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	column.add_child(label)
	return label
