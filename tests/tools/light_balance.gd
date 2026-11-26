extends Node

## Light-level match between the flat view and the 2.5D view.
##
## Builds one lit stage -- shadow-casting pillars with candles beside them, a crystal,
## lava and water pools, glowing bullets and a glowing enemy -- in a real logged-in
## Main, captures it in both views under overworld and dungeon light, and prints the
## brightness at the same world points in each, with the 2.5D / flat ratio. Tune the
## 2.5D constants (WorldView3D) until the ratios sit near 1.
##
## Windowed (the headless driver has no rendering device); real content:
##   GRAVEBOUND_DATA_ROOT=<gravebound-data>/src/main/resources \
##   godot --path . --resolution 1280x960 res://tests/tools/light_balance.tscn -- <out.png>

const MainScript := preload("res://scripts/app/main.gd")
const MAP_SIZE := 64
const FLOOR := 319
const WALL := 83
const CANDLE := 200
const CRYSTAL := 189
const LAVA := 25
const WATER := 9
const LIT_BULLET_GROUPS := [1320, 91]
const LIT_ENEMY := 272
## The walled room (wider than the flat view, so its walls show only in 2.5D) and the
## player at its middle. Everything sampled sits within the flat view's frame.
const STAGE := Rect2i(20, 21, 25, 21)
const CENTRE := Vector2i(32, 31)
const CANDLE_AT := Vector2i(26, 27)
const PILLARS := [Vector2i(28, 27), Vector2i(35, 36)]
const CRYSTAL_AT := Vector2i(38, 27)
const LAVA_POOL := Rect2i(26, 31, 3, 3)
const WATER_POOL := Rect2i(36, 31, 3, 3)
const EFFIGY_AT := Vector2i(34, 35)
const BULLET_CELLS := [Vector2i(29, 35), Vector2i(30, 35), Vector2i(31, 35)]
## Sample points (cells): floor cells unless named after what they sit on.
const POINTS := {
	"ambient": Vector2i(32, 27),
	"candle_pool": Vector2i(26, 28),
	"pillar_shadow": Vector2i(29, 27),
	"crystal_pool": Vector2i(38, 28),
	"lava": Vector2i(27, 32),
	"lava_edge": Vector2i(29, 32),
	"water": Vector2i(37, 32),
	"bullet_glow": Vector2i(30, 34),
	"effigy_glow": Vector2i(33, 35),
}
const FRAMES_SETTLE := 300
const SAMPLES := 6
const SAMPLE_GAP := 9
const PATCH := 4
## Quits on its own if a run stalls, so a windowed run never hangs a terminal.
const WATCHDOG_S := 180.0

var transport := FakeTransport.new()
var main: Node
var _hide_hud := false
var _next_bullet := 5000


func _init() -> void:
	# After Main and its screens, which re-show their layers as they update.
	process_priority = 1000


func _process(_delta: float) -> void:
	if not _hide_hud:
		return
	for layer in main.screens.get_children():
		if layer is CanvasLayer:
			layer.visible = false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		push_error("light_balance: timed out")
		get_tree().quit(2))
	var args := OS.get_cmdline_user_args()
	var output: String = args[0] if args.size() > 0 else "reports/light_balance.png"
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
	# The HUD's panels would sit over sample points; only the world is measured.
	_hide_hud = true
	var shots: Array = []
	var rows: Array = []
	for dungeon in [false, true]:
		state.settings.set_on("view_25d", false)
		state.apply_packet("LoadMapPacket", _stage(dungeon))
		_populate(state, at)
		for view_25d in [false, true]:
			state.settings.set_on("view_25d", view_25d)
			for i in FRAMES_SETTLE:
				await get_tree().process_frame
			# Bullets age out; the ones measured are fresh.
			_bullets(state, _next_bullet)
			_next_bullet += BULLET_CELLS.size()
			var measured := await _measure()
			shots.append(measured["image"])
			rows.append([("dungeon" if dungeon else "overworld") + (" 2.5D" if view_25d else " flat"),
				measured["levels"]])
	_report(rows)
	_sheet(shots, output)
	get_tree().quit()


## Mean brightness (0..255) around each point, averaged over a few frames for flicker.
func _measure() -> Dictionary:
	var levels := {}
	for name in POINTS:
		levels[name] = 0.0
	var image: Image
	for s in SAMPLES:
		for i in SAMPLE_GAP:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		image = get_viewport().get_texture().get_image()
		for name in POINTS:
			levels[name] += _luma(image, _screen(_px(POINTS[name]))) / SAMPLES
	return {"image": image, "levels": levels}


func _screen(world: Vector2) -> Vector2:
	if main._view_3d != null:
		return main._view_3d._camera.unproject_position(Vector3(world.x, 0.0, world.y))
	return main._world.get_global_transform_with_canvas() * world


static func _luma(image: Image, at: Vector2) -> float:
	var total := 0.0
	var count := 0
	for dx in range(-PATCH, PATCH + 1):
		for dy in range(-PATCH, PATCH + 1):
			var x := int(at.x) + dx
			var y := int(at.y) + dy
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var c := image.get_pixel(x, y)
			total += (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0
			count += 1
	return total / maxf(count, 1.0)


func _report(rows: Array) -> void:
	var header := "%-18s" % "point"
	for row in rows:
		header += "%16s" % row[0]
	print(header + "   2.5D/flat ow   2.5D/flat dg")
	for name in POINTS:
		var line := "%-18s" % name
		for row in rows:
			line += "%16.1f" % row[1][name]
		line += "%14.2f%15.2f" % [rows[1][1][name] / maxf(rows[0][1][name], 1.0),
			rows[3][1][name] / maxf(rows[2][1][name], 1.0)]
		print(line)


func _sheet(shots: Array, output: String) -> void:
	var first: Image = shots[0]
	var half: Vector2i = first.get_size() / 2
	var sheet := Image.create(half.x * 2, half.y * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var shot: Image = shots[i]
		shot.convert(Image.FORMAT_RGBA8)
		shot.resize(half.x, half.y, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, half), Vector2i(half.x * (i % 2), half.y * (i / 2)))
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	sheet.save_png(output)
	print("captured ", output)


static func _px(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GameConstants.TILE_SIZE


## The stage as a LoadMap: floor everywhere, a walled room, a candle lighting a pillar
## from the side, a second pillar, a crystal, and lava and water pools.
static func _stage(dungeon: bool) -> Dictionary:
	var layer0 := {}
	var layer1 := {}
	for x in MAP_SIZE:
		for y in MAP_SIZE:
			layer0[Vector2i(x, y)] = FLOOR
	for x in range(STAGE.position.x, STAGE.end.x):
		layer1[Vector2i(x, STAGE.position.y)] = WALL
		layer1[Vector2i(x, STAGE.end.y - 1)] = WALL
	for y in range(STAGE.position.y, STAGE.end.y):
		layer1[Vector2i(STAGE.position.x, y)] = WALL
		layer1[Vector2i(STAGE.end.x - 1, y)] = WALL
	for pillar in PILLARS:
		layer1[pillar] = WALL
	layer1[CANDLE_AT] = CANDLE
	layer1[CRYSTAL_AT] = CRYSTAL
	for x in range(LAVA_POOL.position.x, LAVA_POOL.end.x):
		for y in range(LAVA_POOL.position.y, LAVA_POOL.end.y):
			layer0[Vector2i(x, y)] = LAVA
	for x in range(WATER_POOL.position.x, WATER_POOL.end.x):
		for y in range(WATER_POOL.position.y, WATER_POOL.end.y):
			layer0[Vector2i(x, y)] = WATER
	var tiles: Array = []
	for cell in layer0:
		tiles.append({"tileId": layer0[cell], "layer": 0, "xIndex": cell.y, "yIndex": cell.x})
	for cell in layer1:
		tiles.append({"tileId": layer1[cell], "layer": 1, "xIndex": cell.y, "yIndex": cell.x})
	# A map id that is no vault, so a dungeon id darkens it in both views.
	return {"realmId": 2 if dungeon else 1, "mapId": 9001 if dungeon else 9000,
		"mapWidth": MAP_SIZE, "mapHeight": MAP_SIZE, "tiles": tiles,
		"dungeonId": 0 if dungeon else -1}


## The player and a glowing enemy; the glowing bullets come just before each measure.
static func _populate(state: RealmState, at: Vector2) -> void:
	state.local.id = 1
	state.local.position = at
	state.apply_packet("LoadPacket", {"players": [VisualScenarios._player(1, "Ruu", at, 0)],
		"enemies": [VisualScenarios._enemy(77, LIT_ENEMY, _px(EFFIGY_AT) - Vector2(16, 16), 1000, 1000)]})


static func _bullets(state: RealmState, first_id: int) -> void:
	var bullets: Array = []
	for k in BULLET_CELLS.size():
		var pos := _px(BULLET_CELLS[k]) - Vector2(6, 6)
		bullets.append({"id": first_id + k, "projectileId": LIT_BULLET_GROUPS[k % 2],
			"pos": {"x": pos.x, "y": pos.y}, "size": 12, "angle": 0.0,
			"magnitude": 0.0, "range": 1.0e9, "damage": 0, "flags": [], "amplitude": 0.0,
			"frequency": 0.0, "srcEntityId": 77})
	state.apply_packet("LoadPacket", {"bullets": bullets})
