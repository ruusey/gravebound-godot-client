class_name SocialPanel
extends CanvasLayer

## The friends and guild directory, on the toggle_social key (` by default):
## a Friends tab and a Guild tab, online players first, each filtered to all,
## online or offline and searchable by name. An online row can be messaged,
## visited, summoned or traded with; a friend can be removed. Hovering an online
## row shows their character and gear. Someone can be on both tabs.
##
## The server sends the lists (SocialStatusPacket) and re-checks every action.

const WIDTH := 560.0
const LIST_HEIGHT := 320.0
const ICON := 28
const TITLE_COLOUR := Color(1.0, 0.85, 0.42)
const MUTED := Color("887868")
const OFFLINE_TINT := Color(0.45, 0.45, 0.45, 1.0)
const LOCATION_COLOUR := Color("c8a86e")
const FILTER_NAMES := ["All", "Online", "Offline"]

var state: RealmState
var content: GameData
var actions: SocialActions

var guild_tab := false
var filter := SocialState.Filter.ALL

var _root: PanelContainer
var _tab_buttons: Array[Button] = []
var _filter_buttons: Array[Button] = []
var _search: LineEdit
var _list: VBoxContainer
var _empty: Label
var _add_row: HBoxContainer
var _add_input: LineEdit
var _count: Label
var _inspect: PlayerInspectCard
var _confirm: ConfirmPopup
var _drawn := ""


func setup(realm_state: RealmState, game_data: GameData, social_actions: SocialActions) -> void:
	state = realm_state
	content = game_data
	actions = social_actions


func _ready() -> void:
	layer = 14
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(WIDTH, 0)
	centre.add_child(_root)
	var column := InventoryLayout.column(_root)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var title := InventoryLayout.heading(bar, "FRIENDS & GUILD")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", TITLE_COLOUR)
	InventoryLayout.button(bar, "Close", close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for guild in [false, true]:
		var tab := InventoryLayout.button(tabs, "", show_tab.bind(guild))
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tab_buttons.append(tab)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	column.add_child(filters)
	for which in SocialState.Filter.values():
		var button := InventoryLayout.button(filters, FILTER_NAMES[which], set_filter.bind(which))
		button.toggle_mode = true
		_filter_buttons.append(button)
	_search = LineEdit.new()
	_search.placeholder_text = "search names"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _drawn = "")
	filters.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_empty = HudWidgets.label("", 12, MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_empty)
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 8)
	column.add_child(_add_row)
	_add_input = LineEdit.new()
	_add_input.placeholder_text = "player name"
	_add_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_input.text_submitted.connect(func(_t: String) -> void: _add_friend())
	_add_row.add_child(_add_input)
	InventoryLayout.button(_add_row, "Add Friend", _add_friend)
	_count = HudWidgets.label("", 11, MUTED)
	column.add_child(_count)
	_inspect = PlayerInspectCard.new()
	_inspect.setup(content)
	add_child(_inspect)
	_confirm = ConfirmPopup.new()
	add_child(_confirm)
	TouchFrame.adopt(self)


func toggle() -> void:
	if visible:
		close()
	elif state != null and state.local.is_present():
		visible = true
		_drawn = ""


func close() -> void:
	visible = false
	_inspect.hide_card()


func show_tab(guild: bool) -> void:
	guild_tab = guild
	_drawn = ""


func set_filter(which: int) -> void:
	filter = which
	_drawn = ""


func _process(_delta: float) -> void:
	if not visible:
		return
	if state == null or not state.local.is_present():
		close()
		return
	PanelFit.shrink(_root)
	var key := "%d|%s|%d|%s|%s" % [state.social.version, guild_tab, filter, _search.text, state.guild.in_guild]
	if key != _drawn:
		_drawn = key
		_refresh()


func _refresh() -> void:
	var social := state.social
	_tab_buttons[0].text = "Friends  %d/%d" % [social.online_count(false), social.listed(false, SocialState.Filter.ALL).size()]
	_tab_buttons[1].text = "Guild  %d/%d" % [social.online_count(true), social.listed(true, SocialState.Filter.ALL).size()]
	_tab_buttons[0].button_pressed = not guild_tab
	_tab_buttons[1].button_pressed = guild_tab
	for which in _filter_buttons.size():
		_filter_buttons[which].button_pressed = which == filter
	_inspect.hide_card()
	for child in _list.get_children():
		child.queue_free()
	var rows := social.listed(guild_tab, filter, _search.text)
	for entry in rows:
		_list.add_child(_row(entry))
	_empty.visible = rows.is_empty()
	_empty.text = empty_text(guild_tab, state.guild.in_guild, filter, _search.text)
	_add_row.visible = not guild_tab
	_count.visible = not guild_tab
	_count.text = "%d / %d friends" % [social.friend_count(), social.max_friends]


## What the list says when nothing is in it.
static func empty_text(guild: bool, in_guild: bool, which: int, search: String) -> String:
	if guild and not in_guild:
		return "You are not in a guild."
	if search.strip_edges() != "":
		return "Nobody by that name."
	if which == SocialState.Filter.ONLINE:
		return "Nobody is online."
	if which == SocialState.Filter.OFFLINE:
		return "Nobody is offline."
	return "Nobody in your guild yet." if guild else "No friends yet. Add one by name below."


## The line under a name: level, class and where they are, or that they are offline.
static func detail(entry: Dictionary, class_label: String) -> String:
	if not entry["online"]:
		return "Offline"
	var where := String(entry["location"])
	var line := "Lv %d %s" % [int(entry["level"]), class_label]
	if where != "":
		line += "  -  " + where
	if entry["same_realm"]:
		line += "  (here)"
	return line


func _row(entry: Dictionary) -> Control:
	var name := String(entry["name"])
	var online := bool(entry["online"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if online and content != null:
		icon.texture = content.classes_art.frame(int(entry["class_id"]), "idle", "front", 0, int(entry["dye_id"]))
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var heading := name
	if entry["guild"]:
		heading += "  [%s]" % GuildState.rank_name(int(entry["rank"]))
	if guild_tab and entry["friend"]:
		heading += "  Friend"
	var colour := NameColours.GUILDMATE if guild_tab else NameColours.FRIEND
	var title := HudWidgets.label(heading, 13, colour if online else OFFLINE_TINT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title)
	var cls := content.classes_art.display_name(int(entry["class_id"])) if content != null else ""
	var sub := HudWidgets.label(detail(entry, cls), 11, LOCATION_COLOUR if online else MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(sub)
	if online:
		InventoryLayout.button(row, "Msg", func() -> void:
			if actions.message(name):
				close())
		InventoryLayout.button(row, "Visit", func() -> void:
			if actions.visit(name):
				close())
		InventoryLayout.button(row, "Summon", func() -> void: actions.summon(name))
		InventoryLayout.button(row, "Trade", func() -> void: actions.trade(name))
		row.mouse_entered.connect(_show_inspect.bind(entry, row))
		row.mouse_exited.connect(_inspect.hide_card)
	if not guild_tab:
		InventoryLayout.button(row, "Remove", func() -> void:
			_confirm.request("Remove %s from your friends?" % name, "Remove",
				func() -> void: actions.remove_friend(name)))
	return row


func _show_inspect(entry: Dictionary, row: Control) -> void:
	_inspect.show_player({
		"name": entry["name"],
		"class_id": int(entry["class_id"]),
		"dye_id": int(entry["dye_id"]),
		"level": int(entry["level"]),
		"guild": state.guild.guild_name if entry["guild"] else "",
		"equipment": entry["equipment"],
	})
	var rect := _root.get_global_rect()
	_inspect.show_at(Vector2(rect.end.x + 8.0, row.global_position.y))


func _add_friend() -> void:
	if actions != null and actions.add_friend(_add_input.text):
		_add_input.text = ""


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())


## Typing a name in the search or add box must not walk the player.
func is_typing() -> bool:
	return visible and (_search.has_focus() or _add_input.has_focus())


## A key the chat line or the Controls tab consumed never arrives here.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.is_action_pressed("toggle_social") and state != null and state.local.is_present():
		toggle()
		get_viewport().set_input_as_handled()
