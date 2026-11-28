class_name PlayerInspectCard
extends PanelContainer

## A floating hover pane for another player -- the parity version of the old
## clients' inspect panel. Shows the class sprite, name (+ role badge), level and
## class, its [guild], HP/MP, and when the data carries them (party members, via the richer
## PartyUpdatePacket) the six stats and the equipped items as icons.
##
## One instance per panel, reused: populate it and show_at() on row hover, hide()
## on exit. It ignores the mouse itself so it never steals hover from the row.

const SPRITE := 40
const ITEM := 26
const EQUIP_SLOTS := 5
const NAME_COLOUR := Color("fff0a0")
const MUTED := Color("887868")
const HP_COLOUR := Color("e05555")
const MP_COLOUR := Color("5577e0")
const STAT_COLOUR := Color("c8a86e")
const SLOT_BG := Color(0.11, 0.09, 0.13, 1.0)

var _content: GameData
var _sprite: TextureRect
var _name: Label
var _guild: Label
var _sub: Label
var _hp: Label
var _mp: Label
var _stats1: Label
var _stats2: Label
var _equip_row: HBoxContainer
var _equip_cells: Array = []


func _init() -> void:
	visible = false
	z_index = 4096
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.08, 0.96)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.4, 0.35, 0.3)
	bg.set_content_margin_all(6)
	add_theme_stylebox_override("panel", bg)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(SPRITE, SPRITE)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_sprite)
	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 1)
	head_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(head_col)
	_name = _line(head_col, 13, NAME_COLOUR)
	_guild = _line(head_col, 11, TagStyles.GUILD_BLUE)
	_sub = _line(head_col, 11, MUTED)
	_hp = _line(head_col, 11, HP_COLOUR)
	_mp = _line(head_col, 11, MP_COLOUR)

	_stats1 = _line(column, 11, STAT_COLOUR)
	_stats2 = _line(column, 11, STAT_COLOUR)

	_equip_row = HBoxContainer.new()
	_equip_row.add_theme_constant_override("separation", 3)
	_equip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_equip_row)
	for i in EQUIP_SLOTS:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(ITEM, ITEM)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cell_bg := StyleBoxFlat.new()
		cell_bg.bg_color = SLOT_BG
		cell.add_theme_stylebox_override("panel", cell_bg)
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(pic)
		_equip_row.add_child(cell)
		_equip_cells.append(pic)


func setup(content: GameData) -> void:
	_content = content


## data keys: name, role, guild, class_id, dye_id, level, hp, max_hp, mp, max_mp,
## stats (Dictionary or {}), equipment (Array of item dicts or []). Without
## max_hp / max_mp their lines are left out.
func show_player(data: Dictionary) -> void:
	var cls := _content.classes_art.display_name(int(data.get("class_id", 0)))
	_sprite.texture = _content.classes_art.frame(int(data.get("class_id", 0)), "idle", "front", 0,
		int(data.get("dye_id", 0)))
	var role := String(data.get("role", ""))
	var player_name := String(data.get("name", ""))
	_name.text = (player_name if player_name != "" else cls) + (("  [%s]" % role) if role != "" else "")
	_name.add_theme_color_override("font_color", NameColours.role(role))
	var guild := String(data.get("guild", ""))
	_guild.visible = guild != ""
	_guild.text = "[%s]" % guild
	_sub.text = "Lv %d  %s" % [int(data.get("level", 0)), cls]
	_hp.text = "HP %d/%d" % [int(data.get("hp", 0)), int(data.get("max_hp", 0))]
	_mp.text = "MP %d/%d" % [int(data.get("mp", 0)), int(data.get("max_mp", 0))]
	# The directory knows a player's gear but not their vitals.
	_hp.visible = data.has("max_hp")
	_mp.visible = data.has("max_mp")

	var stats: Dictionary = data.get("stats", {})
	var has_stats := not stats.is_empty()
	_stats1.visible = has_stats
	_stats2.visible = has_stats
	if has_stats:
		_stats1.text = "STR %d   DEF %d   SPD %d   DEX %d" % [int(stats.get("str", 0)),
			int(stats.get("def", 0)), int(stats.get("spd", 0)), int(stats.get("dex", 0))]
		_stats2.text = "VIT %d   WIS %d" % [int(stats.get("vit", 0)), int(stats.get("wis", 0))]

	var equipment: Array = data.get("equipment", [])
	_equip_row.visible = not equipment.is_empty()
	for i in EQUIP_SLOTS:
		var item: Dictionary = equipment[i] if i < equipment.size() and equipment[i] is Dictionary else {}
		var item_id := int(item.get("itemId", -1))
		_equip_cells[i].texture = _content.item_texture(item_id) if item_id >= 0 else null
	visible = true
	reset_size()


## Pin the card near a screen point, kept inside the viewport.
func show_at(screen_pos: Vector2) -> void:
	var view := TouchScale.view_size(self)
	position = Vector2(
		clampf(screen_pos.x, 0.0, maxf(0.0, view.x - size.x)),
		clampf(screen_pos.y, 0.0, maxf(0.0, view.y - size.y)))


func hide_card() -> void:
	visible = false


func _line(into: Container, size_px: int, colour: Color) -> Label:
	var label := HudWidgets.label("", size_px, colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	into.add_child(label)
	return label
