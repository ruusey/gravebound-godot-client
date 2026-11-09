extends GutTest

## The client-side synthetic dungeon builder: prefab rooms stamped flush at
## matching connection points, doorways cut where two rooms meet.

const FLOOR := 1
const WALL := 6


## A square room walled on its border with a single doorway on one side.
func _room(id: int, role: String, side: String) -> Dictionary:
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
		"minionEnemyIds": [], "minMinions": 0, "maxMinions": 0, "staticSpawns": [],
	}


func _dungeon(room_ids: Array) -> Dictionary:
	return {"dungeonId": 3, "name": "Test", "mapWidth": 24, "mapHeight": 24,
		"tileSize": 32, "minRooms": 1, "maxRooms": 1, "roomIds": room_ids,
		"entranceRoomId": -1, "bossRoomId": -1}


func _rooms() -> Dictionary:
	# Entrance opens east; the normal room opens west, so they join side by side.
	return {0: _room(0, "ENTRANCE", "E"), 1: _room(1, "NORMAL", "W")}


func test_it_stamps_both_layers_and_places_the_rooms():
	var layout := DungeonAssembler.new(_dungeon([0, 1]), _rooms(), 7).assemble()
	assert_eq(layout["placements"].size(), 2, "the entrance and one normal room")
	assert_gt(layout["layers"][0].size(), 0, "a base layer")
	assert_gt(layout["layers"][1].size(), 0, "a wall layer")
	# Entrance is centred: (24-5)/2 = 9. Its centre is the player spawn.
	assert_eq(layout["spawn"], Vector2((9 + 2.5) * 32, (9 + 2.5) * 32))


func test_the_normal_room_sits_flush_east_of_the_entrance():
	var layout := DungeonAssembler.new(_dungeon([0, 1]), _rooms(), 7).assemble()
	# Entrance at (9,9), 5 wide, so the normal room's top-left is (14,9).
	var origins: Array = []
	for placement in layout["placements"]:
		origins.append(Vector2i(placement["ox"], placement["oy"]))
	assert_true(Vector2i(9, 9) in origins)
	assert_true(Vector2i(14, 9) in origins)


func test_the_shared_doorway_is_cut_open():
	var layout := DungeonAssembler.new(_dungeon([0, 1]), _rooms(), 7).assemble()
	var walls: Dictionary = layout["layers"][1]
	# The two wall cells at the join (entrance east edge, normal west edge) on the
	# connection row (9+2 = 11) are cleared; a corner wall stays.
	assert_false(walls.has(Vector2i(13, 11)), "entrance doorway open")
	assert_false(walls.has(Vector2i(14, 11)), "neighbour doorway open")
	assert_true(walls.has(Vector2i(9, 9)), "the entrance corner is still walled")


func test_the_same_seed_builds_the_same_dungeon():
	var first := DungeonAssembler.new(_dungeon([0, 1]), _rooms(), 42).assemble()
	var second := DungeonAssembler.new(_dungeon([0, 1]), _rooms(), 42).assemble()
	assert_eq(first["layers"][0], second["layers"][0])
	assert_eq(first["layers"][1], second["layers"][1])
	assert_eq(first["spawn"], second["spawn"])


func test_a_dungeon_with_no_rooms_falls_back_to_one_open_room():
	# wallTileId set so the fallback can wall the border (real dungeons leave it
	# 0, which is why the layout falls through to a floor-only room).
	var dungeon := _dungeon([])
	dungeon["wallTileId"] = WALL
	var layout := DungeonAssembler.new(dungeon, {}, 1).assemble()
	assert_eq(layout["placements"].size(), 0, "no prefab rooms placed")
	assert_true(layout["layers"][0].has(Vector2i(12, 12)), "a floor to render")
	assert_true(layout["layers"][1].has(Vector2i(1, 1)), "walled at the corner")
