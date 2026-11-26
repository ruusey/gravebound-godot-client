extends Node

## Contact sheet of TerrainReveal mid-dissolve, lit, for judging the look.
##
##   godot --path . --resolution 1280x960 res://tests/tools/terrain_reveal_sheet.tscn -- <out.png>
##
## Windowed (the headless driver has no rendering device); GRAVEBOUND_DATA_ROOT
## names the data checkout's resources dir. Columns are seconds after the packet.
## Rows, each a real map slice:
##   walk   ground near the player is known; a ring around it streams in
##   jump   the player was elsewhere on the map and teleports here: shown at once
## The smooth fade is the last row, for comparison.

const TIMES := [0.0, 0.1, 0.2, 0.3, 0.45, 0.8]
const ROWS := [
	{"map": 30, "centre": Vector2i(32, 36), "case": "walk", "dither": true},
	{"map": 38, "centre": Vector2i(328, 305), "case": "walk", "dither": true},
	{"map": 30, "centre": Vector2i(32, 36), "case": "jump", "dither": true},
	{"map": 38, "centre": Vector2i(328, 305), "case": "walk", "dither": false},
]
const HALF := Vector2i(12, 9)
## The walk case: cells inside this radius are already shown.
const SETTLED_RADIUS := 6.0
const ZOOM := 2.0
const THUMB := Vector2i(320, 240)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var output: String = args[0] if args.size() > 0 else "reports/terrain_reveal_sheet.png"
	var config := ClientConfig.new()
	if OS.has_environment("GRAVEBOUND_DATA_ROOT"):
		config.data_root = OS.get_environment("GRAVEBOUND_DATA_ROOT")
	var content := GameData.new()
	if not await content.load_from(FileContentSource.new(config.resolved_data_root())):
		push_error("content load failed")
		get_tree().quit(1)
		return
	var maps := _maps(config.resolved_data_root().path_join("data/maps.json"))
	var sheet := Image.create(THUMB.x * TIMES.size(), THUMB.y * ROWS.size(), false, Image.FORMAT_RGBA8)
	for r in ROWS.size():
		for i in TIMES.size():
			var frame := await _frame(content, maps[ROWS[r]["map"]], ROWS[r], TIMES[i])
			frame.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, THUMB), Vector2i(THUMB.x * i, THUMB.y * r))
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	sheet.save_png(output)
	print("captured ", output)
	get_tree().quit(0)


func _frame(content: GameData, map: Dictionary, row: Dictionary, at: float) -> Image:
	var stage := Node.new()
	add_child(stage)
	var state := RealmState.new(content, func() -> int: return 0)
	var centre: Vector2i = row["centre"]
	var renderer := WorldRenderer.new()
	renderer.setup(state, content)
	renderer.reveal.dither = row["dither"]
	# Boxed: a lambda captures a local by value.
	var now := [100.0]
	renderer.reveal.clock = func() -> float: return now[0]
	stage.add_child(renderer)
	var lighting := SceneLighting.new()
	lighting.setup(state, content)
	lighting.reveal = renderer.reveal
	stage.add_child(lighting)
	var camera := Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = _centre_px(centre)
	stage.add_child(camera)
	camera.make_current()
	state.local.id = 1
	await get_tree().process_frame
	if row["case"] == "walk":
		state.local.position = _centre_px(centre)
		state.apply_packet("LoadMapPacket", _packet(map, centre, func(d: float) -> bool: return d <= SETTLED_RADIUS))
		renderer._process(0.0)
		now[0] += 10.0
		state.apply_packet("LoadMapPacket", _packet(map, centre, func(d: float) -> bool: return d > SETTLED_RADIUS))
	else:
		# Standing in a corner of the same map, then the teleport lands here.
		var away := Vector2i(HALF.x + 2, HALF.y + 2)
		state.local.position = _centre_px(away)
		state.apply_packet("LoadMapPacket", _packet(map, away, func(d: float) -> bool: return d <= SETTLED_RADIUS))
		renderer._process(0.0)
		now[0] += 10.0
		renderer._process(0.0)
		state.local.position = _centre_px(centre)
		state.apply_packet("LoadMapPacket", _packet(map, centre, func(_d: float) -> bool: return true))
	renderer._process(0.0)
	now[0] += at
	for _frame_index in 6:
		renderer._process(0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	stage.queue_free()
	await get_tree().process_frame
	return image


static func _centre_px(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GameConstants.TILE_SIZE


func _packet(map: Dictionary, centre: Vector2i, keep: Callable) -> Dictionary:
	var tiles: Array = []
	var layers: Dictionary = map["data"]
	for layer in [0, 1]:
		var grid: Array = layers[str(layer)]
		for y in range(centre.y - HALF.y, centre.y + HALF.y + 1):
			for x in range(centre.x - HALF.x, centre.x + HALF.x + 1):
				if y < 0 or x < 0 or y >= grid.size() or x >= grid[y].size():
					continue
				var tile_id := int(grid[y][x])
				if not keep.call(Vector2(x - centre.x, y - centre.y).length()):
					continue
				if layer == 1 and tile_id == 0:
					continue
				tiles.append({"tileId": tile_id, "layer": layer, "xIndex": y, "yIndex": x})
	return {"realmId": 1, "mapId": int(map["mapId"]), "mapWidth": int(map["width"]),
		"mapHeight": int(map["height"]), "tiles": tiles}


static func _maps(path: String) -> Dictionary:
	var wanted := {}
	for row in ROWS:
		wanted[row["map"]] = true
	var found := {}
	for map in JSON.parse_string(FileAccess.get_file_as_string(path)):
		var map_id := int(map.get("mapId", -1))
		if wanted.has(map_id):
			found[map_id] = map
	return found
