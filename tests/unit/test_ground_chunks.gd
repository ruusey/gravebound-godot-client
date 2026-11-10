extends GutTest

## The ground drawn once and kept, in chunks: nothing is drawn again while
## nothing changes, a changed tile redraws only the chunks it can touch,
## explored ground stays drawn off screen, and a new map drops it all.

var renderer: WorldRenderer
var state: RealmState
var data: GameData
var camera: Camera2D


func before_each():
	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(data, func() -> int: return 0)
	renderer = WorldRenderer.new()
	renderer.setup(state, data)
	add_child_autofree(renderer)
	camera = Camera2D.new()
	add_child_autofree(camera)
	camera.make_current()


func after_each():
	WallBandPass.enabled = true


func _ground(tiles: Array, realm := 1) -> void:
	state.apply_packet("LoadMapPacket", {"realmId": realm, "tiles": tiles})


func _frames(count := 2) -> void:
	await wait_process_frames(count)


func _chunk(at: Vector2i) -> GroundChunk:
	return renderer.tiles.chunks.chunks.get(at)


func _draws() -> Dictionary:
	var out := {}
	for at in renderer.tiles.chunks.chunks:
		out[at] = renderer.tiles.chunks.chunks[at].draws
	return out


func test_a_tile_resent_as_it_was_is_no_change():
	_ground([WireHelper.tile(1, 0, 3, 4)])
	assert_eq(state.tiles.changed_cells, {Vector2i(3, 4): true})
	state.tiles.changed_cells.clear()
	_ground([WireHelper.tile(1, 0, 3, 4)])
	assert_true(state.tiles.changed_cells.is_empty(), "the server re-sends what we have")
	_ground([WireHelper.tile(2, 0, 3, 4)])
	assert_eq(state.tiles.changed_cells, {Vector2i(3, 4): true})
	state.tiles.clear()
	assert_true(state.tiles.cleared)
	assert_true(state.tiles.changed_cells.is_empty())


func test_standing_still_draws_the_ground_once():
	_ground([WireHelper.tile(1, 0, 0, 0), WireHelper.tile(1, 0, 3, 3)])
	await _frames()
	var first := _draws()
	assert_false(first.is_empty())
	assert_true(first.values().all(func(n: int) -> bool: return n == 1), "each chunk once: %s" % first)
	await _frames(30)
	var later := _draws()
	for at in first:
		assert_eq(later[at], 1, "chunk %s: thirty more frames, not drawn again" % at)
	assert_true(later.values().all(func(n: int) -> bool: return n == 1),
		"the ring ahead filled in meanwhile, each of those once too")
	await _frames(5)
	assert_eq(_draws(), later, "and once the ring is full, nothing more at all")


func test_a_changed_tile_redraws_only_the_chunks_it_touches():
	_ground([WireHelper.tile(1, 0, 5, 5), WireHelper.tile(1, 0, -5, 5)])
	await _frames()
	var before := _draws()
	assert_true(before.has(Vector2i(0, 0)) and before.has(Vector2i(-1, 0)))
	_ground([WireHelper.tile(2, 0, 5, 5)])
	await _frames()
	var after := _draws()
	assert_eq(after[Vector2i(0, 0)], before[Vector2i(0, 0)] + 1, "the chunk holding the cell")
	assert_eq(after[Vector2i(-1, 0)], before[Vector2i(-1, 0)], "a chunk it cannot reach stands")
	# One cell from the border: the seam and the ring around the neighbour.
	_ground([WireHelper.tile(2, 0, 0, 5)])
	await _frames()
	var edge := _draws()
	assert_eq(edge[Vector2i(0, 0)], after[Vector2i(0, 0)] + 1)
	assert_eq(edge[Vector2i(-1, 0)], after[Vector2i(-1, 0)] + 1, "the neighbour across the border too")


func test_ground_walked_away_from_is_kept_not_drawn_again():
	_ground([WireHelper.tile(1, 0, 0, 0), WireHelper.tile(1, 0, 200, 200)])
	await _frames()
	var home := _chunk(Vector2i(0, 0))
	assert_not_null(home)
	camera.position = Vector2(200, 200) * GameConstants.TILE_SIZE
	await _frames(4)
	assert_not_null(_chunk(GroundChunk.of(Vector2i(200, 200))), "the far ground is drawn on arrival")
	camera.position = Vector2.ZERO
	await _frames(4)
	assert_eq(_chunk(Vector2i(0, 0)), home, "the same chunk, kept")
	assert_eq(home.draws, 1, "and never drawn again")


func test_a_new_map_drops_every_chunk():
	_ground([WireHelper.tile(1, 0, 0, 0)])
	await _frames()
	var old := _chunk(Vector2i(0, 0))
	_ground([WireHelper.tile(1, 0, 1, 1)], 2)
	await _frames()
	assert_false(is_instance_valid(old) and old.is_inside_tree() and _chunk(Vector2i(0, 0)) == old,
		"the old realm's ground is gone")
	assert_eq(renderer.draw_stats["tiles"], 1)


func test_switching_the_wall_bands_redraws_the_ground():
	_ground([WireHelper.tile(1, 0, 0, 0)])
	await _frames()
	var before := _chunk(Vector2i(0, 0)).draws
	WallBandPass.enabled = false
	await _frames()
	assert_eq(_chunk(Vector2i(0, 0)).draws, before + 1)


func test_the_ground_ahead_is_drawn_a_couple_of_chunks_a_frame():
	var view := GroundChunks.over(ViewRect.of(renderer.tiles))
	var chunks := GroundChunks.new()
	var ground := TileRenderer.new()
	add_child_autofree(ground)
	chunks.update(ground, ViewRect.of(ground))
	var seen := view.get_area()
	assert_eq(chunks.chunks.size(), seen + GroundChunks.PREFETCH,
		"everything in view at once, then %d of the ring" % GroundChunks.PREFETCH)
	chunks.update(ground, ViewRect.of(ground))
	assert_eq(chunks.chunks.size(), seen + 2 * GroundChunks.PREFETCH)


func test_a_stale_strip_is_repainted_a_few_chunks_a_frame_not_all_at_once():
	# Drive update() directly: the first call fills the whole view (entry), so the
	# chunks exist; a small zoom makes the view span many chunks.
	var chunks := GroundChunks.new()
	var ground := TileRenderer.new()
	add_child_autofree(ground)
	camera.zoom = Vector2(0.25, 0.25)
	var view := ViewRect.of(ground)
	chunks.update(ground, view)
	var seen := GroundChunks.over(view)
	# Every in-view chunk now goes stale at once -- a streamed tile diff, or walking
	# into a fresh strip of ground.
	var in_view: Array = chunks.chunks.keys().filter(func(at: Vector2i) -> bool:
		return seen.has_point(at))
	for at in in_view:
		chunks.dirty[at] = true
	assert_gt(in_view.size(), GroundChunks.MAX_IN_VIEW_REDRAW,
		"need more in-view chunks than the per-frame cap for this to mean anything")
	# One update clears (repaints) at most the cap of them; the rest stay stale for
	# the following frames (_draw erases the dirty flag of a chunk it repaints).
	chunks.update(ground, view)
	var repainted := 0
	for at in in_view:
		if not chunks.dirty.has(at):
			repainted += 1
	assert_lte(repainted, GroundChunks.MAX_IN_VIEW_REDRAW,
		"a stale strip repaints a few chunks a frame, not all at once: %d of %d" % [repainted, in_view.size()])


func test_a_chunk_takes_the_grounds_material():
	_ground([WireHelper.tile(1, 0, 0, 0)])
	await _frames()
	assert_true(_chunk(Vector2i(0, 0)).use_parent_material, "a shader on the ground reaches it")


func test_neighbouring_chunks_overlap_so_no_line_of_background_shows():
	# A clip is cut in whole screen pixels; two cut edge to edge left a line
	# across the nexus in a 1920x961 browser. tests/visual/seam_scan.gd
	# looks for it on screen.
	var west := GroundChunk.new(Vector2i(0, 0))
	var east := GroundChunk.new(Vector2i(1, 0))
	var south := GroundChunk.new(Vector2i(0, 1))
	autofree(west)
	autofree(east)
	autofree(south)
	assert_gt(west.clip().end.x, east.clip().position.x, "east and west overlap")
	assert_gt(west.clip().end.y, south.clip().position.y, "north and south overlap")
	assert_lte(west.clip().end.x - east.area().position.x, float(GameConstants.TILE_SIZE),
		"by less than the ring each chunk also paints, where both draw the same ground")
