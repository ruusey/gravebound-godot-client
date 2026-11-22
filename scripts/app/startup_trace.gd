class_name StartupTrace
extends Node

## Logs how long the client takes to reach the login screen, phase by phase,
## and every long frame just after it -- where first-use shader compiles land.
## On the web the clock is the page's (performance.now()), so the engine
## download and compile before Godot starts are counted too.

const WATCH_SECONDS := 6.0
const LONG_FRAME_MS := 50.0

var _last := 0.0
var _watch_until := 0.0
var _long_frames := 0
var _long_total := 0.0


func _ready() -> void:
	set_process(false)
	mark("engine up")


func mark(phase: String) -> void:
	print("[startup] %s at %d ms" % [phase, now_ms()])


## Logs each frame over LONG_FRAME_MS for the next WATCH_SECONDS, then a total.
func watch_frames() -> void:
	_last = now_ms()
	_watch_until = _last + WATCH_SECONDS * 1000.0
	_long_frames = 0
	_long_total = 0.0
	set_process(true)


func _process(_delta: float) -> void:
	var now := now_ms()
	var frame := now - _last
	_last = now
	if frame >= LONG_FRAME_MS:
		_long_frames += 1
		_long_total += frame
		print("[startup] long frame %d ms at %d ms" % [frame, now])
	if now >= _watch_until:
		print("[startup] %d long frames, %d ms in all" % [_long_frames, _long_total])
		set_process(false)


static func now_ms() -> float:
	if OS.has_feature("web"):
		return float(JavaScriptBridge.eval("performance.now()"))
	return Time.get_ticks_usec() / 1000.0
