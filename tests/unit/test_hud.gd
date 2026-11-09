extends GutTest

## The debug overlay's job is to make client/server disagreement visible.

var hud: DebugHud
var client: GraveBoundClient
var state: RealmState
var transport: FakeTransport


func before_each():
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)

	state = RealmState.new(null)

	hud = DebugHud.new()
	hud.setup(client, state)
	hud.shown = true
	add_child_autofree(hud)


func _refresh() -> String:
	hud._process(1.0)
	return hud._label.text


func test_does_nothing_without_its_dependencies():
	var bare := DebugHud.new()
	add_child_autofree(bare)
	bare._process(1.0)
	assert_eq(bare._label.text, "", "no client or state means nothing to report")


func test_off_until_asked_for_and_builds_nothing_while_off():
	var fresh := DebugHud.new()
	fresh.setup(client, state)
	add_child_autofree(fresh)
	fresh._process(1.0)
	assert_false(fresh.visible, "off by default: /debug brings it up")
	assert_eq(fresh._label.text, "", "and nothing is built while it is off")
	fresh.shown = true
	fresh._process(1.0)
	assert_true(fresh.visible)
	assert_ne(fresh._label.text, "")


func test_throttles_refreshes():
	hud._process(0.01)
	assert_eq(hud._label.text, "", "sub-100ms frames do not rebuild the overlay")


func test_shows_the_connection_state():
	assert_string_contains(_refresh(), "idle")
	client.connect_to_server("h", 1)
	assert_string_contains(_refresh(), "connecting")
	transport.become_connected()
	client._process(0.0)
	assert_string_contains(_refresh(), "awaiting login")
	transport.deliver(WireHelper.login_response(1, 0, Vector2.ZERO))
	client._process(0.0)
	assert_string_contains(_refresh(), "in game")
	client.disconnect_from_server()
	assert_string_contains(_refresh(), "disconnected")


func test_hides_player_lines_until_logged_in():
	var text := _refresh()
	assert_false(text.contains("realm"), "no world summary before login")
	assert_string_contains(text, "ping 0 ms")


func test_shows_where_the_frame_goes():
	var line := DebugHud.frame_line()
	assert_string_contains(line, "frame ")
	assert_string_contains(line, " ms   ")
	assert_string_contains(line, " draw calls   ")
	assert_string_contains(line, " static")
	assert_string_contains(_refresh(), "draw calls")


func test_shows_the_simulated_lag_only_while_there_is_some():
	assert_false(_refresh().contains("lag +"))
	var line := LagTransport.new(transport, 100.0, 4.0)
	client.connection.transport = line
	assert_string_contains(_refresh(), "lag +100 ms")
	assert_string_contains(_refresh(), "/lag")
	line.one_way_ms = 0.0
	line.jitter_ms = 0.0
	assert_false(_refresh().contains("lag +"))


func test_shows_the_heartbeat_ping_and_jitter():
	client.stats.ping_ms = 42
	client.stats.jitter_ms = 7
	client.stats.rtt_ms = 90.0
	assert_string_contains(_refresh(), "ping 42 ms   jitter 7 ms   move rtt 90 ms")


func test_shows_position_and_tile():
	state.local.id = 1
	state.local.name = "Ruu"
	state.local.health = 450
	state.local.mana = 120
	state.local.position = Vector2(64.0, 96.0)
	state.tiles.realm_id = 3
	state.tiles.map_id = 1
	state.tiles.width = 128
	state.tiles.height = 128
	var text := _refresh()
	assert_string_contains(text, "Ruu")
	assert_string_contains(text, "450")
	assert_string_contains(text, "64.0, 96.0")
	assert_string_contains(text, "tile 2, 3")
	assert_string_contains(text, "realm 3")


func test_shows_reconciliation_counters():
	state.movement.corrections = 4
	state.movement.last_correction_px = 12.5
	assert_string_contains(_refresh(), "corrections 4")
	assert_string_contains(_refresh(), "12.50 px")


func test_shows_entity_and_tile_counts():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(1, 0, 0, 0), WireHelper.tile(1, 1, 0, 0)]})
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(1, "a", Vector2.ZERO)],
		"enemies": [WireHelper.enemy(2, 1, Vector2.ZERO), WireHelper.enemy(3, 1, Vector2.ZERO)],
	})
	var text := _refresh()
	assert_string_contains(text, "players 1  enemies 2")
	assert_string_contains(text, "tiles 2 across 2 layers")


func test_shows_unknown_packet_count_only_when_nonzero():
	assert_false(_refresh().contains("unknown packets"))
	client.stats.unknown_packets = 3
	assert_string_contains(_refresh(), "unknown packets: 3")


func test_shows_live_draw_counts_when_a_renderer_is_attached():
	assert_false(_refresh().contains("drawn:"))

	var content := GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	var renderer := WorldRenderer.new()
	renderer.setup(state, content)
	add_child_autofree(renderer)
	hud.renderer = renderer

	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(1, 0, 0, 0)]})
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(1, "a", Vector2.ZERO)],
		"enemies": [WireHelper.enemy(2, 1, Vector2.ZERO)],
	})
	await wait_process_frames(2)

	assert_string_contains(_refresh(), "drawn: 1 tiles, 1 players, 1 enemies, 0 bullets")


func test_packet_mix_is_ordered_by_frequency():
	client.stats.packet_counts = {"LoadPacket": 3, "ObjectMovePacket": 50, "UpdatePacket": 7}
	var mix := client.stats.mix()
	assert_lt(mix.find("ObjectMovePacket"), mix.find("UpdatePacket"), "busiest packet first")
	assert_lt(mix.find("UpdatePacket"), mix.find("LoadPacket"))


func test_packet_mix_is_empty_before_any_traffic():
	assert_eq(client.stats.mix(), "")


func test_unrecognised_client_state_renders_a_placeholder():
	client.state = 99 as GraveBoundClient.State
	assert_string_contains(_refresh(), "?")


func test_reports_a_dungeon_and_a_transition_in_flight():
	# An empty world mid-transition is deliberate; the line says so rather
	# than leaving it looking like the stream broke.
	state.local.id = 1
	state.apply_packet("LoadMapPacket", {"realmId": 4, "mapId": 9, "dungeonId": 3, "tiles": []})
	assert_string_contains(_refresh(), "dungeon 3")
	assert_false(_refresh().contains("entering"), "not while we are standing still")

	state.begin_transition()
	assert_string_contains(_refresh(), "entering")
