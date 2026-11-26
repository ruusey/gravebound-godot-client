extends GutTest

## The phone's realm banner, chat log and interact prompt: sized and placed
## for a small screen.

var state: RealmState


func before_each():
	PhoneLayout.on = true
	state = RealmState.new(GameData.new(), func() -> int: return 0)


func after_each():
	PhoneLayout.on = false


func _font(label: Control, key := "font_size") -> int:
	return label.get_theme_font_size(key)


func test_the_banner_is_about_a_third_the_size():
	var banner := RealmBanner.new()
	banner.setup(state, GameData.new())
	add_child_autofree(banner)
	assert_eq(_font(banner._name), RealmBanner.text_size(RealmBanner.NAME_SIZE, true))
	assert_lt(_font(banner._name), RealmBanner.NAME_SIZE * 0.4)
	assert_lt(_font(banner._detail), RealmBanner.DETAIL_SIZE * 0.45)
	assert_eq(RealmBanner.text_size(16, false), 16, "unchanged off a phone")
	assert_eq(RealmBanner.text_size(1, true), 5, "never unreadably small")


func test_small_text_keeps_its_spaces():
	for size in [5, 6, 7]:
		var font := PhoneLayout.small_font(size)
		var gap := font.get_string_size("a a", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x 			- font.get_string_size("aa", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		assert_gte(gap, 2.0, "%dpt" % size)
	assert_eq(PhoneLayout.small_font(7), PhoneLayout.small_font(7), "made once a size")
	var banner := RealmBanner.new()
	banner.setup(state, GameData.new())
	add_child_autofree(banner)
	assert_eq(banner._name.get_theme_font("font"), PhoneLayout.small_font(_font(banner._name)))


func test_chat_rows_are_small_and_more_of_them_fit():
	var panel := ChatPanel.new()
	panel.setup(state)
	add_child_autofree(panel)
	state.chat.apply_text({"from": ChatLog.SYSTEM, "to": "", "message": "hello"})
	panel._process(0.0)
	assert_eq(_font(panel._rows[0], "normal_font_size"), PhoneLayout.CHAT_FONT)
	assert_lt(PhoneLayout.CHAT_FONT, ChatRow.FONT_SIZE)
	assert_almost_eq(panel._scroll.custom_minimum_size.y, PhoneLayout.CHAT_LINES * PhoneLayout.CHAT_ROW, 0.01)
	assert_gt(PhoneLayout.CHAT_LINES, 3)
	assert_eq(panel._rows[0].get_theme_font("normal_font"), PhoneLayout.small_font(PhoneLayout.CHAT_FONT))
	assert_eq(panel._list.get_theme_constant("separation"), PhoneLayout.CHAT_GAP)


func test_a_quiet_log_fades_and_a_new_line_brings_it_back():
	assert_eq(ChatPanel.fade(0), 1.0)
	assert_eq(ChatPanel.fade(ChatPanel.FADE_AFTER_MS), 1.0, "three seconds untouched")
	assert_almost_eq(ChatPanel.fade(ChatPanel.FADE_AFTER_MS + ChatPanel.FADE_MS / 2), 0.5, 0.01)
	assert_eq(ChatPanel.fade(ChatPanel.FADE_AFTER_MS + ChatPanel.FADE_MS), 0.0)
	var panel := ChatPanel.new()
	panel.setup(state)
	add_child_autofree(panel)
	state.chat.apply_text({"from": ChatLog.SYSTEM, "to": "", "message": "one"})
	panel._process(0.0)
	assert_eq(panel._scroll.modulate.a, 1.0, "just said")
	panel._said_at_ms -= ChatPanel.FADE_AFTER_MS + ChatPanel.FADE_MS
	panel._process(0.0)
	assert_eq(panel._scroll.modulate.a, 0.0, "faded")
	state.chat.apply_text({"from": ChatLog.SYSTEM, "to": "", "message": "two"})
	panel._process(0.0)
	assert_eq(panel._scroll.modulate.a, 1.0, "back for the new line")
	panel._said_at_ms -= ChatPanel.FADE_AFTER_MS + ChatPanel.FADE_MS
	panel._touch_open = true
	panel._process(0.0)
	assert_eq(panel._scroll.modulate.a, 1.0, "open, it shows whatever the age")


func test_the_prompt_sits_over_the_player_not_on_the_bottom_buttons():
	var prompt := InteractPrompt.new()
	add_child_autofree(prompt)
	var button: Button = prompt._button
	assert_eq(button.anchor_top, 0.5)
	assert_eq(button.anchor_bottom, 0.5)
	assert_eq(button.offset_bottom, -InteractPrompt.PHONE_ABOVE_CENTRE, "over the player's head")
	assert_eq(button.grow_vertical, Control.GROW_DIRECTION_BEGIN, "and grows up from there")
	PhoneLayout.on = false
	var desktop := InteractPrompt.new()
	add_child_autofree(desktop)
	assert_eq(desktop._button.anchor_top, 1.0, "the desktop keeps it over the ability bar")
