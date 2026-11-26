extends GutTest

## Following the newest line: a scroll up holds the place, a new line ends it.

var state: RealmState
var panel: ChatPanel


func before_each() -> void:
	state = RealmState.new(null, func() -> int: return 5000)
	panel = ChatPanel.new()
	panel.setup(state)
	add_child_autofree(panel)


func _said(message: String) -> void:
	state.apply_packet("TextPacket", {"from": "Gharr", "to": "", "message": message})


func test_a_new_line_brings_a_scrolled_up_log_back_to_the_newest() -> void:
	_said("first")
	panel._process(0.0)
	panel._follow = false
	_said("second")
	panel._process(0.0)
	assert_true(panel._follow)


func test_a_scrolled_up_log_holds_its_place_while_nothing_is_said() -> void:
	_said("first")
	panel._process(0.0)
	panel._follow = false
	panel._process(0.0)
	assert_false(panel._follow)


func test_at_bottom_when_the_last_line_shows() -> void:
	assert_true(ChatPanel.at_bottom(348.0, 600.0, 252.0))


func test_at_bottom_within_a_pixel() -> void:
	assert_true(ChatPanel.at_bottom(347.5, 600.0, 252.0))


func test_not_at_bottom_when_scrolled_up() -> void:
	assert_false(ChatPanel.at_bottom(0.0, 600.0, 252.0))


func test_a_log_shorter_than_its_box_is_at_bottom() -> void:
	assert_true(ChatPanel.at_bottom(0.0, 160.0, 160.0))
