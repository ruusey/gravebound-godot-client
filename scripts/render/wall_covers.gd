class_name WallCovers
extends RefCounted

## Tall walls and large decorations, redrawn in among the bodies at their own depth.
##
## The tile pass draws every wall under the entities. That alone lets a body standing
## behind a wall draw over it, so each tall wall is drawn again -- top face and front
## face together -- at the depth of its solid footprint's south edge, merged into the
## entities' feet order: a body whose feet are south of that edge is in front and draws
## over the whole wall, and one north of it is covered by the whole wall. Redrawing
## only the top face (above every body) covered a large sprite standing in front of
## the wall wherever it reached up past the face.
##
## A face is cut off at the first row below it holding another collision tile: the tile
## pass draws that tile over the spill, and redrawing the face would cover it.
##
## Oversized decorations (large trees) are drawn the same way, as their canopy: from the
## sprite's top down to the trunk cell's south edge, at that edge's depth.

const NO_COVER: Array = []
const COVER_TEXTURE := 0
const COVER_CANOPY := 1
const COVER_RECT := 2
const COVER_SOLID_ROWS := 3
const NO_SOURCE := Rect2()

## Covers drawn last frame.
var drawn := 0
## tile id -> _resolve_cover(); cleared when the content changes.
var _covers := {}
var _covers_for: GameData
## Sorted (depth << 16 | entry) keys, and the cursor of the next one to draw.
var _keys := PackedInt64Array()
var _next := 0
var _textures: Array = []
var _dests: Array = []
var _sources: Array = []
var _cracks: Array = []
var _crack_sources: Array = []


## Gathers this frame's covers in view, in depth order.
func collect(state: RealmState, content: GameData, view: Rect2) -> void:
	drawn = 0
	_next = 0
	_keys.resize(0)
	_textures.clear()
	_dests.clear()
	_sources.clear()
	_cracks.clear()
	_crack_sources.clear()
	if state == null or content == null:
		return
	if _covers_for != content or not content.ready:
		_covers.clear()
		_covers_for = content
	var walls: Dictionary = state.tiles.layers.get(GameConstants.COLLISION_LAYER, {})
	if walls.is_empty():
		return

	var size := GameConstants.TILE_SIZE
	var spill := content.tallest_spill_rows()
	# A face spills south and a canopy sideways, so walls just outside the view still reach into it.
	var first := Vector2i(floori(view.position.x / size) - 1, floori(view.position.y / size) - 1 - spill)
	var last := Vector2i(ceili(view.end.x / size) + 1, ceili(view.end.y / size) + 1)
	var looks: Dictionary = content.tile_looks
	var cracks: Dictionary = state.tiles.cracks
	for tile_x in range(first.x, last.x + 1):
		for tile_y in range(first.y, last.y + 1):
			var cell := Vector2i(tile_x, tile_y)
			var tile_id: int = walls.get(cell, 0)
			if tile_id <= 0:
				continue
			var cover: Array = _covers.get(tile_id, NO_COVER)
			if cover.is_empty():
				cover = _resolve_cover(tile_id, content, looks)
				_covers[tile_id] = cover
			var texture: Texture2D = cover[COVER_TEXTURE]
			if texture == null:
				continue
			var at := Vector2(tile_x * size, tile_y * size)
			var rect: Rect2 = cover[COVER_RECT]
			var dest := Rect2(at + rect.position, rect.size)
			var source := NO_SOURCE
			var crack: Texture2D = null
			var crack_source := NO_SOURCE
			if not cover[COVER_CANOPY]:
				var shown := _shown_height(walls, cell, rect.size.y)
				if shown < rect.size.y:
					var fraction := shown / rect.size.y
					var texture_size := texture.get_size()
					source = Rect2(0.0, 0.0, texture_size.x, texture_size.y * fraction)
					dest.size.y = shown
				var stage := int(cracks.get(cell, 0)) if not cracks.is_empty() else 0
				if stage > 0:
					crack = content.crack_overlay(stage)
					if crack != null and source != NO_SOURCE:
						var crack_size := crack.get_size()
						crack_source = Rect2(0.0, 0.0, crack_size.x, crack_size.y * shown / rect.size.y)
			var base := at.y + size * int(cover[COVER_SOLID_ROWS])
			_keys.append(((int(roundf(base * 16.0)) + EntityQueue.FEET_BIAS) << 16) | _textures.size())
			_textures.append(texture)
			_dests.append(dest)
			_sources.append(source)
			_cracks.append(crack)
			_crack_sources.append(crack_source)
	_keys.sort()


## Draws every cover a body at `depth` (EntityQueue.depth) stands in front of.
func draw_through(canvas: CanvasItem, depth: int) -> void:
	var count := _keys.size()
	while _next < count and (_keys[_next] >> 16) < depth:
		_draw_cover(canvas, _keys[_next] & 0xFFFF)
		_next += 1


## Draws the covers no body stood in front of.
func draw_rest(canvas: CanvasItem) -> void:
	var count := _keys.size()
	while _next < count:
		_draw_cover(canvas, _keys[_next] & 0xFFFF)
		_next += 1


func _draw_cover(canvas: CanvasItem, entry: int) -> void:
	var dest: Rect2 = _dests[entry]
	var source: Rect2 = _sources[entry]
	if source == NO_SOURCE:
		canvas.draw_texture_rect(_textures[entry], dest, false)
	else:
		canvas.draw_texture_rect_region(_textures[entry], dest, source)
	var crack: Texture2D = _cracks[entry]
	if crack != null:
		var crack_source: Rect2 = _crack_sources[entry]
		if crack_source == NO_SOURCE:
			canvas.draw_texture_rect(crack, dest, false)
		else:
			canvas.draw_texture_rect_region(crack, dest, crack_source)
	drawn += 1


## How much of a wall's art at `cell` still shows on the ground: its top face, then each
## spilled face row down to the first one another collision tile was drawn over.
static func _shown_height(walls: Dictionary, cell: Vector2i, art_height: float) -> float:
	var size := float(GameConstants.TILE_SIZE)
	var shown := size
	var row := 1
	while shown < art_height and walls.get(cell + Vector2i(0, row), 0) <= 0:
		shown = minf(art_height, shown + size)
		row += 1
	return shown


## What a tile id redraws among the bodies: [texture, is canopy, the rect it covers
## relative to the cell's top-left, solid rows its depth sits below]. A canopy is the top
## of a large decoration down to its trunk cell's south edge; a tall wall is its whole
## art (null texture for a tile that is neither).
func _resolve_cover(tile_id: int, content: GameData, looks: Dictionary) -> Array:
	var size := float(GameConstants.TILE_SIZE)
	var cell_rect := Rect2(0.0, 0.0, size, size)
	var draw_rect := content.tile_render_rect(tile_id, cell_rect)
	if draw_rect != cell_rect:
		var cover_h := size - draw_rect.position.y
		var canopy := content.tile_canopy(tile_id, cover_h / draw_rect.size.y)
		return [canopy, true, Rect2(draw_rect.position, Vector2(draw_rect.size.x, cover_h)), 1]
	var look: Array = looks.get(tile_id, GameData.NO_LOOK)
	if look.is_empty():
		look = content.tile_look(tile_id)
	var height: float = look[GameData.LOOK_HEIGHT]
	if height <= size:
		return [null, false, cell_rect, 1]
	return [look[GameData.LOOK_TEXTURE], false, Rect2(0.0, 0.0, size, height), content.tile_solid_rows(tile_id)]
