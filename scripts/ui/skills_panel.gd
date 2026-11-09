class_name SkillsPanel
extends CanvasLayer

## The character sheet: stats, and the skill points to spend.
##
## A point goes into a hotbar slot, not an ability -- InvestSkillPointPacket
## carries the slot, and the server resolves the binding. It is locked once
## spent, which is why the web client asks first; here the panel is the
## asking, since nothing invests without a click on its own button.

const STATS := ["hp", "mp", "def", "str", "spd", "dex", "vit", "wis"]
const TITLE_COLOUR := Color(1.0, 0.85, 0.42)
const MUTED := Color(0.6, 0.6, 0.65)

var state: RealmState
var content: GameData
var client: GraveBoundClient
var shown := false

var _root: PanelContainer
var _stats: Label
var _points: Label
var _icons: Array = []
var _names: Array = []
var _levels: Array = []
var _buttons: Array = []
var close_button: Button
var _drawn := ""


func setup(realm_state: RealmState, game_data: GameData, net_client: GraveBoundClient) -> void:
	state = realm_state
	content = game_data
	client = net_client


func _ready() -> void:
	# Over the bar and the bag, under the transition cover.
	layer = 13
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(300, 0)
	centre.add_child(_root)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	_line(column, "Character", 16, TITLE_COLOUR)
	_stats = _line(column, "", 12, Color.WHITE)
	_points = _line(column, "", 12, Color.WHITE)
	for slot in AbilityCatalog.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		column.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon)
		_icons.append(icon)
		_names.append(_line(row, "", 12, Color.WHITE))
		_names[slot].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_levels.append(_line(row, "", 12, MUTED))
		var button := Button.new()
		button.text = "Invest"
		button.custom_minimum_size.x = 88
		button.pressed.connect(invest.bind(slot))
		row.add_child(TouchSize.grow(button, 16))
		_buttons.append(button)
	# Menu opens it on a phone, where there is no K to shut it again.
	close_button = TouchSize.grow(InventoryLayout.button(column, "Close", close), 16)
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	visible = state != null and content != null and shown and state.local.is_present()
	if not visible:
		return
	PanelFit.shrink(_root)
	var key := "%d:%d:%s" % [state.local.class_id, state.abilities.version, state.local.stats]
	if key != _drawn:
		refresh()


func refresh() -> void:
	var class_id := state.local.class_id
	_drawn = "%d:%d:%s" % [class_id, state.abilities.version, state.local.stats]
	var stats := PackedStringArray()
	for stat in STATS:
		stats.append("%s %d" % [stat.to_upper(), int(state.local.stats.get(stat, 0))])
	_stats.text = "  ".join(stats)
	var points := state.abilities.available_points
	_points.text = "Skill points: %d" % points
	for slot in AbilityCatalog.SLOTS:
		var id := content.abilities.hotbar_id(class_id, slot)
		var definition := content.abilities.ability(id)
		var bound := not definition.is_empty()
		var level: int = state.abilities.invested[slot]
		var cap := content.abilities.cap(id)
		_icons[slot].texture = content.abilities.icon(id) if bound else null
		_names[slot].text = str(definition.get("name", "")) if bound else "(empty)"
		_levels[slot].text = "%d/%d" % [level, cap] if bound else ""
		_buttons[slot].disabled = not (bound and points > 0 and level < cap)


## One point into a slot. Gated the way the server gates it, so a click
## that would be refused sends nothing.
func invest(slot: int) -> bool:
	if client == null or not client.is_in_game() or slot < 0 or slot >= AbilityCatalog.SLOTS:
		return false
	var id := content.abilities.hotbar_id(state.local.class_id, slot)
	if id <= 0 or state.abilities.available_points <= 0:
		return false
	if state.abilities.invested[slot] >= content.abilities.cap(id):
		return false
	client.send("InvestSkillPointPacket", {"slot": slot})
	return true


func toggle() -> void:
	shown = not shown


func close() -> void:
	shown = false


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())


func _line(into: Container, text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	into.add_child(label)
	return label
