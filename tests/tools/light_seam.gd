extends Node

## Glowing shots packed across a ground-chunk border on bare floor, in the flat view:
## shows whether any bullet glow is cut off at the chunk edge.
##   GRAVEBOUND_DATA_ROOT=... godot --path . --resolution 1280x960 res://tests/tools/light_seam.tscn -- <out.png> [extra emitters]

const MainScript := preload("res://scripts/app/main.gd")
const MAP_SIZE := 64
const FLOOR := 319
const CANDLE := 200
const SERPENTS_KISS := 1409
const CENTRE := Vector2i(32, 31)

var transport := FakeTransport.new()
var main: Node


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var output: String = args[0]
	var candles := args.size() > 1
	var config := ClientConfig.new()
	config.data_root = OS.get_environment("GRAVEBOUND_DATA_ROOT")
	config.autoconnect = false
	main = MainScript.new()
	main.config = config
	add_child(main)
	while not main.game_data.ready:
		await get_tree().process_frame
	var at := _px(CENTRE)
	main.client.connection.transport = transport
	main.session.begin("a@b.c", "pw", "char-1")
	transport.become_connected()
	main.client._process(0.0)
	transport.deliver(WireHelper.login_response(1, 2, at))
	main.client._process(0.0)
	var state: RealmState = main.state
	state.settings.set_on("lighting", true)
	state.settings.set_on("view_25d", false)
	state.apply_packet("LoadMapPacket", _stage(candles))
	state.local.id = 1
	state.local.position = at
	state.apply_packet("LoadPacket", {"players": [VisualScenarios._player(1, "Ruu", at, 0)]})
	for i in 200:
		await get_tree().process_frame
	# 24 Serpent's Kiss shots held still in two rows, one each side of the chunk border
	# under the player (cell row 32) -- more glows on one chunk than Godot lights it with.
	var bullets: Array = []
	var id := 9000
	for row in [31.6, 32.3]:
		for k in 12:
			var pos := Vector2(28.0 + k * 0.6, row) * GameConstants.TILE_SIZE - Vector2(7.0, 7.0)
			bullets.append({"id": id, "projectileId": SERPENTS_KISS,
				"pos": {"x": pos.x, "y": pos.y}, "size": 14, "angle": 0.0,
				"magnitude": 0.0, "range": 1.0e9, "damage": 0, "flags": [], "amplitude": 0.0,
				"frequency": 0.0, "srcEntityId": 1})
			id += 1
	state.apply_packet("LoadPacket", {"bullets": bullets})
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output)
	print("captured ", output)
	get_tree().quit()


static func _px(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GameConstants.TILE_SIZE


## Bare floor; optionally a ring of candles around the view, off the volley.
static func _stage(candles: bool) -> Dictionary:
	var tiles: Array = []
	for x in MAP_SIZE:
		for y in MAP_SIZE:
			tiles.append({"tileId": FLOOR, "layer": 0, "xIndex": y, "yIndex": x})
	if candles:
		for x in range(18, 48, 3):
			for y in [23, 40]:
				tiles.append({"tileId": CANDLE, "layer": 1, "xIndex": y, "yIndex": x})
	return {"realmId": 1, "mapId": 9000, "mapWidth": MAP_SIZE, "mapHeight": MAP_SIZE,
		"tiles": tiles, "dungeonId": -1}
