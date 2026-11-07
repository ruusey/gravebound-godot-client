class_name WallStroke
extends RefCounted

## A dark outline around walls, drawn the same way every other sprite outline is:
## offset copies of the wall's own texture, tinted dark, stamped BEHIND the body so
## the body covers the centre and only a rim shows. Called before the collision
## bodies. Only the top, left and right are stroked (never the bottom), and only on a
## side facing open ground -- a side that abuts another wall is skipped and its body
## covers any protrusion, so a run of walls reads as one block under one outline.
## Unlike WallBands (square walls only) this covers tall walls too, stroking their
## full drawn height.

const TILE := float(GameConstants.TILE_SIZE)

static var enabled := true


## Offset silhouette copies for every wall in view; call before the collision bodies.
func paint_under(canvas: CanvasItem, tiles: TileMapState, content: GameData,
		first: Vector2i, last: Vector2i) -> void:
	if not enabled:
		return
	var walls: Dictionary = tiles.layers.get(GameConstants.COLLISION_LAYER, {})
	if walls.is_empty():
		return
	var looks: Dictionary = content.tile_looks
	for tile_x in range(first.x, last.x + 1):
		for tile_y in range(first.y, last.y + 1):
			var cell := Vector2i(tile_x, tile_y)
			var tile_id: int = walls.get(cell, 0)
			if tile_id <= 0:
				continue
			var look: Array = looks.get(tile_id, GameData.NO_LOOK)
			if look.is_empty():
				look = content.tile_look(tile_id)
			if not look[GameData.LOOK_FLAGS] & GameData.LOOK_WALL:
				continue
			var texture: Texture2D = look[GameData.LOOK_TEXTURE]
			if texture == null:
				continue
			# The wall body draws cell-wide and LOOK_HEIGHT tall, anchored at the cell
			# top (tall walls spill one cell south); outline the whole drawn rect.
			var rect := Rect2(tile_x * TILE, tile_y * TILE, TILE, look[GameData.LOOK_HEIGHT])
			if not WallBands.is_wall_at(tiles, content, cell + Vector2i(0, -1)):
				_stamp(canvas, texture, rect, Vector2(0.0, -SpriteOutline.OFFSET))
			if not WallBands.is_wall_at(tiles, content, cell + Vector2i(-1, 0)):
				_stamp(canvas, texture, rect, Vector2(-SpriteOutline.OFFSET, 0.0))
			if not WallBands.is_wall_at(tiles, content, cell + Vector2i(1, 0)):
				_stamp(canvas, texture, rect, Vector2(SpriteOutline.OFFSET, 0.0))


func _stamp(canvas: CanvasItem, texture: Texture2D, rect: Rect2, offset: Vector2) -> void:
	canvas.draw_texture_rect(texture, Rect2(rect.position + offset, rect.size), false, SpriteOutline.TINT)
