class_name DevOverlay
extends CanvasLayer

## The web client's dev readout: one line, top right, on by default; /dev
## turns it off and on.
##
## FPS, ping and draw calls in its traffic-light colours, jitter, and the
## render resolution with the scale DisplayScale chose -- the
## numbers that say whether a hitch is the frame, the network or the
## screen. Draw calls come from FrameCounts, the rendering server's own
## count. It only builds the line while it is showing, and a few times a
## second at that, so a readout left off costs nothing but the check.

const REFRESH_SECONDS := 0.25
const GREEN := "#66ff66"
const YELLOW := "#ffff66"
const RED := "#ff6666"

var client: GraveBoundClient
var shown := true

var _text: RichTextLabel
var _elapsed := REFRESH_SECONDS


func setup(net_client: GraveBoundClient) -> void:
	client = net_client


func _ready() -> void:
	# Over everything, as the web's is (max z-index), and click-through.
	layer = 30
	visible = false
	var anchor := MarginContainer.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	anchor.add_theme_constant_override("margin_top", 2)
	anchor.add_theme_constant_override("margin_right", 10)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.09, 0.8)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 12)
	panel.add_child(_text)


func _process(delta: float) -> void:
	visible = shown and client != null and client.is_in_game()
	if not visible:
		_elapsed = REFRESH_SECONDS
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = 0.0
	var window := get_window()
	_text.text = line(Engine.get_frames_per_second(), client.stats.ping_ms, client.stats.jitter_ms,
		window.size, window.content_scale_factor, FrameCounts.draw_calls())


## The readout, in BBCode.
static func line(fps: float, ping_ms: int, jitter_ms: int, resolution: Vector2i, scale: float,
		draw_calls: int) -> String:
	return "  |  ".join([
		"FPS [color=%s]%d[/color]" % [fps_colour(fps), roundi(fps)],
		"PING [color=%s]%dms[/color]" % [ping_colour(ping_ms), ping_ms],
		"JITTER %dms" % jitter_ms,
		"RES %dx%d @%sx" % [resolution.x, resolution.y, DisplayScale.label(scale)],
		"DRAW [color=%s]%d[/color]" % [draw_colour(draw_calls), draw_calls],
	])


## The web client's thresholds, each.
static func fps_colour(fps: float) -> String:
	return GREEN if fps >= 55 else YELLOW if fps >= 30 else RED


static func ping_colour(ping_ms: int) -> String:
	return GREEN if ping_ms < 50 else YELLOW if ping_ms < 120 else RED


static func draw_colour(draw_calls: int) -> String:
	return GREEN if draw_calls < 600 else YELLOW if draw_calls < 1500 else RED
