extends GutTest


func test_at_bottom_when_the_last_line_shows() -> void:
	assert_true(ChatPanel.at_bottom(348.0, 600.0, 252.0))


func test_at_bottom_within_a_pixel() -> void:
	assert_true(ChatPanel.at_bottom(347.5, 600.0, 252.0))


func test_not_at_bottom_when_scrolled_up() -> void:
	assert_false(ChatPanel.at_bottom(0.0, 600.0, 252.0))


func test_a_log_shorter_than_its_box_is_at_bottom() -> void:
	assert_true(ChatPanel.at_bottom(0.0, 160.0, 160.0))
