class_name InteractionNotices
extends CanvasLayer

## What happened to the player's trades, party and PvP matches -- a request
## sent, an answer, a trade done, a match won -- as a short column of lines under
## the realm banner, each standing a few seconds (InteractionState.notices). Not
## the chat: these are the game telling you, not anyone saying it.

const TOP := 64.0
const SIZE := 14
const COLOUR := Color(1.0, 0.85, 0.4)
const FAILED_COLOUR := Color("ff8a8a")
const OUTLINE := 4

var state: RealmState

var _column: VBoxContainer
var _drawn_version := -1


func setup(realm_state: RealmState) -> void:
	state = realm_state


func _ready() -> void:
	layer = 15
	_column = VBoxContainer.new()
	_column.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_column.offset_top = TOP
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)


func _process(_delta: float) -> void:
	if state == null or _drawn_version == state.interactions.version:
		return
	_drawn_version = state.interactions.version
	for child in _column.get_children():
		child.queue_free()
	for notice in state.interactions.notices:
		var line := HudWidgets.label(String(notice["text"]), SIZE,
			FAILED_COLOUR if bool(notice["failed"]) else COLOUR)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_constant_override("outline_size", OUTLINE)
		line.add_theme_color_override("font_outline_color", Color.BLACK)
		_column.add_child(line)


## The lines on screen, for a test or a scripted render.
func lines() -> Array:
	return _column.get_children().filter(func(child: Node) -> bool: return not child.is_queued_for_deletion()) \
		.map(func(label: Label) -> String: return label.text)
