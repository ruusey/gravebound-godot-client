extends GutTest

## New terrain is marked for the fade the first time it is seen, and only then.


func _packet(tiles: Array, map_id := 1) -> Dictionary:
	return {"realmId": 1, "mapId": map_id, "mapWidth": 16, "mapHeight": 16, "tiles": tiles}


func _tile(x: int, y: int, tile_id: int, layer := 0) -> Dictionary:
	return {"tileId": tile_id, "layer": layer, "xIndex": y, "yIndex": x}


func test_first_sight_of_a_cell_is_revealed():
	var tiles := TileMapState.new()
	tiles.apply_load_map(_packet([_tile(2, 3, 5)]))
	assert_true(tiles.revealed_cells.has(Vector2i(2, 3)))


func test_a_changed_tile_is_not_revealed_again():
	var tiles := TileMapState.new()
	tiles.apply_load_map(_packet([_tile(2, 3, 5)]))
	tiles.revealed_cells.clear()
	tiles.apply_load_map(_packet([_tile(2, 3, 6)]))
	assert_true(tiles.revealed_cells.is_empty(), "a wall breaking is not new ground")
	assert_true(tiles.changed_cells.has(Vector2i(2, 3)), "but it still repaints")


func test_void_is_not_revealed():
	var tiles := TileMapState.new()
	tiles.apply_load_map(_packet([_tile(1, 1, 0)]))
	assert_true(tiles.revealed_cells.is_empty())


func test_a_new_map_reveals_everything_again():
	var tiles := TileMapState.new()
	tiles.apply_load_map(_packet([_tile(2, 3, 5)]))
	tiles.revealed_cells.clear()
	tiles.apply_load_map(_packet([_tile(2, 3, 5)], 2))
	assert_true(tiles.revealed_cells.has(Vector2i(2, 3)))
