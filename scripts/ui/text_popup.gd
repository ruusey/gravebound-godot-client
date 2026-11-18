class_name TextPopup
extends CanvasLayer

## A read-only text box: a title, the body text, and a single Close button.
##
## Shown client-side when the player reads a `display_text` tile — the body is the
## tile's own `description`. Modeled on ConfirmPopup; a second show while one stands
## is ignored so a held F can't stack boxes.

var _root: PanelContainer
var _title: Label
var _body: Label
var _showing := false


func _ready() -> void:
	layer = 18
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14171f")
	style.border_color = Color("8a6d3b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_root.add_theme_stylebox_override("panel", style)
	centre.add_child(_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_root.add_child(column)
	_title = HudWidgets.label("", 16, Color("f0d890"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_body = HudWidgets.label("", 14, Color("d8d0c0"))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 348
	column.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	InventoryLayout.button(buttons, "Close", _close)
	TouchFrame.adopt(self)


## Show `body` under `title`. An empty title hides the title line.
func show_text(title: String, body: String) -> void:
	if _showing:
		return
	_showing = true
	_title.text = title
	_title.visible = title != ""
	_body.text = body
	visible = true


func _close() -> void:
	_showing = false
	visible = false


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())
