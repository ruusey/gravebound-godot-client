class_name ClientCommands
extends RefCounted

## The chat commands the client answers itself, never sent to the server.
##
## The web client's handleChatCommand checks its own before anything goes on
## the wire -- /clear and /dev among them -- and says what it did as a SYSTEM
## line; this is that branch. Anything not named here is a server command
## and ChatActions sends it as one.
##
##   /dev    the compact readout, top right: FPS, ping, jitter, resolution, draw calls
##   /debug  the full diagnostics, top left, off until asked for
##   /clear  empties the chat log
##   /lag    steps the delay line (LagTransport) 50ms at a time to 350 and off;
##           /lag N sets N ms one way -- what the L key did before the quest
##           log took it, as the web's does

var state: RealmState
var dev: DevOverlay
var hud: DebugHud
var client: GraveBoundClient


func _init(realm_state: RealmState, dev_overlay: DevOverlay, debug_hud: DebugHud,
		net_client: GraveBoundClient = null) -> void:
	state = realm_state
	dev = dev_overlay
	hud = debug_hud
	client = net_client


## Whether the line was one of ours; it has been handled if so.
func run(line: String) -> bool:
	var words := line.strip_edges().trim_prefix("/").split(" ", false)
	if words.is_empty():
		return false
	match words[0].to_lower():
		"dev":
			dev.shown = not dev.shown
			_note("Dev overlay %s (FPS / ping / jitter / res / draw)" % _on(dev.shown))
		"debug":
			hud.shown = not hud.shown
			_note("Diagnostics %s" % _on(hud.shown))
		"clear":
			state.chat.clear()
		"lag":
			var delay: Variant = client.connection.transport if client != null else null
			if not delay is LagTransport:
				return false
			if words.size() > 1 and words[1].is_valid_float():
				delay.one_way_ms = maxf(0.0, words[1].to_float())
				delay.jitter_ms = LagTransport.STEP_JITTER_MS if delay.one_way_ms > 0.0 else 0.0
			else:
				delay.cycle()
			_note("Lag +%d ms one way" % roundi(delay.one_way_ms))
		_:
			return false
	return true


func _note(text: String) -> void:
	state.chat.apply_text({"from": ChatLog.SYSTEM, "to": state.local.name, "message": text})


static func _on(shown: bool) -> String:
	return "ON" if shown else "OFF"
