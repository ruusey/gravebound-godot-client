class_name TileMapState
extends RefCounted

## Terrain the server has revealed, and the collision queries derived from it.
##
## Only tileId travels on the wire; every flag is reconstructed from the
## client's own tiles.json. The queries below mirror TileManager and the two
## reference clients exactly, because every place they differ is a tick the
## server disagrees with: solidity is an 85% top-left-anchored hitbox against
## the collision layer, plus the map's edge and the void cells of the base
## layer; the slow test samples ONE point of the base layer, under the feet.

const TILE_SIZE := GameConstants.TILE_SIZE
const COLLISION_LAYER := GameConstants.COLLISION_LAYER
const BASE_LAYER := 0

var realm_id := 0
var map_id := 0
## > -1 once the realm is an assembled dungeon. New in v0.9.0.
var dungeon_id := -1
var width := 0
var height := 0
## layer -> {Vector2i(tileX, tileY): tileId}
var layers := {}
## What changed since the ground last redrew (TileRenderer takes both).
var changed_cells := {}   # Vector2i -> true; a re-sent, unchanged id is none
## Cells seen for the first time on this map, for TerrainReveal to fade in.
var revealed_cells := {}   # Vector2i -> true
## Breakable walls' crack overlay stage (1-3), collision layer only.
var cracks := {}   # Vector2i -> stage; intact cells are absent
var cleared := false

var _content: GameData


func _init(content: GameData = null) -> void:
	_content = content


func clear() -> void:
	layers.clear()
	cracks.clear()
	changed_cells.clear()
	revealed_cells.clear()
	cleared = true


func tile_count() -> int:
	var total := 0
	for layer in layers:
		total += layers[layer].size()
	return total


## Applies a LoadMapPacket. Returns true when this is a different place, which
## invalidates every entity and tile we were holding.
##
## LoadMap fires on every tile-stream chunk, not only on a transition, so a
## move is an id change -- and the *map* id counts as well as the realm's: a
## dungeon assembled inside the realm you are already in reuses its realm id,
## and watching only that leaves the previous map's tiles underneath it.
func apply_load_map(data: Dictionary) -> bool:
	var incoming := int(data.get("realmId", 0))
	var incoming_map := int(data.get("mapId", 0))
	var incoming_dungeon := int(data.get("dungeonId", -1))
	var changed := incoming != realm_id or incoming_map != map_id \
		or incoming_dungeon != dungeon_id
	if changed:
		clear()

	realm_id = incoming
	map_id = incoming_map
	dungeon_id = incoming_dungeon
	width = int(data.get("mapWidth", 0))
	height = int(data.get("mapHeight", 0))

	# A realm's first packet carries every tile in view, so this loop stays to
	# dictionary reads: the layer's table is looked up only when the layer changes.
	var current_layer := -1
	var cells: Dictionary = {}
	for tile in data.get("tiles", []):
		var layer := int(tile.get("layer", 0))
		if layer != current_layer:
			current_layer = layer
			if not layers.has(layer):
				layers[layer] = {}
			cells = layers[layer]
		# NetTile's field names lie: TileManager reads getTiles()[y][x] and then
		# builds `new NetTile(id, layer, y, x)`, so xIndex carries the ROW and
		# yIndex the COLUMN. Reading them at face value transposes the map --
		# invisible at a spawn on the diagonal, and progressively wrong the
		# further you walk from it. The web client swaps them the same way.
		var cell := Vector2i(int(tile.get("yIndex", 0)), int(tile.get("xIndex", 0)))
		var tile_id := int(tile.get("tileId", -1))
		if cells.get(cell) != tile_id:
			if tile_id != 0 and not cells.has(cell):
				revealed_cells[cell] = true
			cells[cell] = tile_id
			changed_cells[cell] = true
		if layer == COLLISION_LAYER:
			var stage := int(tile.get("crackStage", 0))
			if stage != int(cracks.get(cell, 0)):
				_apply_crack(cell, stage)
	return changed


func crack_at(cell: Vector2i) -> int:
	return int(cracks.get(cell, 0))


func _apply_crack(cell: Vector2i, stage: int) -> void:
	if crack_at(cell) == stage:
		return
	if stage > 0:
		cracks[cell] = stage
	else:
		cracks.erase(cell)
	changed_cells[cell] = true


## Whether the ground under an entity's feet slows it.
func slows(position: Vector2, entity_size: int) -> bool:
	var tile_id := _feet_tile(position, entity_size)
	return tile_id > 0 and _content.tile_slows(tile_id)


## Whether an entity stands in water or lava, and is drawn sunk into it. Keyed
## on the tile's liquid, not on slowing: bushes and swamp slow without being
## liquid, and speed paths "slow" by a negative factor.
func wades(position: Vector2, entity_size: int) -> bool:
	var tile_id := _feet_tile(position, entity_size)
	return tile_id > 0 and _content.tile_submerges(tile_id)


## The movement speed multiplier for the base-layer tile under the feet: 1.0 off a
## slow tile, 1/3 for a full slow, >1 on a speed-up tile. Mirrors the server's
## TileManager.slowSpeedMul so prediction stays in sync.
func slow_mul(position: Vector2, entity_size: int) -> float:
	var tile_id := _feet_tile(position, entity_size)
	return _content.tile_speed_mul(tile_id) if tile_id > 0 else 1.0


## The base-layer tile under an entity's feet, or -1.
##
## Mirror of TileManager.feetOnFlaggedTile, which all three clients copy:
## one sample of the BASE layer at the horizontal middle and the BOTTOM of
## the hitbox. Sampling the centre instead, or the collision layer, is a
## third of a step of disagreement on every tick spent in shallow water --
## which the nexus has plenty of -- and reads as a correction on every ack.
func _feet_tile(position: Vector2, entity_size: int) -> int:
	if _content == null:
		return -1
	var column := floori((position.x + entity_size * 0.5) / TILE_SIZE)
	var row := floori((position.y + entity_size) / TILE_SIZE)
	return layers.get(BASE_LAYER, {}).get(Vector2i(column, row), -1)


func tile_at(layer: int, tile_x: int, tile_y: int) -> int:
	return layers.get(layer, {}).get(Vector2i(tile_x, tile_y), -1)


## Whether an entity may stand at `position` (its top-left): the server's
## collisionTile, collidesXLimit / collidesYLimit and isVoidTile together,
## which its movePlayer asks of every axis of a step.
func blocks(position: Vector2, entity_size: int) -> bool:
	if _content == null:
		return false
	if _off_the_map(position, entity_size) or _on_void(position, entity_size):
		return true
	var layer: Dictionary = layers.get(COLLISION_LAYER, {})
	if layer.is_empty():
		return false

	var hit_size := floorf(float(entity_size) * GameConstants.COLLISION_HITBOX_SCALE)
	# Centre the reduced hitbox on the sprite. A top-left anchor left all the slack on the
	# right/bottom and none on the left/top, so a player clipped a few px into a wall from
	# the left/top and that intruded cell then occluded on-screen enemies. MUST match the
	# server (TileManager.collisionTile / collidesAtPosition).
	var inset := (float(entity_size) - hit_size) * 0.5
	var box := Rect2(position + Vector2(inset, inset), Vector2(hit_size, hit_size))
	var first := Vector2i(floori(box.position.x / TILE_SIZE), floori(box.position.y / TILE_SIZE))
	var last := Vector2i(floori(box.end.x / TILE_SIZE), floori(box.end.y / TILE_SIZE))
	# A wall taller than two cells is solid down its whole face, so one standing a few
	# rows north can still reach the box (TileManager.collisionBounds on the server).
	var north := first.y - (_content.tallest_solid_rows() - 1)

	for tile_x in range(first.x, last.x + 1):
		for tile_y in range(north, last.y + 1):
			var tile_id: int = layer.get(Vector2i(tile_x, tile_y), -1)
			if tile_id < 0 or not _content.tile_has_collision(tile_id):
				continue
			var rows := _content.tile_solid_rows(tile_id)
			if Rect2(tile_x * TILE_SIZE, tile_y * TILE_SIZE, TILE_SIZE, TILE_SIZE * rows).intersects(box):
				return true
	return false


## The map's edge, with the whole sprite rather than the hitbox; nothing to
## hit before a map has a size.
func _off_the_map(position: Vector2, entity_size: int) -> bool:
	if width <= 0 or height <= 0:
		return false
	return position.x <= 0.0 or position.x + entity_size >= width * TILE_SIZE \
		or position.y <= 0.0 or position.y + entity_size >= height * TILE_SIZE


## A void cell of the base layer under the entity's centre is a hole in the
## world. The server tests the centre after the move; a cell it never sent
## inside the map is void too (the stream carries no id-0 tiles).
func _on_void(position: Vector2, entity_size: int) -> bool:
	var base: Dictionary = layers.get(BASE_LAYER, {})
	if base.is_empty():
		return false
	var cell := Vector2i(floori((position.x + entity_size * 0.5) / TILE_SIZE),
		floori((position.y + entity_size * 0.5) / TILE_SIZE))
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	return base.get(cell, 0) <= 0
