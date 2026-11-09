extends GutTest

## The scrolling-dungeon backdrop behind the sign-in panel: it assembles a
## dungeon into its own realm state, fills it with drifting enemies, and pans.

const FLOOR := 1
const WALL := 6

var data: GameData


func before_each():
	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	# The shared fixture has no dungeon data; inject a two-room dungeon whose tiles
	# and enemies the fixture does carry (tiles 1/6, enemies 1/2).
	data.library.dungeons = {0: {
		"dungeonId": 0, "name": "Fixture", "mapWidth": 24, "mapHeight": 24,
		"tileSize": 32, "minRooms": 1, "maxRooms": 1, "roomIds": [0, 1]}}
	data.library.dungeon_rooms = {0: _room(0, "ENTRANCE", "E", [1], []),
		1: _room(1, "NORMAL", "W", [], [{"enemyId": 2, "col": 2, "row": 2}])}


func _room(id: int, role: String, side: String, minions: Array, statics: Array) -> Dictionary:
	var base: Array = []
	var walls: Array = []
	for r in 5:
		var base_row: Array = []
		var wall_row: Array = []
		for c in 5:
			base_row.append(FLOOR)
			wall_row.append(WALL if r == 0 or c == 0 or r == 4 or c == 4 else 0)
		base.append(base_row)
		walls.append(wall_row)
	return {
		"roomId": id, "role": role, "width": 5, "height": 5,
		"data": {"0": base, "1": walls},
		"connections": [{"id": 0, "side": side, "offset": 2, "length": 1}],
		"minionEnemyIds": minions, "minMinions": minions.size(), "maxMinions": minions.size(),
		"staticSpawns": statics,
	}


func _backdrop() -> DungeonBackdrop:
	var made := DungeonBackdrop.new()
	made.game_data = data
	made.seed_value = 99
	add_child_autofree(made)
	made.size = Vector2(256, 256)
	return made


func test_it_can_build_only_with_dungeon_data():
	assert_true(DungeonBackdrop.can_build(data))
	data.library.dungeons = {}
	assert_false(DungeonBackdrop.can_build(data), "no dungeons, no backdrop")


func test_building_fills_the_realm_with_the_dungeon():
	var backdrop := _backdrop()
	backdrop.build()
	assert_true(backdrop.built)
	var tiles: TileMapState = backdrop._state.tiles
	assert_eq(tiles.width, 24)
	assert_eq(tiles.dungeon_id, 0, "flagged a dungeon, so the ambient darkens")
	assert_gt(tiles.layers[0].size(), 0, "a floor was stamped")
	assert_gt(tiles.changed_cells.size(), 0, "seeded so the ground paints")


func test_it_spawns_the_rooms_enemies():
	var backdrop := _backdrop()
	backdrop.build()
	var enemies: Dictionary = backdrop._state.entities.enemies
	assert_gt(enemies.size(), 0, "the minion fill and the static boss")
	var ids: Array = []
	for enemy in enemies.values():
		ids.append(enemy["enemy_id"])
	assert_true(2 in ids, "the fixed spawn (enemy 2) is placed")


func test_a_rider_rides_the_camera_so_the_lighting_has_a_viewer():
	var backdrop := _backdrop()
	backdrop.build()
	assert_true(backdrop._state.local.is_present(), "a present viewer gates the lights")
	assert_almost_eq(backdrop._state.local.centre().x, backdrop._camera.position.x, 0.01)


func test_stepping_pans_the_view_and_drifts_the_enemies():
	var backdrop := _backdrop()
	backdrop.build()
	var start := backdrop._camera.position
	var before: Dictionary = {}
	for id in backdrop._state.entities.enemies:
		before[id] = backdrop._state.entities.enemies[id]["pos"]
	for frame in 90:
		backdrop.step(1.0 / 60.0)
	assert_ne(backdrop._camera.position, start, "the view has panned")
	var moved := false
	for id in before:
		if backdrop._state.entities.enemies[id]["pos"] != before[id]:
			moved = true
	assert_true(moved, "at least one enemy drifted")


func test_the_same_seed_builds_the_same_dungeon():
	var a := _backdrop()
	var b := _backdrop()
	a.build()
	b.build()
	assert_eq(a._state.tiles.layers[0], b._state.tiles.layers[0])
	assert_eq(a._state.entities.enemies.size(), b._state.entities.enemies.size())


func test_a_phone_keeps_the_cheaper_torch_hall():
	var was := PhoneLayout.on
	PhoneLayout.on = true
	var screen := LoginScreen.new()
	screen.game_data = data   # dungeon data is loaded, but a phone skips it
	add_child_autofree(screen)
	assert_null(screen._dungeon, "no scrolling dungeon on a phone")
	assert_not_null(screen._backdrop, "the torchlit hall instead")
	PhoneLayout.on = was


func test_desktop_with_data_gets_the_scrolling_dungeon():
	var was := PhoneLayout.on
	PhoneLayout.on = false
	var screen := LoginScreen.new()
	screen.game_data = data
	add_child_autofree(screen)
	assert_not_null(screen._dungeon, "the scrolling dungeon on desktop")
	assert_null(screen._backdrop)
	PhoneLayout.on = was
