class_name DungeonAssembler
extends RefCounted

## Builds a synthetic dungeon from the loaded dungeon + prefab-room JSON, the way
## the server's DungeonAssembler does: prefab rooms stamped flush against matching
## connection points, doorways cut where two rooms meet. Used only by the login
## backdrop, so it is trimmed -- no boss-depth guarantee, no corridor carving --
## to a plausible, lit, walkable layout rather than a gameplay-correct one.
##
## Output tile layers are keyed exactly like TileMapState: layer 0 is the base,
## layer COLLISION_LAYER the walls, each a { Vector2i(col, row): tileId }.

const VOID := 0
const BASE_LAYER := 0
const COLLISION_LAYER := GameConstants.COLLISION_LAYER

var _dungeon: Dictionary
var _rooms: Dictionary
var _rng := RandomNumberGenerator.new()
var _width: int
var _height: int
var _tile_size: int

var _base := {}         # Vector2i(col, row) -> tileId
var _collision := {}    # Vector2i(col, row) -> tileId
var _occupied := {}     # Vector2i(col, row) -> true
var _placements: Array = []    # [{room, ox, oy, depth}]
var _open: Array = []   # [{dir, ex, ey, length, from_hall, depth}]


func _init(dungeon: Dictionary, rooms: Dictionary, seed_value: int = 0) -> void:
	_dungeon = dungeon
	_rooms = rooms
	if seed_value != 0:
		_rng.seed = seed_value
	_width = maxi(8, int(dungeon.get("mapWidth", 64)))
	_height = maxi(8, int(dungeon.get("mapHeight", 64)))
	_tile_size = int(dungeon.get("tileSize", GameConstants.TILE_SIZE))
	if _tile_size <= 0:
		_tile_size = GameConstants.TILE_SIZE


## {layers, width, height, tile_size, dungeon_id, name, placements, spawn}.
## spawn is the entrance centre in pixels -- where the camera starts its pan.
func assemble() -> Dictionary:
	var pool := _resolve_pool()
	if pool.is_empty():
		return _fallback("dungeon %d has no rooms" % int(_dungeon.get("dungeonId", -1)))

	var entrance := _pick_entrance(pool)
	var boss: Variant = _pick_boss(pool)
	var fill_pool: Array = []
	for room in pool:
		if room != entrance and room != boss:
			fill_pool.append(room)

	var ew := int(entrance.get("width", 1))
	var eh := int(entrance.get("height", 1))
	var ex := clampi((_width - ew) / 2, 1, maxi(1, _width - ew - 1))
	var ey := clampi((_height - eh) / 2, 1, maxi(1, _height - eh - 1))
	_place_room(entrance, ex, ey, 0)

	var target := _clamp_room_count()
	var guard := target * 160 + 32
	while _count_normal() < target and not _open.is_empty() and not fill_pool.is_empty() and guard > 0:
		guard -= 1
		_try_attach_random_room(fill_pool, _pop_next_open())

	if boss != null and not _open.is_empty():
		_force_place_boss(boss)

	_prune_orphan_hallways()
	_cut_used_connections()

	var spawn := _center_of(_placements[0])
	return {
		"layers": {BASE_LAYER: _base, COLLISION_LAYER: _collision},
		"width": _width,
		"height": _height,
		"tile_size": _tile_size,
		"dungeon_id": int(_dungeon.get("dungeonId", 0)),
		"name": String(_dungeon.get("name", "")),
		"placements": _placements,
		"spawn": spawn,
	}


func _resolve_pool() -> Array:
	var pool: Array = []
	for id in _dungeon.get("roomIds", []):
		var room: Variant = _rooms.get(int(id))
		if room != null:
			pool.append(room)
	return pool


func _pick_entrance(pool: Array) -> Dictionary:
	var forced := int(_dungeon.get("entranceRoomId", -1))
	if forced > -1 and _rooms.has(forced):
		return _rooms[forced]
	for room in pool:
		if _role(room) == "ENTRANCE":
			return room
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _pick_boss(pool: Array) -> Variant:
	var forced := int(_dungeon.get("bossRoomId", -1))
	if forced > -1 and _rooms.has(forced):
		return _rooms[forced]
	for room in pool:
		if _role(room) == "BOSS":
			return room
	return null


func _clamp_room_count() -> int:
	var lo := maxi(1, int(_dungeon.get("minRooms", 1)))
	var hi := maxi(lo, int(_dungeon.get("maxRooms", lo)))
	return _rng.randi_range(lo, hi)


func _count_normal() -> int:
	var n := 0
	for placement in _placements:
		var role := _role(placement["room"])
		if role != "ENTRANCE" and role != "BOSS" and role != "HALLWAY":
			n += 1
	return n


## A hallway's far opening is served before new hallways sprout from rooms, so
## rooms get placed instead of every opening growing a dead-end hallway.
func _pop_next_open() -> Dictionary:
	for i in _open.size():
		if _open[i]["from_hall"]:
			return _open.pop_at(i)
	return _open.pop_at(_rng.randi_range(0, _open.size() - 1))


func _try_attach_random_room(pool: Array, open: Dictionary) -> void:
	for room in _order_candidates(pool, open):
		var matching: Array = []
		for conn in room.get("connections", []):
			if _is_opposite(open["dir"], String(conn.get("side", ""))):
				matching.append(conn)
		_shuffle(matching)
		for conn in matching:
			if _attach(room, conn, open):
				return


## Alternates room<->hallway so an opening on a normal room prefers a hallway next
## and vice-versa, with the other group as fallback.
func _order_candidates(pool: Array, open: Dictionary) -> Array:
	var hallways: Array = []
	var normals: Array = []
	for room in pool:
		if _is_hallway(room):
			hallways.append(room)
		else:
			normals.append(room)
	_shuffle(hallways)
	_shuffle(normals)
	if open["from_hall"]:
		return normals + hallways
	return hallways + normals


func _attach(room: Dictionary, conn: Dictionary, open: Dictionary) -> bool:
	var origin := _room_origin(open, room, conn)
	if not _fits(room, origin.x, origin.y):
		return false
	var depth: int = open["depth"] + (0 if _is_hallway(room) else 1)
	_place_room(room, origin.x, origin.y, depth)
	return true


## Top-left origin so room's connection edge sits flush against the open
## connection with the two strips aligned (mirrors DungeonAssembler.roomOrigin).
func _room_origin(open: Dictionary, room: Dictionary, conn: Dictionary) -> Vector2i:
	var oc := int(conn.get("offset", 0))
	var w := int(room.get("width", 1))
	var h := int(room.get("height", 1))
	match open["dir"]:
		"E": return Vector2i(open["ex"], open["ey"] - oc)
		"W": return Vector2i(open["ex"] - w + 1, open["ey"] - oc)
		"S": return Vector2i(open["ex"] - oc, open["ey"])
		_: return Vector2i(open["ex"] - oc, open["ey"] - h + 1)   # "N"


func _fits(room: Dictionary, ox: int, oy: int) -> bool:
	var w := int(room.get("width", 1))
	var h := int(room.get("height", 1))
	for r in range(oy, oy + h):
		for c in range(ox, ox + w):
			if r < 1 or c < 1 or r >= _height - 1 or c >= _width - 1:
				return false
			if _occupied.has(Vector2i(c, r)):
				return false
	return true


func _place_room(room: Dictionary, ox: int, oy: int, depth: int) -> void:
	var data: Dictionary = room.get("data", {})
	for key in data:
		var layer_index := int(key)
		var target := _base if layer_index == BASE_LAYER else (_collision if layer_index == COLLISION_LAYER else {})
		if target.is_empty() and layer_index != BASE_LAYER and layer_index != COLLISION_LAYER:
			continue
		var grid: Array = data[key]
		for dy in grid.size():
			var grid_row: Array = grid[dy]
			for dx in grid_row.size():
				_set_tile(target, oy + dy, ox + dx, int(grid_row[dx]))
	var w := int(room.get("width", 1))
	var h := int(room.get("height", 1))
	for r in range(oy, oy + h):
		for c in range(ox, ox + w):
			_occupied[Vector2i(c, r)] = true
	_placements.append({"room": room, "ox": ox, "oy": oy, "depth": depth})
	_seed_connections(room, ox, oy, depth)


func _seed_connections(room: Dictionary, ox: int, oy: int, depth: int) -> void:
	var hall := _is_hallway(room)
	var w := int(room.get("width", 1))
	var h := int(room.get("height", 1))
	for conn in room.get("connections", []):
		var off := int(conn.get("offset", 0))
		var length := int(conn.get("length", 1))
		match String(conn.get("side", "")).to_upper():
			"N": _open.append(_opening("N", ox + off, oy - 1, length, hall, depth))
			"S": _open.append(_opening("S", ox + off, oy + h, length, hall, depth))
			"W": _open.append(_opening("W", ox - 1, oy + off, length, hall, depth))
			"E": _open.append(_opening("E", ox + w, oy + off, length, hall, depth))


func _opening(dir: String, ex: int, ey: int, length: int, from_hall: bool, depth: int) -> Dictionary:
	return {"dir": dir, "ex": ex, "ey": ey, "length": length, "from_hall": from_hall, "depth": depth}


## Place the boss onto the deepest remaining opening that will take it (the
## server also enforces a minimum depth; the backdrop only needs it placed).
func _force_place_boss(boss: Dictionary) -> void:
	var candidates := _open.duplicate()
	_shuffle(candidates)
	candidates.sort_custom(func(a, b): return a["depth"] > b["depth"])
	for open in candidates:
		for conn in boss.get("connections", []):
			if _is_opposite(open["dir"], String(conn.get("side", ""))) and _attach(boss, conn, open):
				_open.erase(open)
				return


func _prune_orphan_hallways() -> void:
	var changed := true
	while changed:
		changed = false
		for placement in _placements.duplicate():
			var room: Dictionary = placement["room"]
			if not _is_hallway(room):
				continue
			var connected := 0
			for conn in room.get("connections", []):
				if _is_connection_used(placement, conn):
					connected += 1
			if connected < 2:
				_unstamp(placement)
				changed = true


func _unstamp(placement: Dictionary) -> void:
	var room: Dictionary = placement["room"]
	var ox: int = placement["ox"]
	var oy: int = placement["oy"]
	for r in range(oy, oy + int(room.get("height", 1))):
		for c in range(ox, ox + int(room.get("width", 1))):
			var cell := Vector2i(c, r)
			_base.erase(cell)
			_collision.erase(cell)
			_occupied.erase(cell)
	_placements.erase(placement)


## A connection is used when the cells just outside its strip are occupied by a
## flush neighbour -- occupancy-based so it stays correct after pruning.
func _is_connection_used(placement: Dictionary, conn: Dictionary) -> bool:
	for cell in _connection_cells(placement, conn, true):
		if _occupied.has(cell):
			return true
	return false


func _connection_cells(placement: Dictionary, conn: Dictionary, outside: bool) -> Array:
	var room: Dictionary = placement["room"]
	var ox: int = placement["ox"]
	var oy: int = placement["oy"]
	var w := int(room.get("width", 1))
	var h := int(room.get("height", 1))
	var off := int(conn.get("offset", 0))
	var length := int(conn.get("length", 1))
	var side := String(conn.get("side", "")).to_upper()
	var cells: Array = []
	for i in length:
		match side:
			"N": cells.append(Vector2i(ox + off + i, oy - 1 if outside else oy))
			"S": cells.append(Vector2i(ox + off + i, oy + h if outside else oy + h - 1))
			"W": cells.append(Vector2i(ox - 1 if outside else ox, oy + off + i))
			"E": cells.append(Vector2i(ox + w if outside else ox + w - 1, oy + off + i))
	return cells


## Open the doorway: clear the collision-layer wall at every joined connection.
## Rooms are authored fully walled, so unused connections simply stay walled.
func _cut_used_connections() -> void:
	for placement in _placements:
		for conn in placement["room"].get("connections", []):
			if not _is_connection_used(placement, conn):
				continue
			for cell in _connection_cells(placement, conn, false):
				_collision.erase(cell)


func _fallback(reason: String) -> Dictionary:
	var floor_tile := int(_dungeon.get("corridorFloorTileId", 0))
	if floor_tile <= 0:
		floor_tile = 1
	var wall_tile := int(_dungeon.get("wallTileId", 0))
	for r in range(1, _height - 1):
		for c in range(1, _width - 1):
			_set_tile(_base, r, c, floor_tile)
			if r == 1 or c == 1 or r == _height - 2 or c == _width - 2:
				_set_tile(_collision, r, c, wall_tile)
	return {
		"layers": {BASE_LAYER: _base, COLLISION_LAYER: _collision},
		"width": _width, "height": _height, "tile_size": _tile_size,
		"dungeon_id": int(_dungeon.get("dungeonId", 0)), "name": String(_dungeon.get("name", "")),
		"placements": _placements,
		"spawn": Vector2((_width / 2) * _tile_size, (_height / 2) * _tile_size),
	}


func _center_of(placement: Dictionary) -> Vector2:
	var room: Dictionary = placement["room"]
	return Vector2(
		(placement["ox"] + int(room.get("width", 1)) / 2.0) * _tile_size,
		(placement["oy"] + int(room.get("height", 1)) / 2.0) * _tile_size)


func _set_tile(layer: Dictionary, row: int, col: int, tile_id: int) -> void:
	if tile_id <= 0 or row < 0 or col < 0 or row >= _height or col >= _width:
		return
	layer[Vector2i(col, row)] = tile_id


func _role(room: Dictionary) -> String:
	return String(room.get("role", "NORMAL")).to_upper()


func _is_hallway(room: Dictionary) -> bool:
	return _role(room) == "HALLWAY"


func _is_opposite(outward: String, side: String) -> bool:
	var s := side.to_upper()
	match outward:
		"N": return s == "S"
		"S": return s == "N"
		"E": return s == "W"
		"W": return s == "E"
	return false


func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp
