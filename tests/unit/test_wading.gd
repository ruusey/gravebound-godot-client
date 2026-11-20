extends GutTest

## Standing in water or lava: the legs go under, and only ours do.

var state: RealmState
var content: GameData
var queue := EntityQueue.new()

## The unit suite runs against the fixture content, where 10 is liquid water
## and 3 (Swamp) slows without being a liquid.
const WET := 10
const SWAMP := 3
const GRASS := 1
const VIEW := Rect2(-500, -500, 1000, 1000)


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(
		ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content)


func _ground(tile_id: int) -> void:
	var tiles: Array = []
	for x in range(-2, 3):
		for y in range(-2, 3):
			tiles.append({"tileId": tile_id, "layer": 0, "xIndex": y, "yIndex": x})
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 2, "tiles": tiles})


func _stand(position: Vector2) -> void:
	state.local.id = 1
	state.local.position = position
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", position)]})


# --- who is in the water ---------------------------------------------------

func test_the_feet_decide_not_the_middle():
	# Sampled at the bottom of the hitbox, so the body sinks exactly as the
	# feet enter rather than when the waist crosses the line. Water on row 1
	# (y 32..64) is the case that tells the two samplings apart.
	_ground(GRASS)
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 2, "tiles": [
		{"tileId": WET, "layer": 0, "xIndex": 1, "yIndex": 0}]})
	assert_true(state.tiles.wades(Vector2(0, 0), 32),
		"feet at y=32 are in it while the middle at y=16 is not")
	assert_false(state.tiles.wades(Vector2(0, 32), 32),
		"and the middle being in it is not enough once the feet are past")


func test_dry_ground_is_not_waded():
	_ground(GRASS)
	assert_false(state.tiles.wades(Vector2(0, 0), 32))


func test_a_slowing_tile_that_is_not_a_liquid_is_not_waded():
	_ground(SWAMP)
	assert_true(state.tiles.slows(Vector2(0, 0), 32), "it still slows")
	assert_false(state.tiles.wades(Vector2(0, 0), 32), "but the feet stay out")


func test_only_water_and_lava_submerge():
	content.library.tiles[SWAMP]["data"]["liquid"] = "acid"
	content.library.tiles[GRASS]["data"]["liquid"] = "lava"
	assert_true(content.tile_submerges(WET), "water")
	assert_true(content.tile_submerges(GRASS), "lava")
	assert_false(content.tile_submerges(SWAMP), "another liquid animates but does not sink you")


func test_an_unknown_tile_is_not_water():
	assert_false(state.tiles.wades(Vector2(0, 0), 32), "nothing loaded at all")


func test_water_is_read_off_the_ground_not_the_collision_layer():
	# The slow test for movement mirrors the server against the collision
	# layer; this one is about what is drawn, and water is terrain.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 2, "tiles": [
		{"tileId": WET, "layer": GameConstants.COLLISION_LAYER, "xIndex": 1, "yIndex": 0}]})
	assert_false(state.tiles.wades(Vector2(0, 0), 32))


func test_only_the_player_we_are_wades():
	_ground(WET)
	state.local.id = 1
	state.local.position = Vector2(0, 0)
	state.apply_packet("LoadPacket", {"players": [
		WireHelper.player(1, "me", Vector2(0, 0)),
		WireHelper.player(2, "you", Vector2(64, 0)),
	]})
	var items := queue.build(state, content, VIEW)
	assert_eq(items.size(), 2)
	var wading := 0
	for item in items:
		if item.get("wading", false):
			wading += 1
	assert_eq(wading, 1, "ours goes under; the one standing beside us does not")


# --- the geometry ----------------------------------------------------------

func test_the_body_sinks_by_the_web_clients_fraction():
	assert_eq(Wading.SINK, 0.30)
	var sunk := Wading.sunk(Rect2(0, 0, 32, 32), 32.0)
	assert_almost_eq(sunk.position.y, 9.6, 0.001)
	assert_eq(sunk.size, Vector2(32, 32), "it sinks, it does not shrink")


func test_what_shows_is_what_is_still_inside_the_cell():
	var cell := Rect2(0, 0, 32, 32)
	var shown := Wading.shown(Wading.sunk(Rect2(0, 0, 32, 32), 32.0), cell)
	assert_almost_eq(shown.size.y, 32.0 * (1.0 - Wading.SINK), 0.01, "seven tenths of it")
	assert_eq(shown.end.y, 32.0, "clipped at the cell, which is the waterline")


func test_a_tall_frame_loses_its_overhang_too():
	# The web client masks to the cell rect rather than to a waterline, so a
	# swing that reaches above the body is cut there as well.
	var cell := Rect2(0, 0, 32, 32)
	var swing := Rect2(0, -16, 32, 48)
	var shown := Wading.shown(Wading.sunk(swing, 32.0), cell)
	assert_eq(shown.position.y, 0.0, "nothing above the cell survives")
	assert_eq(shown.end.y, 32.0)


func test_the_slice_of_the_sheet_matches_the_part_that_shows():
	var texture := AtlasTexture.new()
	texture.region = Rect2(64, 128, 8, 8)
	# The real arrangement: the frame is sunk, and what survives the clip is
	# its top -- the feet are what the water takes.
	var sunk := Wading.sunk(Rect2(0, 0, 32, 32), 32.0)
	var shown := Wading.shown(sunk, Rect2(0, 0, 32, 32))
	var slice := Wading.slice(texture, sunk, shown)
	# The frame's own coordinates, not the sheet's: an AtlasTexture adds its
	# own origin, and adding it here too samples past the end of the frame and
	# clips to nothing -- the body disappears rather than losing its legs.
	assert_eq(slice.position, Vector2.ZERO, "from the top of the frame")
	assert_eq(slice.size.x, 8.0, "the whole width")
	assert_almost_eq(slice.size.y, 8.0 * (1.0 - Wading.SINK), 0.01,
		"and seven tenths of the height")


func test_a_sliceless_call_is_the_whole_texture():
	assert_eq(Wading.slice(null, Rect2(0, 0, 32, 32), Rect2(0, 0, 32, 32)), Rect2())


# --- what actually gets drawn ----------------------------------------------

func test_a_dry_player_is_drawn_whole():
	_ground(GRASS)
	_stand(Vector2(0, 0))
	var body := EntityRenderer.body_draw(queue.build(state, content, VIEW)[0])
	assert_eq(body["slice"], Rect2(), "no slice means the whole texture")
	assert_eq(body["rect"].size.y, 32.0)


func test_a_wading_player_is_drawn_clipped():
	_ground(WET)
	_stand(Vector2(0, 0))
	var body := EntityRenderer.body_draw(queue.build(state, content, VIEW)[0])
	assert_almost_eq(body["rect"].size.y, 32.0 * (1.0 - Wading.SINK), 0.01)
	assert_almost_eq(body["rect"].end.y, 32.0, 0.01, "cut at the waterline")
	assert_eq(body["slice"].position, Vector2.ZERO, "showing the top of the frame")
	assert_lt(body["slice"].size.y, body["texture"].region.size.y if body.has("texture") else 8.0,
		"and not all of it")


func test_a_body_with_no_art_is_left_alone():
	# The fallback block is drawn by colour, and there is no sheet to slice.
	var body := EntityRenderer.body_draw({"pos": Vector2.ZERO, "size": 32,
		"draw": Vector2(32, 32), "flip": false, "texture": null, "wading": true})
	assert_eq(body["slice"], Rect2())
	assert_eq(body["rect"].size.y, 32.0)


func test_a_state_with_no_content_wades_nowhere():
	# The renderer asks this every frame, including before content has landed.
	var bare := RealmState.new(null)
	assert_false(bare.tiles.wades(Vector2.ZERO, 32))
