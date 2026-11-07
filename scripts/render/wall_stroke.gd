class_name WallStroke
extends RefCounted

## A crisp black outline on the top, left, and right of every wall (never the
## bottom). The side is drawn only where open ground lies beyond, so a wall that
## abuts another wall is left unstroked on that side and a run of walls -- square
## or tall -- reads as one block under a single continuous outline. Unlike
## WallBands this also covers tall (8x16) walls, stroking their full drawn height
## so a vertical stack stays seamless.

const TILE := float(GameConstants.TILE_SIZE)
const STROKE := Color(0.04, 0.04, 0.063, 0.88)
const THICK := 2.0

static var enabled := true


func paint(canvas: CanvasItem, tiles: TileMapState, content: GameData,
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
			# Tall walls draw their top face at the cell and spill one cell south;
			# stroke the full drawn silhouette so stacked walls stay continuous.
			var height: float = look[GameData.LOOK_HEIGHT]
			var x := tile_x * TILE
			var y := tile_y * TILE
			if not WallBands.is_wall_at(tiles, content, cell + Vector2i(0, -1)):
				canvas.draw_rect(Rect2(x, y, TILE, THICK), STROKE)
			if not WallBands.is_wall_at(tiles, content, cell + Vector2i(-1, 0)):
				canvas.draw_rect(Rect2(x, y, THICK, height), STROKE)
			if not WallBands.is_wall_at(tiles, content, cell + Vector2i(1, 0)):
				canvas.draw_rect(Rect2(x + TILE - THICK, y, THICK, height), STROKE)
