class_name HudWidgets
extends RefCounted

## The player HUD's parts, built from Godot's own controls.
##
## Construction only, as InventoryLayout is for the bag: a bar is a
## ProgressBar with flat style boxes and a label laid over it, a stat cell
## is a caption, a value and the equipment bonus beside it. PlayerHud owns
## the state and writes the text; this knows what the pieces look like.

const BAR_HEIGHT := 16
const BAR_BACK := Color(0.08, 0.08, 0.1, 0.9)
const TEXT_SIZE := 12
const CAPTION := Color(0.7, 0.7, 0.75)
const STAR_GOLD := Color("ffd34d")
## The plain font, for prose and anything typed: the game font has ASCII only.
const TEXT_FONT := preload("res://assets/fonts/open-sans-semibold.woff2")

## Cached star textures, keyed by size and colour.
static var _star_icons := {}

## Cached game logo. Built from the raw PNG bytes (res://logo.bin), NOT the
## imported res://icon.png: the texture import's .ctex isn't loadable in the
## web/GL-compat export, so every runtime load of icon.png returned null and the
## logo showed nowhere. Reading the raw bytes into an ImageTexture sidesteps the
## importer, so the same file works on web and desktop.
static var _logo: ImageTexture
## The one-line wordmark (res://logo_banner.bin), cropped to its lettering.
static var _banner: ImageTexture


## The stacked game logo as a texture, or null if the raw asset is missing.
## Callers must null-check (a missing logo is cosmetic and must never hard-fail).
static func logo_texture() -> ImageTexture:
	if _logo == null:
		_logo = _raw_png("res://logo.bin")
	return _logo


## The one-line wordmark, for wide headers; null-checked like logo_texture.
static func banner_texture() -> ImageTexture:
	if _banner == null:
		_banner = _raw_png("res://logo_banner.bin")
	return _banner


static func _raw_png(path: String) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(image)


## A gold five-pointed star drawn into a texture, used instead of the U+2605
## glyph for the quest-star display: the fallback font renders that glyph as a
## missing-glyph box on the web export, so an icon that does not depend on the
## font's coverage is used. Rasterised once per size/colour, then cached.
static func star_icon(size := 16, colour := STAR_GOLD) -> ImageTexture:
	var key := "%d:%s" % [size, colour.to_html()]
	if _star_icons.has(key):
		return _star_icons[key]
	var points := PackedVector2Array()
	var centre := size * 0.5
	for i in 10:
		var radius := size * 0.48 if i % 2 == 0 else size * 0.20
		var angle := -PI * 0.5 + float(i) * PI / 5.0
		points.append(Vector2(centre + cos(angle) * radius, centre + sin(angle) * radius))
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var solid := Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points)
			image.set_pixel(x, y, colour if solid else Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(image)
	_star_icons[key] = texture
	return texture


## A filled bar with its text centred over the fill: [bar, label]. A
## party row's bars are a few pixels tall and carry no text.
static func bar(into: Container, fill: Color, height := BAR_HEIGHT) -> Array:
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, height)
	progress.show_percentage = false
	progress.max_value = 1.0
	progress.step = 0.0
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_theme_stylebox_override("background", _flat(BAR_BACK))
	progress.add_theme_stylebox_override("fill", _flat(fill))
	into.add_child(progress)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(label)
	return [progress, label]


## Recolour a bar's fill: the XP bar turns gold once it is fame.
static func refill(progress: ProgressBar, fill: Color) -> void:
	progress.add_theme_stylebox_override("fill", _flat(fill))


## One cell of the stats grid: "STR" over "75 +5", as [value, bonus].
static func stat_cell(into: Container, caption: String) -> Array:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	into.add_child(column)
	column.add_child(label(caption, 10, CAPTION))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	column.add_child(row)
	var value := label("", TEXT_SIZE, Color.WHITE)
	row.add_child(value)
	var bonus := label("", 10, Color.WHITE)
	row.add_child(bonus)
	return [value, bonus]


static func label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _flat(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(2)
	return box
