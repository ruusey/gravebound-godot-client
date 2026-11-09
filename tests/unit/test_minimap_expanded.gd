extends GutTest

## The phone's opened map: a finger drags it, two pinch it, a first tap on a
## player names them and a second teleports, and a drag never does.

var state: RealmState
var client: GraveBoundClient
var transport: FakeTransport
var map: MinimapExpanded


func before_each():
	state = RealmState.new(null, func() -> int: return 10_000)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	map = MinimapExpanded.new()
	map.setup(state, ChatActions.new(state, client))
	add_child_autofree(map)


## A 40x40 map with us mid-map and Mingau up and to the left.
func _in_realm() -> void:
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(1, 0, Vector2(640, 640)))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 1, "mapWidth": 40, "mapHeight": 40,
		"tiles": [WireHelper.tile(1, 0, 5, 5)]})
	state.apply_packet("GlobalPlayerPositionPacket", {"players": [
		{"playerId": 1, "name": "Ruu", "x": 640.0, "y": 640.0, "teleportable": true},
		{"playerId": 2, "name": "Mingau", "x": 320.0, "y": 320.0, "teleportable": true}]})
	transport.clear_sent()
	map.open(0.5)


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = pressed
	map._on_map_input(touch)


func _move(index: int, at: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = at
	map._on_map_input(drag)


func _tap(at: Vector2) -> void:
	_touch(0, at, true)
	_touch(0, at, false)


func _mingau() -> Vector2:
	return MinimapView.to_panel(Vector2(320, 320), map._canvas.window, map._canvas.side)


func _teleports() -> int:
	return transport.sent_packets().filter(func(packet) -> bool:
		return packet["name"] == "CommandPacket" and str(packet["data"]["command"]).contains("tp")).size()


func test_view_zoom_keeps_the_tile_under_the_fingers():
	var size := Vector2i(100, 100)
	var focus := MinimapView.focus_zoomed_about(size, Vector2(50, 50), 0.5, 0.25, Vector2(50, 50), 200.0)
	var before := MinimapView.window(size, 0.5, Vector2(50, 50))
	var after := MinimapView.window(size, 0.25, focus)
	var held := before.position + Vector2(0.25, 0.25) * before.size
	assert_almost_eq(after.position + Vector2(0.25, 0.25) * after.size, held, Vector2(0.001, 0.001))


func test_view_a_drag_moves_the_map_with_the_finger():
	var focus := MinimapView.focus_dragged(Vector2i(100, 100), Vector2(50, 50), 0.5, Vector2(20, 0), 200.0)
	assert_eq(focus, Vector2(45, 50), "a 20px drag right on a 50-tile window shows 5 tiles further left")


func test_opens_following_the_player_and_closes():
	_in_realm()
	assert_true(map.visible)
	assert_true(map.following)
	assert_eq(map._canvas.window.get_center(), Vector2(20, 20))
	map.close()
	assert_false(map.visible)


func test_a_first_tap_names_a_player_and_a_second_teleports():
	_in_realm()
	_tap(_mingau())
	assert_eq(map.picked.get("name", ""), "Mingau")
	assert_eq(_teleports(), 0, "named, not sent")
	_tap(_mingau())
	assert_eq(_teleports(), 1)
	assert_false(map.visible, "closes on the way")


func test_a_drag_pans_and_never_teleports():
	_in_realm()
	var start := _mingau()
	_touch(0, start, true)
	_move(0, start + Vector2(40, 0))
	_move(0, start + Vector2(80, 0))
	_touch(0, start + Vector2(80, 0), false)
	assert_false(map.following)
	map._process(0.0)
	assert_lt(map._canvas.window.get_center().x, 20.0, "panned left")
	assert_true(map.picked.is_empty())
	assert_eq(_teleports(), 0)


func test_pinching_apart_zooms_in():
	_in_realm()
	var middle := Vector2.ONE * map._canvas.side * 0.5
	_touch(0, middle - Vector2(20, 0), true)
	_touch(1, middle + Vector2(20, 0), true)
	_move(1, middle + Vector2(60, 0))
	_move(0, middle - Vector2(60, 0))
	assert_lt(map.zoom, 0.5, "a smaller fraction of the map")
	_touch(0, middle, false)
	_touch(1, middle, false)
	assert_true(map.picked.is_empty(), "a pinch is not a tap")


func test_the_buttons_zoom_and_me_recentres():
	_in_realm()
	map.zoom_by(1.0 / MinimapExpanded.BUTTON_ZOOM)
	assert_almost_eq(map.zoom, 0.5 / MinimapExpanded.BUTTON_ZOOM, 0.0001)
	map._drag(Vector2(30, 30))
	map.recentre()
	map._process(0.0)
	assert_eq(map._canvas.window.get_center(), Vector2(20, 20))
