extends GutTest

## The torchlit hall behind the sign-in panel, and the fire in it.

var data: GameData
var backdrop: LoginBackdrop


func before_each():
	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	backdrop = _backdrop()


## Built from the fixture's tiles -- a tall wall, grass, its twin, and two
## props for the torch and the candelabra -- and sized like the shared
## 64x64 test window, since a Control under a plain Node has no size.
func _backdrop() -> LoginBackdrop:
	var made := LoginBackdrop.new()
	made.game_data = data
	made.clock = func() -> float: return 0.25
	made.hall.wall_tile = 6
	made.hall.floor_tile = 1
	made.hall.floor_accent = 8
	made.torch_tile = 9
	made.candelabra_tile = 2
	add_child_autofree(made)
	made.size = Vector2(64, 64)
	return made


func _draw() -> void:
	backdrop.step(1.0 / 60.0)
	await wait_process_frames(2)


func test_the_hall_fills_the_screen_a_cell_at_a_time():
	# The shared test window is 64x64: two cells across, two down.
	await _draw()
	assert_eq(backdrop.drawn["tiles"], 4)
	assert_eq(backdrop.drawn["torches"], 4, "four along the wall whatever the width")


func test_the_torches_burn_with_the_trails_own_particles():
	backdrop.field.rng.seed = 3
	backdrop.step(1.0 / 60.0)
	# Four torches at 90 a second are one and a half each a frame: four
	# the first frame, the halves carried; the candle's 40 has not added up.
	assert_eq(backdrop.field.count, 4)
	for i in backdrop.field.count:
		assert_lt(backdrop.field.vy[i], 0.0, "every spark rises")
		assert_almost_eq(backdrop.field.size_start[i] / backdrop.field.size_end[i], 3.5, 0.01, "and burns down")
	await _draw()
	assert_gt(backdrop.drawn["flames"], 0, "and they are drawn")
	for i in 60:
		backdrop.step(1.0 / 60.0)
	assert_between(backdrop.field.count, 100, 300, "a second in, births and deaths balance")


func test_the_fire_is_the_same_every_time_from_a_seed():
	var other := _backdrop()
	backdrop.field.rng.seed = 11
	other.field.rng.seed = 11
	for i in 5:
		backdrop.step(1.0 / 60.0)
		other.step(1.0 / 60.0)
	assert_eq(backdrop.field.count, other.field.count)
	assert_eq(backdrop.field.x[0], other.field.x[0])
	assert_eq(backdrop.field.tint[3], other.field.tint[3])


func test_the_flames_start_at_the_torch_tips():
	backdrop.step(1.0 / 60.0)
	var tips := backdrop.torch_tips()
	assert_eq(tips.size(), 4)
	assert_eq(tips[0].y, tips[3].y, "all on the same wall row")
	assert_lt(tips[0].x, tips[1].x)
	var near := 0
	for i in backdrop.field.count:
		var at := Vector2(backdrop.field.x[i], backdrop.field.y[i])
		for tip in tips + [backdrop.candle_tip()]:
			if at.distance_to(tip) < 16.0:
				near += 1
				break
	assert_eq(near, backdrop.field.count, "every spark within a few pixels of a flame")


func test_the_glow_adds_and_the_flames_mix():
	assert_eq(backdrop._glow.material.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	assert_eq(backdrop._flames.material.blend_mode, CanvasItemMaterial.BLEND_MODE_MIX)
	assert_eq(backdrop._glow.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "a soft halo, not a stepped one")
	assert_eq(backdrop.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "crisp stone")
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_IGNORE, "nothing here takes a click from the form")


func test_without_content_it_is_a_dark_screen_and_no_error():
	var bare := LoginBackdrop.new()
	add_child_autofree(bare)
	bare.size = Vector2(64, 64)
	bare.step(1.0 / 60.0)
	await wait_process_frames(2)
	assert_eq(bare.drawn["tiles"], 0)
	assert_eq(bare.drawn["torches"], 0)
	assert_gt(bare.field.count, 0, "the fire burns regardless; only the stone needs content")


func test_a_flame_flickers_between_seven_tenths_and_full():
	var low := 1.0
	var high := 0.0
	for i in 500:
		var f := TorchFlame.flicker(i * 0.037, 1.9)
		low = minf(low, f)
		high = maxf(high, f)
	assert_gt(low, 0.69)
	assert_lt(high, 1.01)
	assert_lt(high - low, 0.32, "and it breathes rather than strobes")
	assert_ne(TorchFlame.flicker(0.5, 0.0), TorchFlame.flicker(0.5, 1.9), "no two torches together")


func test_light_is_warm_near_a_flame_and_dim_far_from_it_and_darker_below():
	var lights := [{"at": Vector2(100, 100), "strength": 1.0}]
	var near := TorchFlame.light(Vector2(110, 100), HallTiles.AMBIENT, 0.0, lights, HallTiles.WARM, 360.0)
	var far := TorchFlame.light(Vector2(900, 100), HallTiles.AMBIENT, 0.0, lights, HallTiles.WARM, 360.0)
	assert_gt(near.r, far.r * 3.0, "the flame lights the stone")
	assert_gt(near.r, near.b, "warmly")
	assert_eq(far, HallTiles.AMBIENT, "out of reach is the ambient alone")
	var bottom := TorchFlame.light(Vector2(900, 100), HallTiles.AMBIENT, 1.0, [], HallTiles.WARM, 360.0)
	assert_almost_eq(bottom.r, HallTiles.AMBIENT.r * 0.75, 0.001, "a quarter darker at the bottom")
	var blazing := TorchFlame.light(Vector2(100, 100), Color.WHITE, 0.0, lights, Color.WHITE, 360.0)
	assert_eq(blazing, Color.WHITE, "never brighter than white")


func test_the_wall_shows_its_front_face():
	var wall := data.tile_texture(6)
	assert_not_null(wall)
	assert_eq(wall.region.size.y, 16.0, "fixture tile 6 is a tall wall")
	var front := HallTiles.front_face(wall)
	assert_eq(front.region.size, Vector2(8, 8))
	assert_eq(front.region.position, wall.region.position + Vector2(0, 8), "the lower half")
	var floor := data.tile_texture(1)
	assert_same(HallTiles.front_face(floor), floor, "a square tile is itself")
	assert_null(HallTiles.front_face(null))


func test_the_login_screen_puts_the_hall_behind_everything():
	# The hall is the phone's backdrop; a desktop with data scrolls a dungeon.
	var was := PhoneLayout.on
	PhoneLayout.on = true
	var screen := _login_screen()
	add_child_autofree(screen)
	assert_eq(screen._backdrop.get_index(), 0, "first under the layer's TouchFrame")
	assert_eq(screen._backdrop.get_parent().get_index(), 0)
	assert_same(screen._backdrop.game_data, data)
	PhoneLayout.on = was


func test_a_tile_the_content_lacks_leaves_its_cells_bare():
	# The 64px window is two rows, both wall: with the wall missing every
	# cell is skipped -- and none errors, which GUT would count as a pass.
	backdrop.hall.wall_tile = 9999
	await _draw()
	assert_eq(backdrop.drawn["tiles"], 0)
	assert_eq(backdrop.drawn["torches"], 4, "the torches are still there")


## Once the player is in the game the login screen is hidden, and nothing
## behind it may keep running: no particles simulated, none emitted, no
## redraw asked for -- and the ones already burning are dropped, not kept.
func test_the_fire_stops_and_empties_once_the_screen_is_hidden():
	var screen := CanvasLayer.new()
	add_child_autofree(screen)
	var hidden := _backdrop()
	hidden.reparent(screen)
	hidden.size = Vector2(64, 64)
	for i in 30:
		hidden._process(1.0 / 60.0)
	assert_gt(hidden.field.count, 0, "burning while shown")
	screen.visible = false
	await wait_process_frames(2)
	hidden._process(1.0 / 60.0)
	assert_eq(hidden.field.count, 0, "hidden: the flames are dropped")
	for i in 30:
		hidden._process(1.0 / 60.0)
	assert_eq(hidden.field.count, 0, "and none are emitted while hidden")
	assert_false(hidden.is_processing(), "nothing steps it while hidden")
	screen.visible = true
	await wait_process_frames(2)
	assert_true(hidden.is_processing(), "shown again, it burns again")
	hidden._process(1.0 / 60.0)
	assert_gt(hidden.field.count, 0)


## A login screen whose server list fetch answers from a fake backend, not
## the network.
func _login_screen() -> LoginScreen:
	var service := DataService.new()
	service.backend = FakeHttpBackend.new()
	service.base_url = "http://data.test"
	add_child_autofree(service)
	var screen := LoginScreen.new()
	screen.data_service = service
	screen.game_data = data
	return screen
