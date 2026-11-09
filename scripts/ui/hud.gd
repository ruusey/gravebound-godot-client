class_name DebugHud
extends CanvasLayer

## Diagnostic overlay.
##
## For a client whose whole job is to agree with a server you cannot see, the
## interesting numbers are the ones that show disagreement: how many
## corrections the server has issued, how far off we were, and how much input
## is still outstanding. And the frame itself, because a frame that runs long
## is what makes the 64Hz predictor step twice at once -- the jitter the
## reference clients' dev overlays report as FPS and DRAW beside PING.

const REFRESH_INTERVAL := 0.1

var client: GraveBoundClient
var state: RealmState
var renderer: WorldRenderer
var shown := false

var _label: Label
var _panel: PanelContainer
var _elapsed := 0.0


func setup(net_client: GraveBoundClient, realm_state: RealmState, world: WorldRenderer = null) -> void:
	client = net_client
	state = realm_state
	renderer = world


func _ready() -> void:
	layer = 10
	visible = shown
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 8)
	_panel.modulate = Color(1, 1, 1, 0.9)
	add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_label)


func _process(delta: float) -> void:
	visible = shown
	if not shown:
		return
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL or client == null or state == null:
		return
	_elapsed = 0.0
	_label.text = "\n".join(_lines())


## Where the diagnostics end on screen, for what stacks under them; 0 when
## they are off.
func bottom() -> float:
	return _panel.position.y + _panel.size.y if visible and _panel != null else 0.0


func _lines() -> PackedStringArray:
	var stats := client.stats
	var lines := PackedStringArray()
	lines.append("%s  |  %.0f fps" % [state_name(), Engine.get_frames_per_second()])
	lines.append(frame_line())

	if state.local.is_present():
		lines.append("%s (class %d)  hp %d  mp %d" % [
			state.local.name if state.local.name != "" else "?",
			state.local.class_id, state.local.health, state.local.mana])
		lines.append("pos %.1f, %.1f   tile %d, %d" % [
			state.local.position.x, state.local.position.y,
			floori(state.local.position.x / GameConstants.TILE_SIZE),
			floori(state.local.position.y / GameConstants.TILE_SIZE)])
		var place := "realm %d  map %d  %dx%d" % [
			state.tiles.realm_id, state.tiles.map_id, state.tiles.width, state.tiles.height]
		if state.tiles.dungeon_id >= 0:
			place += "  dungeon %d" % state.tiles.dungeon_id
		# An empty world mid-transition is deliberate, and this says so.
		if state.transition_pending:
			place += "  (entering ...)"
		lines.append(place)

	lines.append("ping %d ms   jitter %d ms   move rtt %.0f ms%s" % [
		stats.ping_ms, stats.jitter_ms, stats.rtt_ms, simulated_lag()])
	lines.append("seq %d   unacked %d" % [state.movement.input_seq, state.movement.unacked_inputs])
	lines.append("corrections %d   last %.2f px" % [
		state.movement.corrections, state.movement.last_correction_px])
	lines.append("in %s (%d pkt)   out %s (%d pkt)" % [
		String.humanize_size(stats.bytes_in), stats.packets_in,
		String.humanize_size(stats.bytes_out), stats.packets_out])
	lines.append("players %d  enemies %d  bullets %d  portals %d" % [
		state.entities.players.size(), state.entities.enemies.size(),
		state.projectiles.bullets.size(), state.entities.portals.size()])
	lines.append("tiles %d across %d layers" % [state.tiles.tile_count(), state.tiles.layers.size()])

	if renderer != null:
		var live := renderer.draw_stats
		lines.append("drawn: %d tiles, %d players, %d enemies, %d bullets" % [
			live["tiles"], live["players"], live["enemies"], live["bullets"]])
	if stats.unknown_packets > 0:
		lines.append("unknown packets: %d" % stats.unknown_packets)
	lines.append("[F1] packet mix   [F2] collision overlay   [`] screenshot")
	lines.append("[enter] chat   [space] use portal   [r] nexus   [v] vault   [m] map   [l] quests   /lag")
	return lines


## Where the frame goes: the process step, which includes every _draw, and
## what the renderer was then handed (FrameCounts). Zero headless.
static func frame_line() -> String:
	return "frame %.1f ms   %d draw calls   %d objects   %s static" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		FrameCounts.draw_calls(),
		FrameCounts.objects(),
		String.humanize_size(int(Performance.get_monitor(Performance.MEMORY_STATIC)))]


## The delay line's own contribution to the ping, when there is one.
func simulated_lag() -> String:
	var transport := client.connection.transport
	if transport is LagTransport and transport.delaying():
		return "   lag +%.0f ms" % transport.one_way_ms
	return ""


func state_name() -> String:
	match client.state:
		GraveBoundClient.State.IDLE: return "idle"
		GraveBoundClient.State.CONNECTING: return "connecting"
		GraveBoundClient.State.AWAITING_LOGIN: return "awaiting login"
		GraveBoundClient.State.IN_GAME: return "in game"
		GraveBoundClient.State.ENDED: return "game over"
		GraveBoundClient.State.CLOSED: return "disconnected"
	return "?"
