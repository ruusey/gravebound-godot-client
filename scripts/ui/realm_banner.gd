class_name RealmBanner
extends CanvasLayer

## The realm's name and difficulty along the top of the screen, and, while
## a corrupted realm is being cleansed, how far that has come.
##
## The web client's realm-info line and its purification bar in one place:
## the name from the map (or what the server called the realm, which is
## all a dungeon has), the difficulty in the colour both references use,
## green through yellow and orange to red; and under it, only while the
## realm has a purification goal, the tier and the percentage and the
## modifiers -- what RealmPurificationPacket carries.

const MARGIN_TOP := 8.0
const NAME_SIZE := 16
const DETAIL_SIZE := 13
## A phone draws the name and the purification line at about a third of
## that: at full size they ran across half the screen.
const PHONE_SCALE := 0.35

var state: RealmState
var content: GameData
## Off for a scripted render that is about something else.
var shown := true

var _column: VBoxContainer
var _name: Label
var _detail: Label

## The realm fields last drawn, so the per-frame tick skips rebuilding the text
## and re-applying the colour override (which invalidates the theme cache) when
## nothing about the realm changed -- which is every frame but the handful it does.
var _drawn_name := ""
var _drawn_difficulty := -1.0
var _drawn_goal := -1
var _drawn_progress := -1
var _drawn_tier := -1
var _drawn_modifiers := ""


func setup(realm_state: RealmState, game_data: GameData) -> void:
	state = realm_state
	content = game_data


func _ready() -> void:
	layer = 11
	visible = false
	_column = VBoxContainer.new()
	_column.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_column.offset_top = MARGIN_TOP
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_name = _line(text_size(NAME_SIZE, PhoneLayout.on))
	_detail = _line(text_size(DETAIL_SIZE, PhoneLayout.on))
	_detail.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	TouchFrame.adopt(self)


func _line(size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	if PhoneLayout.on:
		label.add_theme_font_override("font", PhoneLayout.small_font(size))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2 if PhoneLayout.on else 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(label)
	return label


func _process(_delta: float) -> void:
	var name := realm_name()
	visible = shown and state != null and state.local.is_present() and not state.transition_pending and name != ""
	if not visible:
		return
	if PhoneLayout.on:
		var width := _column.get_combined_minimum_size().x
		_column.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_column.position = PhoneLayout.banner_at(TouchScale.view_size(_column), width)
		_column.size = Vector2(width, _column.size.y)
	var realm: Dictionary = state.minimap.realm
	var difficulty := float(realm.get("difficulty", 0.0))
	var goal := int(realm.get("goal", 0))
	var progress := int(realm.get("progress", 0))
	var tier := int(realm.get("tier", 0))
	var modifiers := String(realm.get("modifiers", ""))
	if name == _drawn_name and difficulty == _drawn_difficulty and goal == _drawn_goal \
			and progress == _drawn_progress and tier == _drawn_tier and modifiers == _drawn_modifiers:
		return
	_drawn_name = name
	_drawn_difficulty = difficulty
	_drawn_goal = goal
	_drawn_progress = progress
	_drawn_tier = tier
	_drawn_modifiers = modifiers
	_name.text = name if difficulty <= 0.0 else "%s   %s" % [name, PortalCard.number(difficulty)]
	_name.add_theme_color_override("font_color", difficulty_colour(difficulty) if difficulty > 0.0 else Color.WHITE)
	_detail.text = purification(realm)
	_detail.visible = _detail.text != ""


## A line's font size: as given, or scaled down for a phone.
static func text_size(size: int, phone: bool) -> int:
	return maxi(5, roundi(size * PHONE_SCALE)) if phone else size


## The server's own name for the realm if it sent one, the map's otherwise.
func realm_name() -> String:
	if state == null:
		return ""
	if state.transition.zone != "":
		return state.transition.zone
	return "" if content == null else content.maps.name(state.tiles.map_id).replace("_", " ")


## The web client's line, only while there is a goal.
static func purification(realm: Dictionary) -> String:
	var goal := int(realm.get("goal", 0))
	if goal <= 0:
		return ""
	var percent := clampi(roundi(int(realm.get("progress", 0)) * 100.0 / goal), 0, 100)
	var tier := int(realm.get("tier", 0))
	var line := ("Tier %d - Purification %d%%" % [tier, percent]) if tier > 1 else "Realm Purification - %d%%" % percent
	var modifiers := String(realm.get("modifiers", ""))
	return line + ("  -  " + modifiers if modifiers != "" else "")


## Green through yellow and orange to red as difficulty rises: the web
## client's realm-info colour, which it says matches the native's.
static func difficulty_colour(difficulty: float) -> Color:
	if difficulty <= 2.0:
		return Color8(60, 180, 60)
	if difficulty <= 4.0:
		return Color8(180, 160, 40)
	if difficulty <= 6.0:
		return Color8(220, 80, 40)
	return Color8(255, 40, 40)
