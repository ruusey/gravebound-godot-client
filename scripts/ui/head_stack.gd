class_name HeadStack
extends Control

## What floats over a character's head: the status chips, stacked upward,
## and above them the bubble of what it last said.
##
## The web client's sizes: chips 40x14 with 2 between, the lowest just over
## the anchor; the bubble a white rounded box of 12px text wrapped at 180,
## fading over its last half second. Chips are rebuilt only when the set
## changes, and the bubble is re-measured only when the line changes, with
## its label given the new width before the text, because an autowrapped
## Label is measured at whatever width it has at that moment.

const CHIP_SIZE := Vector2(40.0, 14.0)
const CHIP_GAP := 2.0
const BUBBLE_GAP := 4.0
const BUBBLE_WRAP := 180.0
const RELAYOUT_FRAMES := 3

static var chip_style: LabelSettings = TagStyles.chip_label()
static var bubble_style: LabelSettings = TagStyles.bubble_label()

var _chips: VBoxContainer
var _chips_key := ""
## Raw-input gate so the per-entity 38-status scan + chip rebuild only runs when
## the effect/stack arrays actually change, not every frame for every entity.
var _raw_effects: Array = []
var _raw_stacks: Array = []
var _raw_immune: Array = []
var _raw_known := false
var _relayout_frames := 0
var _chips_empty := true
var _bubble: PanelContainer
var _bubble_text: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips = VBoxContainer.new()
	_chips.add_theme_constant_override("separation", int(CHIP_GAP))
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", TagStyles.bubble_box())
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_text = Label.new()
	_bubble_text.label_settings = bubble_style
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.add_child(_bubble_text)
	add_child(_bubble)


## Centred on x = 0 of this control, growing upward from y = 0.
func show_stack(effects: Array, stacks: Array, bubble: Dictionary, immune: Array = []) -> void:
	var top := _show_chips(effects, stacks, immune)
	_show_bubble(top - BUBBLE_GAP if top < 0.0 else 0.0, bubble)


func chip_count() -> int:
	return _chips.get_child_count() if _chips.visible else 0


func has_bubble() -> bool:
	return _bubble.visible


## Returns the top of the stack, or 0 with nothing on it.
func _show_chips(effects: Array, stacks: Array, immune: Array) -> float:
	# Cheap gate: the active-set scan (38 statuses x effects) and chip rebuild run per
	# entity EVERY frame otherwise. Skip both unless the raw effect/stack/immune arrays
	# changed, compared by value (the old string key formatted both arrays every frame).
	if not _raw_known or effects != _raw_effects or stacks != _raw_stacks or immune != _raw_immune:
		_raw_known = true
		_raw_effects = effects.duplicate()
		_raw_stacks = stacks.duplicate()
		_raw_immune = immune.duplicate()
		# Persistent immune pills sit above the live-effect chips.
		var active := StatusChips.active(effects, stacks)
		active.append_array(StatusChips.immune_chips(immune))
		var key := str(active)
		if key != _chips_key:
			_chips_key = key
			for child in _chips.get_children():
				child.free()
			for chip in active:
				_chips.add_child(TagStyles.chip(chip[0], chip[1], CHIP_SIZE, chip_style))
			_relayout_frames = RELAYOUT_FRAMES
		_chips_empty = active.is_empty()
	_chips.visible = not _chips_empty
	if _chips_empty:
		return 0.0
	# Re-measured for a few frames after the set changes, until the new chips'
	# labels have their sizes, rather than every frame for every tag.
	if _relayout_frames > 0:
		_relayout_frames -= 1
		_chips.reset_size()
		_chips.position = Vector2(-CHIP_SIZE.x * 0.5, -_chips.size.y).round()
	return _chips.position.y


func _show_bubble(bottom_y: float, bubble: Dictionary) -> void:
	_bubble.visible = not bubble.is_empty()
	if bubble.is_empty():
		return
	var text: String = bubble["message"]
	if text != _bubble_text.text:
		# A wrapping Label's minimum height is measured at the width it has
		# NOW, and the container gives it its new width only on the next
		# frame: at the last line's width a new line wraps a word a row and
		# the box is drawn a screen tall for that one frame. So the label is
		# given its width, in size as well as minimum, before the text.
		var unwrapped := bubble_style.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			bubble_style.font_size).x
		var width := minf(unwrapped + 1.0, BUBBLE_WRAP)
		_bubble_text.custom_minimum_size.x = width
		_bubble_text.size = Vector2(width, 0.0)
		_bubble_text.text = text
		_bubble.reset_size()
	_bubble.modulate.a = bubble["alpha"]
	_bubble.position = Vector2(-_bubble.size.x * 0.5, bottom_y - _bubble.size.y).round()
