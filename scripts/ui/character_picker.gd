class_name CharacterPicker
extends VBoxContainer

## The account's characters on two pages: the living, and the graveyard.
##
## The data service returns every character the account ever had, the dead
## ones with a `deleted` timestamp. Both references split them the same way
## -- the web client's Characters / Graveyard tabs, the native's greyed
## rows with "Died:" -- and neither lets a dead one be played, since the
## login rejects it.

signal activated()
## A right-click on a character, either page: the web client's stats card.
signal stats_requested(character: Dictionary)

const PAGES := ["Characters", "Graveyard"]
const ALIVE := 0
const GRAVEYARD := 1
## A finger that moves this far down the list is scrolling it, not picking a row.
const DRAG_SCROLL_START := 8.0
## A tap this soon after a drag is not the second half of a double-tap.
const ACTIVATE_AFTER_DRAG_MS := 500
## Room left around the picker on screen when deciding whether both tabs fit.
const TAB_FIT_MARGIN := 64.0

var game_data: GameData
var tabs: TabBar
var list: ItemList

var _pages: Array = [[], []]
var _drag_travel := 0.0
var _drag_scrolling := false
var _drag_ended_ms := -ACTIVATE_AFTER_DRAG_MS
## The row picked before the current touch: the press that starts a drag also
## selects the row under the finger, so a drag puts this one back.
var _resting_selection := -1


func _ready() -> void:
	tabs = TabBar.new()
	for page in PAGES:
		tabs.add_tab(page)
	tabs.tab_changed.connect(func(_index: int) -> void: _fill())
	TabArrows.select_on_scroll(tabs)
	add_child(TouchSize.grow(tabs))
	get_viewport().size_changed.connect(_fit_tabs)
	# Five rows a thumb's height (three on a phone's short screen): the font
	# plus the gap between rows.
	list = ItemList.new()
	list.custom_minimum_size = Vector2(0, TouchSize.PHONE_ROW * 3 if PhoneLayout.on else TouchSize.ROW * 5)
	list.add_theme_font_size_override("font_size", TouchSize.FONT)
	list.add_theme_constant_override("v_separation", 12 if PhoneLayout.on else 22)
	list.item_activated.connect(_on_activated)
	list.gui_input.connect(_on_list_input)
	list.allow_rmb_select = true
	list.item_clicked.connect(_on_clicked)
	add_child(list)


static func is_dead(character: Dictionary) -> bool:
	return character.get("deleted") != null


func show_characters(characters: Array) -> void:
	_pages = [[], []]
	for character in characters:
		_pages[GRAVEYARD if is_dead(character) else ALIVE].append(character)
	for page in PAGES.size():
		tabs.set_tab_title(page, "%s (%d)" % [PAGES[page], _pages[page].size()])
	_fit_tabs()
	# Opens on the living, unless there are none left to open on.
	var wanted := ALIVE if not _pages[ALIVE].is_empty() or _pages[GRAVEYARD].is_empty() else GRAVEYARD
	if tabs.current_tab == wanted:
		_fill()
	else:
		tabs.current_tab = wanted


## Both tabs always show, widening the column to fit, unless the screen is too
## narrow: then the bar clips and its arrows switch tabs (TabArrows).
func _fit_tabs() -> void:
	tabs.clip_tabs = false
	var needed := tabs.get_combined_minimum_size().x
	tabs.clip_tabs = needed > TouchScale.panel_view(self).x - TAB_FIT_MARGIN


func clear() -> void:
	_pages = [[], []]
	list.clear()


## The character under the cursor, or nothing; a dead one is never chosen.
func selected() -> Dictionary:
	var picked := list.get_selected_items()
	if picked.is_empty() or tabs.current_tab != ALIVE:
		return {}
	return _pages[ALIVE][picked[0]]


## Puts the cursor on the last living character: the data service appends
## a new one to the account, so after a create that is the one just made.
func select_newest() -> void:
	tabs.current_tab = ALIVE
	if list.item_count > 0:
		list.select(list.item_count - 1)
		_resting_selection = list.item_count - 1


func _on_activated(_index: int) -> void:
	if Time.get_ticks_msec() - _drag_ended_ms < ACTIVATE_AFTER_DRAG_MS:
		return
	activated.emit()


## Touch drags scroll the rows directly; the list's scrollbar is too thin for a thumb.
func _on_list_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_travel = 0.0
			_drag_scrolling = false
		elif _drag_scrolling:
			_drag_scrolling = false
			_drag_ended_ms = Time.get_ticks_msec()
		else:
			var picked := list.get_selected_items()
			_resting_selection = picked[0] if not picked.is_empty() else -1
	elif event is InputEventScreenDrag:
		_drag_travel += absf(event.relative.y)
		if not _drag_scrolling:
			if _drag_travel < DRAG_SCROLL_START:
				return
			_drag_scrolling = true
			if _resting_selection >= 0 and _resting_selection < list.item_count:
				list.select(_resting_selection)
		list.get_v_scroll_bar().value -= event.relative.y
		list.accept_event()


func _on_clicked(index: int, _at: Vector2, button: int) -> void:
	var page: Array = _pages[tabs.current_tab]
	if button == MOUSE_BUTTON_RIGHT and index < page.size():
		stats_requested.emit(page[index])


func alive_count() -> int:
	return _pages[ALIVE].size()


func dead_count() -> int:
	return _pages[GRAVEYARD].size()


func _fill() -> void:
	list.clear()
	for character in _pages[tabs.current_tab]:
		list.add_item(describe(character, game_data))
	_resting_selection = -1
	if list.item_count > 0:
		list.select(0)
		_resting_selection = 0


## One line per character: class, the two stats that matter at the door,
## then for the living the fame it would bank on death now, and for the
## fallen the day they fell -- the native client's "Died:".
static func describe(character: Dictionary, content: GameData) -> String:
	var stats: Dictionary = character.get("stats", {})
	var line := "%s  hp %s  spd %s" % [class_label(character, content),
		stat_text(stats.get("hp")), stat_text(stats.get("spd"))]
	if is_dead(character):
		line += "  died %s" % String(character.get("deleted", "")).substr(0, 10)
	elif content != null:
		line += "  fame %s" % Mastery.thousands(content.levels.fame_for(int(stats.get("xp", 0))))
	return line


## A stat as a whole number. The service's JSON reaches us as floats --
## JSON.parse_string makes every number one -- so a bare str() read
## "hp 130.0"; a stat the service left out is "?".
static func stat_text(value: Variant) -> String:
	return str(roundi(value)) if value is float or value is int else "?"


static func class_label(character: Dictionary, content: GameData) -> String:
	var class_id := int(character.get("characterClass", 0))
	return content.classes_art.display_name(class_id) if content else "class %d" % class_id
