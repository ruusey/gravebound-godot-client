class_name ChatPanel
extends CanvasLayer

## The chat log the server and other players produce.
##
## Shows a compact tail by default (the last few lines, sitting on the bottom
## margin), and EXPANDS into a scrollback of the whole ring when the mouse is over
## it, the input line is open, or (on a touchscreen) the log was touched. The ring
## itself lives in ChatLog (newest in, oldest out); this panel only renders it.
##
## Enter opens a line to type into, under the log; while it is open the panel
## captures the keyboard, and Screens tells every polled input so -- without the
## gate, typing walks the player and fires.
##
## One row per line (ChatRow) rather than one label for all of them: a SYSTEM
## line and a player line are different colours, and a long line wraps.

## Tail height (rows) when collapsed, and the viewport height when expanded. The
## expanded viewport is also capped to a fraction of the screen so it never runs
## off the top on a short (phone) display.
const COMPACT_LINES := 6
const EXPANDED_LINES := 14
const ROW_HEIGHT := 18
const EXPANDED_SCREEN_FRACTION := 0.45
const FONT_SIZE := 12
const MARGIN := 12
const WIDTH := 420
const INPUT_ROW := 28
const SCROLLBAR_WIDTH := 10
## A log collapsed while scrolled up holds its place this long before it returns
## to the newest line, so a mouse slipping off it doesn't lose the reader's spot.
const FOLLOW_RESUME_MS := 8000
## A phone's log narrows beside the touch buttons down to this, then rises
## over them instead.
const PHONE_MIN_WIDTH := 200.0
## A phone's log, left alone, fades out this long after its last new line
## and comes back with the next, or when opened.
const FADE_AFTER_MS := 3000
const FADE_MS := 600

var state: RealmState
var actions: ChatActions

var _box: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array = []
## The line each row shows, by identity, so a new line repaints only what changed.
var _row_lines: Array = []
var _input: ChatInput
var _shown := -1
var _hovering := false
## Opened by touching the log (no hover on a touchscreen); a touch elsewhere closes it.
var _touch_open := false
## Stick to the newest line unless the user has scrolled up.
var _follow := true
## The user scrolled the log since the last frame: only that, never the log
## growing, decides whether it still follows the newest line.
var _user_scrolled := false
var _collapsed_at_ms := -1
## The chip that folds the log to its name; the input line stays.
var fold: PanelFold
## The screen another panel covers (empty for none): the log steps right of it
## rather than drawing over it -- the open bag reaches this corner on a phone.
var avoid: Callable = func() -> Rect2: return Rect2()
## The log's left edge and width when nothing covers it.
var _home_left := float(MARGIN)
var _width := float(WIDTH - MARGIN)
## When the log last changed, for the phone's fade.
var _said_at_ms := 0


func setup(realm_state: RealmState, chat_actions: ChatActions = null) -> void:
	state = realm_state
	actions = chat_actions


func _ready() -> void:
	# Over the world and the debug overlay, under the transition cover.
	layer = 12
	if PhoneLayout.on:
		_home_left = PhoneLayout.MARGIN
		_width = PhoneLayout.CHAT_WIDTH
	_box = VBoxContainer.new()
	# Pinned by its bottom edge, growing upward: the log sits on the margin and
	# the input row, when shown, lifts it by its own height.
	_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.offset_top = -MARGIN
	_box.offset_bottom = -MARGIN
	_box.offset_left = _home_left
	_box.offset_right = _home_left + _width
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	# The scrollback. Vertical-only; its height is driven each frame (compact vs
	# expanded). mouse_filter is flipped in _process: PASS while collapsed so a
	# click on the tail still reaches the world, STOP while expanded so the wheel/
	# drag scrolls the log instead of acting on the world underneath.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size = Vector2(_width, _lines() * _row_height())
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.mouse_entered.connect(func() -> void: _hovering = true)
	_scroll.mouse_exited.connect(func() -> void: _hovering = false)
	_scroll.gui_input.connect(_on_scroll_input)
	_scroll.get_v_scroll_bar().custom_minimum_size.x = SCROLLBAR_WIDTH
	_scroll.get_v_scroll_bar().scrolling.connect(func() -> void: _user_scrolled = true)
	_box.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if PhoneLayout.on:
		_list.add_theme_constant_override("separation", PhoneLayout.CHAT_GAP)
	_scroll.add_child(_list)

	_input = ChatInput.new()
	_input.add_theme_font_size_override("font_size", FONT_SIZE)
	_input.custom_minimum_size.y = INPUT_ROW
	_input.sent.connect(_on_sent)
	_box.add_child(_input)

	fold = PanelFold.new(self, "Chat", "chat", state.settings if state != null else null,
		func(folded: bool) -> void: _scroll.visible = not folded)
	# Never hidden as a layer (the sign-in screen just covers it), so the chip
	# hides itself until there is a player to have a chat.
	fold.chip.visible = false
	_scroll.visible = not _folded()
	TouchFrame.adopt(self)


## The chat line, opened as Enter opens it: the phone's Chat button.
func open_line() -> void:
	if not _input.is_open():
		_input.open()


## The Chat button: opens the line, or shuts an open one.
func toggle_line() -> void:
	if _input.is_open():
		_input.close()
	else:
		_input.open()


func captures_mouse() -> bool:
	return _is_expanded() or fold.under_mouse()


func is_typing() -> bool:
	return _input.is_open()


## Expanded while the mouse is over the log, the input line is open, or the log
## was touched. Collapsing back to the tail the instant the mouse leaves is
## deliberate: the log is an overlay on the world, not a window to park open.
func _is_expanded() -> bool:
	return _hovering or _input.is_open() or _touch_open


func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_open = true
	if event is InputEventScreenDrag or event is InputEventPanGesture 			or (event is InputEventMouseButton and event.pressed and event.button_index in [
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		_user_scrolled = true


## Enter opens the line; a click anywhere it is not closes it, and a touch
## anywhere off the log folds a touch-opened log back to its tail.
func _unhandled_input(event: InputEvent) -> void:
	if state == null or not state.local.is_present():
		return
	# The touch that opened the log falls through here too (the tail passes clicks to
	# the world), so only a touch off the log closes it.
	if event is InputEventScreenTouch and event.pressed and _touch_open \
			and not _scroll.get_global_rect().has_point(_scroll.get_global_mouse_position()):
		_touch_open = false
	if event is InputEventMouseButton and event.pressed and _input.is_open():
		_input.close()
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) \
			and not _input.is_open():
		_input.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_SLASH and not _input.is_open():
		# Slash opens the line pre-filled with "/" so a command is one keystroke away.
		_input.open("/")
		get_viewport().set_input_as_handled()


## Clear of the touch buttons (`thumbs`, in the canvas's pixels): beside
## them, narrowed, where there is room; above them where there is not -- a
## phone held upright.
func _lift_over(thumbs: Rect2) -> void:
	var points := Rect2(thumbs.position / scale.x, thumbs.size / scale.x)
	var width := PhoneLayout.CHAT_WIDTH
	var bottom := -float(MARGIN)
	if points.has_area():
		var room := points.position.x - PhoneLayout.GAP - _home_left
		if room >= PHONE_MIN_WIDTH:
			width = minf(width, room)
		else:
			bottom = points.position.y - PhoneLayout.GAP - TouchScale.view_size(_box).y
	_set_width(width)
	if not is_equal_approx(_box.offset_bottom, bottom):
		_box.offset_bottom = bottom
		_box.offset_top = bottom


func _set_width(width: float) -> void:
	if is_equal_approx(width, _width):
		return
	_width = width
	_box.offset_right = _box.offset_left + width
	_scroll.custom_minimum_size.x = width
	for row in _rows:
		row.custom_minimum_size.x = width


## Step the log right of `covered` when its home corner, chip included, would
## sit under it; back home when it is clear.
func _clear_of(covered: Rect2) -> void:
	var box := _box.get_global_rect()
	var home := Rect2(_home_left, box.position.y - PanelFold.CHIP_HEIGHT - 2.0,
		_width, box.size.y + PanelFold.CHIP_HEIGHT + 2.0)
	var left := _home_left
	if covered.has_area() and covered.intersects(home):
		left = covered.end.x + MARGIN
	if not is_equal_approx(_box.offset_left, left):
		_box.offset_left = left
		_box.offset_right = left + _width


func _on_sent(text: String) -> void:
	if actions != null:
		actions.say(text)


func _process(_delta: float) -> void:
	if PhoneLayout.on:
		fold.chip.visible = false
		_lift_over(PhoneLayout.thumbs)
	else:
		fold.chip.visible = state != null and state.local.is_present()
	_clear_of(avoid.call())
	fold.place(Vector2(_box.offset_left, _box.get_global_rect().position.y - PanelFold.CHIP_HEIGHT - 2.0))
	if state == null:
		blank()
		return

	var expanded := _is_expanded()
	# Height: compact tail, or expanded viewport capped to a slice of the screen.
	var want_h := _lines() * _row_height()
	if expanded:
		var cap := TouchScale.view_size(_box).y * EXPANDED_SCREEN_FRACTION
		# Never up over a phone's vitals, however high the log has risen.
		if PhoneLayout.on:
			var under := TouchScale.view_size(_box).y + _box.offset_bottom - PhoneLayout.vitals_bottom
			cap = minf(cap, under - INPUT_ROW - PhoneLayout.GAP * 2.0)
		want_h = minf(EXPANDED_LINES * _row_height(), cap)
	if not is_equal_approx(_scroll.custom_minimum_size.y, want_h):
		_scroll.custom_minimum_size.y = want_h
	# Capture scroll only when expanded; otherwise let clicks fall through to the
	# world -- and on a phone, past the tail to the move stick under it.
	var resting := Control.MOUSE_FILTER_IGNORE if PhoneLayout.on else Control.MOUSE_FILTER_PASS
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP if expanded else resting
	if PhoneLayout.on:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if expanded \
			else ScrollContainer.SCROLL_MODE_SHOW_NEVER

	# Between new lines, a log the user scrolled up stays where they put it. Judged
	# only after the user scrolls: a new line grows the log a frame before the
	# scroll catches up, which would otherwise read as scrolled up. A log collapsed
	# while scrolled up keeps its place for FOLLOW_RESUME_MS, then shows the newest.
	var bar := _scroll.get_v_scroll_bar()
	if expanded:
		_collapsed_at_ms = -1
		if _user_scrolled:
			_user_scrolled = false
			_follow = at_bottom(bar.value, bar.max_value, bar.page)
	elif not _follow:
		var now := Time.get_ticks_msec()
		if _collapsed_at_ms < 0:
			_collapsed_at_ms = now
		elif now - _collapsed_at_ms >= FOLLOW_RESUME_MS:
			_follow = true
			_collapsed_at_ms = -1

	# Rebuild only when something was said -- watches the ring's revision, not its
	# size (size saturates at 50 once full, so newer lines would stop redrawing).
	# Every new line brings the log to it, scrolled up or not: a busy chat is
	# otherwise lost below the box.
	if state.chat.revision != _shown:
		_shown = state.chat.revision
		_follow = true
		_collapsed_at_ms = -1
		_said_at_ms = Time.get_ticks_msec()
		refresh()
	elif _follow:
		_stick_bottom()
	if PhoneLayout.on:
		_scroll.modulate.a = 1.0 if expanded else fade(Time.get_ticks_msec() - _said_at_ms)


## Whether a scroll at `value` shows the log's last line.
static func at_bottom(value: float, max_value: float, page: float) -> bool:
	return value >= max_value - page - 1.0


## The phone log's opacity `idle_ms` after its last new line: whole for
## FADE_AFTER_MS, then gone over FADE_MS.
static func fade(idle_ms: int) -> float:
	return clampf(1.0 - float(idle_ms - FADE_AFTER_MS) / FADE_MS, 0.0, 1.0)


## The phone's log has no chip, so it is never folded.
func _folded() -> bool:
	return fold.folded and not PhoneLayout.on


func _lines() -> int:
	return PhoneLayout.CHAT_LINES if PhoneLayout.on else COMPACT_LINES


func _row_height() -> float:
	return PhoneLayout.CHAT_ROW if PhoneLayout.on else float(ROW_HEIGHT)


## Nothing to show without a log. Blanking rather than returning keeps the guard
## testable (an exception leaves the rows as-is and GUT scores that as passing).
func blank() -> void:
	for row in _rows:
		row.blank()
	_row_lines.fill(null)
	_shown = -1


## Renders the whole ring (not just the tail) into the scrollback; the viewport
## height is what decides how many are visible at once. Splits out so a test can
## drive it without waiting for a frame.
func refresh() -> void:
	var lines: Array = state.chat.lines
	while _rows.size() < lines.size():
		# Wrapped rather than run off the edge: a long line is the normal case.
		var row := ChatRow.new(_width, PhoneLayout.CHAT_FONT if PhoneLayout.on else ChatRow.FONT_SIZE)
		_list.add_child(row)
		_rows.append(row)
		_row_lines.append(null)
	_recycle_dropped(lines)
	for i in _rows.size():
		var line: Variant = lines[i] if i < lines.size() and not _folded() else null
		if is_same(line, _row_lines[i]):
			continue
		_row_lines[i] = line
		if line == null:
			_rows[i].blank()
		else:
			_rows[i].show_line(line)
	if _follow:
		_stick_bottom()


## The rows of lines the ring dropped off its front move to the end to be
## refilled: with a full ring every line shifts up one, and repainting all the
## rows for each new line cost milliseconds.
func _recycle_dropped(lines: Array) -> void:
	if lines.is_empty():
		return
	var dropped := 0
	while dropped < _row_lines.size() and _row_lines[dropped] != null \
			and not is_same(_row_lines[dropped], lines[0]):
		dropped += 1
	if dropped == 0 or dropped >= _row_lines.size() or not is_same(_row_lines[dropped], lines[0]):
		return
	for i in dropped:
		var row: ChatRow = _rows.pop_front()
		_rows.append(row)
		_list.move_child(row, -1)
		_row_lines.pop_front()
		_row_lines.append(null)


## Pin to the newest line. Deferred so the row layout has settled first; the
## ScrollContainer clamps an over-large value to its real maximum.
func _stick_bottom() -> void:
	_scroll.set_deferred("scroll_vertical", 1_000_000)
