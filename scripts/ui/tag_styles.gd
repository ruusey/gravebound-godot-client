class_name TagStyles
extends RefCounted

## The looks the entity tags share: the web client's text styles as
## LabelSettings, its bubble box as a StyleBox, and a chip.

## The web's gold for a player's quest stars.
const STAR_GOLD := Color("ffd34d")
## The light blue of a player's [guild] tag.
const GUILD_BLUE := Color("8fd8ff")


## 16px bold with a 3px black stroke: PIXI.Text {fontSize: 16, fontWeight:
## 'bold', stroke: 0x000000, strokeThickness: 3}.
static func name_label() -> LabelSettings:
	return _label(bold(), 16, Color.WHITE, 3)


## A player's quest stars: the name's style in the web's gold. Its own
## settings, because a LabelSettings colour wins over a theme override.
static func star_label() -> LabelSettings:
	return _label(bold(), 16, STAR_GOLD, 3)


## A player's [guild] tag under the name: smaller, in light blue.
static func guild_label() -> LabelSettings:
	return _label(bold(), 12, GUILD_BLUE, 3)


## 24px bold with a 4px stroke, the damage numbers.
static func damage_label() -> LabelSettings:
	return _label(bold(), 24, Color.WHITE, 4)


static func chip_label() -> LabelSettings:
	return _label(ThemeDB.fallback_font, 11, Color.WHITE, 0)


static func bubble_label() -> LabelSettings:
	return _label(ThemeDB.fallback_font, 12, Color("1a1a1a"), 0)


static func caption_label() -> LabelSettings:
	return _label(ThemeDB.fallback_font, 14, Color(0.75, 0.7, 1.0), 2)


## White at 0.95 with a faint border, rounded at 10, padded 8 by 5.
static func bubble_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 1.0, 1.0, 0.95)
	box.border_color = Color("c8c0b0")
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 5.0
	box.content_margin_bottom = 5.0
	return box


## One chip: the effect's colour, black-bordered, with its label centred.
static func chip(text: String, colour: Color, extent: Vector2, style: LabelSettings) -> PanelContainer:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour, 0.92)
	box.border_color = Color(0.0, 0.0, 0.0, 0.85)
	box.set_border_width_all(1)
	box.set_content_margin_all(0.0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = extent
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.label_settings = style
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


static func bold() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.6
	return font


static func _label(font: Font, size: int, colour: Color, outline: int) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = font
	settings.font_size = size
	settings.font_color = colour
	settings.outline_size = outline
	settings.outline_color = Color.BLACK
	return settings
