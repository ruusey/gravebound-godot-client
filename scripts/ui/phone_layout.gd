class_name PhoneLayout
extends RefCounted

## Where the HUD goes with touch controls, in the panels' points
## (TouchFrame): the vitals top-left with the party and nearby lists under
## them, the map top-right with Menu, Bag and Chat in a column beside it and
## the quest stars under it, the realm's name between the two where it fits
## (under the stars where it does not), the chat bottom-left over the move
## stick, and the touch layer's Attack cluster bottom-right. Main turns it
## on with the touch controls, before the layers are built.

const MARGIN := 8.0
const GAP := 6.0
const MAP_SIDE := 104.0
const BUTTON_SIZE := Vector2(60.0, 30.0)
const BUTTON_FONT := 13
const VITALS_WIDTH := 200.0
const CHAT_WIDTH := 300.0
## The phone's chat: small lines, five of them in the box three used to
## fill. A 7pt row is 10 tall, and the lines sit CHAT_GAP apart.
const CHAT_LINES := 5
const CHAT_FONT := 7
const CHAT_GAP := 1
const CHAT_ROW := 10.0 + CHAT_GAP
## A row under the map: the quest stars' chip.
const CHIP_ROW := 30.0
const GAME_FONT := "res://assets/fonts/game_font.tres"

static var on := false
## The game font per small size, its spaces kept (small_font).
static var _small_fonts := {}
## Where the vitals end; PlayerHud keeps it up to date as it draws.
static var vitals_bottom := MARGIN
## The open bag fills the left column; the party and nearby lists give way.
static var bag_open := false
## The touch buttons' extent in the canvas's pixels, for the chat to clear.
static var thumbs := Rect2()


static func column_taken() -> bool:
	return on and bag_open


## Where the left column starts, under the vitals.
static func column_top() -> float:
	return vitals_bottom + GAP


## Where a left-column panel's fold chip goes: its usual corner, or the
## column's edge once folded, where the panel it would sit on is gone.
static func chip_x(panel_right: float, chip_width: float, folded: bool) -> float:
	return MARGIN if on and folded else panel_right - chip_width - 2.0


## Under the map, where the right column carries on.
static func under_map() -> float:
	return MARGIN + MAP_SIDE + GAP


## Where the realm's name sits, `width` wide: centred between the vitals and
## the buttons when it fits there, else right-aligned under the stars.
static func banner_at(screen: Vector2, width: float) -> Vector2:
	var left := MARGIN + VITALS_WIDTH + GAP
	var right := buttons_at(screen).x - GAP
	if width <= right - left:
		return Vector2((left + right - width) * 0.5, MARGIN)
	return Vector2(screen.x - MARGIN - width, under_map() + CHIP_ROW + GAP)


## The map's square in the top-right corner of `screen`.
static func map_rect(screen: Vector2) -> Rect2:
	return Rect2(screen.x - MARGIN - MAP_SIDE, MARGIN, MAP_SIDE, MAP_SIDE)


## The top-left corner of the Menu, Bag and Chat column, left of the map.
static func buttons_at(screen: Vector2) -> Vector2:
	return Vector2(map_rect(screen).position.x - GAP - BUTTON_SIZE.x, MARGIN)


## The game font for text under its usual sizes. Its flat -5 on every space
## suits 12pt and more, but swallows the space whole at 7 and under, and the
## words run together; this one trims each size to a third of its height.
static func small_font(size: int) -> Font:
	if _small_fonts.has(size):
		return _small_fonts[size]
	var font: FontVariation = (load(GAME_FONT) as FontVariation).duplicate()
	var raw := font.base_font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	font.spacing_space = maxi(2, roundi(size / 3.0)) - roundi(raw)
	_small_fonts[size] = font
	return font
