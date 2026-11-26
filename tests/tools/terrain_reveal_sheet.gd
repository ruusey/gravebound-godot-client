extends Node

## Contact sheet of TerrainReveal mid-fade, for judging the look.
##
##   godot --path . --resolution 1280x960 res://tests/tools/terrain_reveal_sheet.tscn -- <out.png>
##
## Windowed (the headless driver has no rendering device); GRAVEBOUND_DATA_ROOT
## names the data checkout's resources dir. Rows: smooth entry,
## smooth stream, dither entry, dither stream. Columns: seconds after the packet.
## Terrain is a real slice of the vault map (map 30) around its potion alcove.

const TIMES := [0.0, 0.1, 0.2, 0.3, 0.45, 0.8]
const CENTRE := Vector2i(32, 36)
const HALF := Vector2i(12, 9)
## The stream case: cells inside this radius are already shown.
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
	var layers := _vault_layers(config.resolved_data_root().path_join("data/maps.json"))
	var rows: Array[Image] = []
	for dither in [false, true]:
		for stream in [false, true]:
			rows.append(await _row(content, layers, dither, stream))
	var sheet := Image.create(THUMB.x * TIMES.size(), THUMB.y * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		sheet.blit_rect(rows[r], Rect2i(Vector2i.ZERO, rows[r].get_size()), Vector2i(0, THUMB.y * r))
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	sheet.save_png(output)
	print("captured ", output)
	get_tree().quit(0)


func _row(content: GameData, layers: Dictionary, dither: bool, stream: bool) -> Image:
	var row := Image.create(THUMB.x * TIMES.size(), THUMB.y, false, Image.FORMAT_RGBA8)
	for i in TIMES.size():
		var frame := await _frame(content, layers, dither, stream, TIMES[i])
		frame.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_NEAREST)
		row.blit_rect(frame, Rect2i(Vector2i.ZERO, THUMB), Vector2i(THUMB.x * i, 0))
	return row


func _frame(content: GameData, layers: Dictionary, dither: bool, stream: bool, at: float) -> Image:
	var stage := Node.new()
	add_child(stage)
	var state := RealmState.new(content, func() -> int: return 0)
	var origin := Vector2(CENTRE) * GameConstants.TILE_SIZE + Vector2.ONE * GameConstants.TILE_SIZE * 0.5
	state.local.id = 1
	state.local.position = origin
	var renderer := WorldRenderer.new()
	renderer.setup(state, content)
	renderer.reveal.dither = dither
	# Boxed: a lambda captures a local by value.
	var now := [100.0]
	renderer.reveal.clock = func() -> float: return now[0]
	stage.add_child(renderer)
	var camera := Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = origin
	stage.add_child(camera)
	camera.make_current()
	await get_tree().process_frame
	if stream:
		# Already-seen ground first, long settled by the time the strip lands.
		state.apply_packet("LoadMapPacket", _packet(layers, func(d: float) -> bool: return d <= SETTLED_RADIUS))
		renderer._process(0.0)
		now[0] += 10.0
		state.apply_packet("LoadMapPacket", _packet(layers, func(d: float) -> bool: return d > SETTLED_RADIUS))
	else:
		state.apply_packet("LoadMapPacket", _packet(layers, func(_d: float) -> bool: return true))
	renderer._process(0.0)
	now[0] += at
	for _frame_index in 4:
		renderer._process(0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	stage.queue_free()
	await get_tree().process_frame
	return image


func _packet(layers: Dictionary, keep: Callable) -> Dictionary:
	var tiles: Array = []
	for layer in [0, 1]:
		var grid: Array = layers[str(layer)]
		for y in range(CENTRE.y - HALF.y, CENTRE.y + HALF.y + 1):
			for x in range(CENTRE.x - HALF.x, CENTRE.x + HALF.x + 1):
				var tile_id := int(grid[y][x])
				if not keep.call(Vector2(x - CENTRE.x, y - CENTRE.y).length()):
					continue
				if layer == 1 and tile_id == 0:
					continue
				tiles.append({"tileId": tile_id, "layer": layer, "xIndex": y, "yIndex": x})
	return {"realmId": 1, "mapId": 30, "mapWidth": 64, "mapHeight": 64, "tiles": tiles}


static func _vault_layers(path: String) -> Dictionary:
	for map in JSON.parse_string(FileAccess.get_file_as_string(path)):
		if int(map.get("mapId", -1)) == 30:
			return map["data"]
	return {}
