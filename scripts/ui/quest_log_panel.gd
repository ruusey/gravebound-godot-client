class_name QuestLogPanel
extends CanvasLayer

## The quest log: the web client's Quests panel and its star chip.
##
## The chip ("★ N Stars") is up whenever we are in a realm, just left of the
## minimap -- the web's sits top right, where our minimap is -- and a click
## opens the log, as the toggle_quests key does (L by default, as the
## web's). The log is a card a quest (QuestCard), active first, then
## available, then complete, rebuilt only when the server's snapshot
## changes; Accept and Abandon go as the server's `/quest accept|abandon
## <id>`, the same command a chat line would send.

const HEIGHT_SHARE := 0.8
const TAB_ACTIVE := 0
const TAB_COMPLETED := 1

var state: RealmState
var content: GameData
var client: GraveBoundClient
var shown := false

var chip: Button
var _dialog: PanelContainer
var _stars: Label
var _cards: VBoxContainer
var _search: LineEdit
var _tabs: TabBar
var _tab := TAB_ACTIVE
var _query := ""
var _drawn := -1


func setup(realm_state: RealmState, game_data: GameData, net_client: GraveBoundClient) -> void:
	state = realm_state
	content = game_data
	client = net_client


func _ready() -> void:
	layer = 13
	visible = false
	chip = Button.new()
	chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	chip.offset_right = -(MinimapPanel.MARGIN + MinimapPanel.SIDE + 8)
	chip.offset_top = 32
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.add_theme_color_override("font_color", TagStyles.STAR_GOLD)
	chip.add_theme_font_size_override("font_size", 12)
	# A drawn star icon, not the U+2605 glyph, which the fallback font shows as a
	# missing-glyph box on the web export.
	chip.icon = HudWidgets.star_icon(14)
	chip.tooltip_text = "Open the quest log (L)"
	chip.pressed.connect(toggle)
	add_child(chip)
	# Under the map on a phone, where left of it are Menu, Bag and Chat.
	if PhoneLayout.on:
		chip.offset_right = -PhoneLayout.MARGIN
		chip.offset_top = PhoneLayout.under_map()
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_dialog = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14171f")
	style.border_color = Color("3a4152")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_dialog.add_theme_stylebox_override("panel", style)
	centre.add_child(_dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_dialog.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := HudWidgets.label("QUEST LOG", 16, Color("dfe4ee"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var star_icon := TextureRect.new()
	star_icon.texture = HudWidgets.star_icon(16)
	star_icon.custom_minimum_size = Vector2(16, 16)
	star_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(star_icon)
	_stars = HudWidgets.label("", 14, TagStyles.STAR_GOLD)
	head.add_child(_stars)
	InventoryLayout.button(head, "Close", close)
	_search = LineEdit.new()
	_search.placeholder_text = "Search quests..."
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(QuestCard.WIDTH, 0)
	_search.text_changed.connect(_on_search_changed)
	column.add_child(_search)
	_tabs = TabBar.new()
	_tabs.add_tab("Active")
	_tabs.add_tab("Completed")
	_tabs.tab_changed.connect(_on_tab_changed)
	column.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(QuestCard.WIDTH + 16, 0)
	column.add_child(scroll)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	scroll.add_child(_cards)
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	visible = state != null and state.local.is_present()
	_dialog.visible = visible and shown
	if not visible:
		return
	if _dialog.visible:
		PanelFit.shrink(_dialog)
	chip.text = "%d Stars" % state.progress.stars
	if _dialog.visible and state.progress.version != _drawn:
		refresh()


## Every card to the server's last snapshot, filtered to the open tab and
## matching the search box.
func refresh() -> void:
	_drawn = state.progress.version
	_stars.text = "%d Stars" % state.progress.stars
	for card in _cards.get_children():
		_cards.remove_child(card)
		card.queue_free()
	var quests := state.progress.sorted_quests().filter(_in_tab).filter(_matches_query)
	if quests.is_empty():
		var empty := "No completed quests yet." if _tab == TAB_COMPLETED else "No active quests."
		if _query != "":
			empty = "No quests match \"%s\"." % _query
		_cards.add_child(HudWidgets.label(empty, 13, QuestCard.MUTED))
	for quest in quests:
		_cards.add_child(QuestCard.new(quest, content, act))
	var scroll := _cards.get_parent() as ScrollContainer
	scroll.custom_minimum_size.y = minf(_cards.get_combined_minimum_size().y,
		get_viewport().get_visible_rect().size.y / scale.y * HEIGHT_SHARE - 60.0)


## Completed tab = COMPLETE; Active tab = everything still in play (active or
## not-yet-accepted).
func _in_tab(quest: Dictionary) -> bool:
	var done := AccountProgress.status_of(quest) == AccountProgress.COMPLETE
	return done if _tab == TAB_COMPLETED else not done


func _matches_query(quest: Dictionary) -> bool:
	if _query == "":
		return true
	var hay := "%s %s %s" % [quest.get("name", ""), quest.get("desc", ""), quest.get("cat", "")]
	return _query in hay.to_lower()


func _on_search_changed(text: String) -> void:
	_query = text.strip_edges().to_lower()
	_drawn = -1


func _on_tab_changed(tab: int) -> void:
	_tab = tab
	_drawn = -1


## Accept or abandon, as the server's command.
func act(verb: String, quest_id: int) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send_server_command("/quest %s %d" % [verb, quest_id])
	return true


func toggle() -> void:
	shown = not shown
	_drawn = -1


func close() -> void:
	shown = false


func captures_mouse() -> bool:
	if not visible:
		return false
	var at := chip.get_global_mouse_position()
	return chip.get_global_rect().has_point(at) or (_dialog.visible and _dialog.get_global_rect().has_point(at))


## While the search box holds the keyboard a letter is a letter, not a move.
func is_typing() -> bool:
	return _dialog.visible and _search != null and _search.has_focus()


## A key the chat line or the Controls tab consumed never arrives here.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.is_action_pressed("toggle_quests") and state != null and state.local.is_present():
		toggle()
