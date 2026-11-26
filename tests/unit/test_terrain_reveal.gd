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



# The layer itself: walking dissolves new ground in, arriving never does.
var state: RealmState
var reveal: TerrainReveal
var now := [100.0]


func _start(settle := true) -> void:
	state = RealmState.new()
	reveal = TerrainReveal.new()
	reveal.state = state
	now = [100.0]
	var clock_box := now
	reveal.clock = func() -> float: return clock_box[0]
	state.local.id = 1
	state.local.position = Vector2(16, 16)
	add_child_autofree(reveal)
	_land([Vector2i(0, 0), Vector2i(1, 0)])
	_step(0.0)
	if settle:
		_step(1.0)


func _land(cells: Array) -> void:
	var tiles: Array = []
	for cell: Vector2i in cells:
		tiles.append(_tile(cell.x, cell.y, 5))
	state.tiles.apply_load_map(_packet(tiles))


func _step(seconds: float) -> void:
	now[0] += seconds
	reveal.refresh()
	state.tiles.cleared = false


func test_entering_a_map_shows_at_once():
	_start(false)
	assert_eq(reveal.active_count(), 0)


func test_walked_into_ground_dissolves_in():
	_start()
	_land([Vector2i(2, 0)])
	_step(0.0)
	assert_eq(reveal.active_count(), 1)
	assert_almost_eq(reveal.shown(Vector2i(2, 0)), 0.0, 0.001, "covered as it lands")
	_step(TerrainReveal.DURATION_S * 0.5)
	assert_between(reveal.shown(Vector2i(2, 0)), 0.1, 0.9, "partway")
	assert_eq(reveal.shown(Vector2i(0, 0)), 1.0, "known ground is never covered")


func test_a_teleport_lifts_every_cover_and_shows_what_follows():
	_start()
	_land([Vector2i(2, 0)])
	_step(0.0)
	state.local.position += Vector2(TerrainReveal.TELEPORT_PX + 1.0, 0)
	_step(0.0)
	assert_eq(reveal.active_count(), 0, "the cover from before the jump is gone")
	_land([Vector2i(5, 1)])
	_step(TerrainReveal.ARRIVAL_GRACE_S * 0.5)
	assert_eq(reveal.active_count(), 0, "ground landing just after the jump shows at once")


func test_the_setting_turns_it_off():
	_start()
	state.settings.set_on("terrain_fade_in", false)
	_land([Vector2i(2, 0)])
	_step(0.0)
	assert_eq(reveal.active_count(), 0)
