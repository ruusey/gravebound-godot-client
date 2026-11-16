class_name LootPreview
extends Panel

## The small grid of what a loot bag holds, shown under it on the ground:
## the web client's renderLootPreviews, one container's worth.
##
## Its sizes are the web's screen pixels as they are -- five columns of
## 15px cells, 11px icons, 2px of padding, two rows at most -- on a dark box
## with a thin gold edge and 3px corners. A vault chest shows all its slots,
## empty ones as dim cells, so an empty chest still reads as somewhere to put
## things. Strictly something to look at: it takes no mouse, so a click
## through it lands on the world as it would on the web's non-interactive layer.

const COLUMNS := 5
const ROWS := 2
const CELL := 15
const PAD := 2
const ICON := 11
## Below the bag's bottom edge.
const DROP := 4
const BACKGROUND := Color(0x0a / 255.0, 0x0a / 255.0, 0x0c / 255.0, 0.72)
const EDGE := Color(0xc8 / 255.0, 0xa8 / 255.0, 0x6e / 255.0, 0.55)
const SLOT := Color(0.2, 0.18, 0.15, 0.95)
const SLOT_EDGE := Color(0xc8 / 255.0, 0xa8 / 255.0, 0x6e / 255.0, 0.45)

var _icons: Array[TextureRect] = []
var _shown := 0
## A chest's slot count; 0 for a bag, which shows only what it holds.
var _slots := 0
## The container id and item-id signature last filled, so a frame that finds
## the contents unchanged skips the whole rebuild (reassigning ten TextureRects
## and a queue_redraw) and only repositions. Driven every frame by EntityOverlay.
var _filled := false
var _fill_id := 0
var _fill_sig := PackedInt32Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", style)
	for i in COLUMNS * ROWS:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size = Vector2(ICON, ICON)
		icon.position = cell_origin(i)
		add_child(icon)
		_icons.append(icon)


## Whether the grid must be refilled for this container and signature, or the
## contents are what it already holds and the caller need only reposition it.
## Textures depend on item id alone, so the id list is the whole signature.
func needs_fill(id: int, sig: PackedInt32Array) -> bool:
	if _filled and id == _fill_id and sig == _fill_sig:
		return false
	_filled = true
	_fill_id = id
	_fill_sig = sig
	return true


## What of a container's items the grid shows: the real ones, in order, as
## many as two rows hold.
static func shown_items(items: Array) -> Array:
	var real := items.filter(func(item: Variant) -> bool: return Inventory.holds(item))
	return real.slice(0, COLUMNS * ROWS)


## The grid's size for `count` items: a row as wide as it needs, up to five.
static func grid_size(count: int) -> Vector2:
	var columns := mini(count, COLUMNS)
	var rows := ceili(float(count) / COLUMNS)
	return Vector2(columns * CELL + PAD, rows * CELL + PAD)


## Where the icon for the i'th item sits inside the box.
static func cell_origin(i: int) -> Vector2:
	var inset := PAD + (CELL - ICON) / 2.0 - PAD / 2.0
	return Vector2(inset + (i % COLUMNS) * CELL, inset + floori(float(i) / COLUMNS) * CELL)


## Fills the grid; `textures` is one a shown item, null where the item has
## no art (the web leaves that cell empty).
func show_items(textures: Array) -> void:
	_slots = 0
	_shown = textures.size()
	size = grid_size(_shown)
	for i in _icons.size():
		var icon := _icons[i]
		icon.texture = textures[i] if i < _shown else null
		icon.visible = icon.texture != null
	queue_redraw()


## A chest: every slot in place, `textures` one a slot with null where it is
## empty.
func show_slots(textures: Array) -> void:
	_slots = mini(textures.size(), _icons.size())
	_shown = textures.filter(func(texture: Variant) -> bool: return texture != null).size()
	size = grid_size(_slots)
	for i in _icons.size():
		var icon := _icons[i]
		icon.texture = textures[i] if i < _slots else null
		icon.visible = icon.texture != null
	queue_redraw()


func _draw() -> void:
	for i in _slots:
		var cell := Rect2(cell_origin(i) - Vector2.ONE, Vector2.ONE * (ICON + 2))
		draw_rect(cell, SLOT)
		draw_rect(cell, SLOT_EDGE, false, 1.0)


func slot_count() -> int:
	return _slots


## Centred under the bag's bottom-middle point, on a whole pixel.
func place(anchor: Vector2) -> void:
	position = Vector2(roundf(anchor.x - size.x / 2.0), roundf(anchor.y + DROP))


func icon_count() -> int:
	return _icons.filter(func(icon: TextureRect) -> bool: return icon.visible).size()


func item_count() -> int:
	return _shown
