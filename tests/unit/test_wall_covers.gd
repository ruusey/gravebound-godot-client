extends GutTest

## A tall wall is drawn among the bodies at the depth of its solid cell's south edge:
## whole (top and face together), over what stands behind it and under what stands in
## front -- never its top over a body its face is under.

const SIZE := GameConstants.TILE_SIZE
## Tile 6 in the fixture is an 8x16 wall: top face in its cell, front face a row south.
const TALL_WALL := 6
const SQUARE_WALL := 2

var data: GameData
var state: RealmState
var probe: Node2D


func before_each():
	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(data, func() -> int: return 10_000)
	var script := GDScript.new()
	# Draws the covers due before one body at `depth`, then the rest, as EntityRenderer does.
	script.source_code = "\n".join([
		"extends Node2D",
		"var covers := WallCovers.new()",
		"var depth := 0",
		"var before := -1",
		"func _draw():",
		"\tcovers.draw_through(self, depth)",
		"\tbefore = covers.drawn",
		"\tcovers.draw_rest(self)",
	])
	script.reload()
	probe = Node2D.new()
	probe.set_script(script)
	add_child_autofree(probe)


func _covers_before(body_top: float, body_size: float) -> int:
	probe.covers.collect(state, data, Rect2(-200, -200, 400, 400))
	probe.depth = EntityQueue.depth({"pos": Vector2(0.0, body_top), "size": body_size})
	probe.queue_redraw()
	await wait_process_frames(2)
	return probe.before


func _walls(cells: Dictionary) -> void:
	var tiles: Array = []
	for cell in cells:
		tiles.append(WireHelper.tile(cells[cell], GameConstants.COLLISION_LAYER, cell.x, cell.y))
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": tiles})


func test_a_large_body_in_front_of_a_wall_draws_over_all_of_it():
	# Feet on the face row south of the wall, sprite reaching up past the top face.
	_walls({Vector2i(0, 0): TALL_WALL})
	assert_eq(await _covers_before(SIZE * 1.5 - 64.0, 64.0), 1, "the wall goes down first")


func test_a_body_behind_a_wall_is_covered_by_it():
	_walls({Vector2i(0, 1): TALL_WALL})
	assert_eq(await _covers_before(SIZE * 1.0 - 48.0, 48.0), 0, "the wall draws over it")
	assert_eq(probe.covers.drawn, 1)


func test_a_body_level_with_the_solid_edge_stays_behind():
	_walls({Vector2i(0, 0): TALL_WALL})
	assert_eq(await _covers_before(SIZE - 40.0, 40.0), 0)


func test_a_square_wall_is_never_redrawn():
	_walls({Vector2i(0, 0): SQUARE_WALL})
	assert_eq(await _covers_before(SIZE * 1.5 - 40.0, 40.0), 0)
	assert_eq(probe.covers.drawn, 0)


func test_a_face_stops_where_a_tile_below_was_drawn_over_it():
	var walls := {Vector2i(0, 0): TALL_WALL}
	assert_eq(WallCovers._shown_height(walls, Vector2i(0, 0), SIZE * 2.0), SIZE * 2.0, "open floor: the whole face")
	walls[Vector2i(0, 1)] = SQUARE_WALL
	assert_eq(WallCovers._shown_height(walls, Vector2i(0, 0), SIZE * 2.0), float(SIZE), "only the top face")
