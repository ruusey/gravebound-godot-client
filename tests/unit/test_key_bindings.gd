extends GutTest

## Rebinding: the input map follows, a taken key swaps, a choice is kept,
## and the Controls tab binds the next key pressed.

const PATH := "user://test_bindings.cfg"


func before_each():
	KeyBindings.apply({})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func after_each():
	KeyBindings.apply({})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _key(physical: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = true
	return event


func test_the_defaults_are_the_projects():
	assert_eq(KeyBindings.default_key("move_up"), KEY_W)
	assert_eq(KeyBindings.key_of("move_up"), KEY_W)
	assert_eq(KeyBindings.default_key("toggle_minimap"), KEY_M, "the minimap's M is an action now")
	assert_eq(KeyBindings.custom(), {}, "nothing changed, nothing to keep")


func test_a_new_key_drives_the_action_and_the_old_one_no_longer_does():
	assert_eq(KeyBindings.rebind("move_up", KEY_O), ["move_up"])
	assert_true(_key(KEY_O).is_action("move_up"))
	assert_false(_key(KEY_W).is_action("move_up"))
	assert_eq(KeyBindings.custom(), {"move_up": KEY_O})


func test_a_taken_key_swaps_so_nothing_is_left_unbound():
	var changed := KeyBindings.rebind("move_up", KEY_S)
	assert_eq(changed, ["move_up", "move_down"])
	assert_eq(KeyBindings.key_of("move_up"), KEY_S)
	assert_eq(KeyBindings.key_of("move_down"), KEY_W, "down takes up's old key")
	assert_eq(KeyBindings.rebind("move_up", KEY_S), [], "the same key again changes nothing")


func test_a_choice_is_kept_and_reset_puts_the_defaults_back():
	var settings := GameSettings.new()
	settings.load_from(PATH)
	settings.rebind("drink_hp", KEY_Q)
	KeyBindings.apply({})
	assert_eq(KeyBindings.key_of("drink_hp"), KEY_Z, "wiped in memory")
	var again := GameSettings.new()
	again.load_from(PATH)
	assert_eq(KeyBindings.key_of("drink_hp"), KEY_Q, "and read back by a new session")
	again.reset_keys()
	assert_eq(KeyBindings.key_of("drink_hp"), KEY_Z)
	var third := GameSettings.new()
	third.load_from(PATH)
	assert_eq(KeyBindings.key_of("drink_hp"), KEY_Z, "the reset is kept too")


func test_the_controls_tab_binds_the_next_key_and_escape_cancels():
	var settings := GameSettings.new()
	var tab := ControlsTab.new(settings)
	add_child_autofree(tab)
	await wait_process_frames(1)
	assert_eq(tab.buttons.size(), KeyBindings.all_actions().size())
	assert_eq(tab.buttons["move_up"].text, "W")
	tab.buttons["move_up"].pressed.emit()
	assert_eq(tab.waiting_for, "move_up")
	assert_eq(tab.buttons["move_up"].text, ControlsTab.WAITING)
	tab.take(_key(KEY_O))
	assert_eq(KeyBindings.key_of("move_up"), KEY_O)
	assert_eq(tab.buttons["move_up"].text, "O")
	assert_eq(tab.waiting_for, "", "one key, then done")
	tab.listen("move_down")
	tab.take(_key(KEY_ESCAPE))
	assert_eq(KeyBindings.key_of("move_down"), KEY_S, "escape binds nothing")
	assert_eq(tab.buttons["move_down"].text, "S")


func test_while_waiting_the_options_own_the_keyboard():
	var state := RealmState.new()
	var panel := OptionsPanel.new()
	panel.setup(state.settings, null)
	add_child_autofree(panel)
	await wait_process_frames(1)
	panel.visible = true
	assert_false(panel.capturing())
	panel.controls.listen("move_up")
	assert_true(panel.capturing(), "so W is a binding, not a step forward")
	panel.close()
	assert_false(panel.capturing(), "closing stops waiting")


func test_the_minimap_answers_its_new_key():
	KeyBindings.rebind("toggle_minimap", KEY_N)
	var panel := MinimapPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var shown := panel.shown
	panel._unhandled_input(_key(KEY_M))
	assert_eq(panel.shown, shown, "M does nothing now")
	panel._unhandled_input(_key(KEY_N))
	assert_ne(panel.shown, shown, "N toggles it")


func test_the_directory_has_the_backtick_and_the_screenshot_moved_off_it():
	assert_eq(KeyBindings.default_key("toggle_social"), KEY_QUOTELEFT)
	assert_eq(KeyBindings.default_key("screenshot"), KEY_P)


func test_a_bag_slot_is_shift_and_its_key_and_keeps_its_own_group():
	assert_eq(KeyBindings.binding_name("quick_slot_1"), "Shift+1")
	var shifted := _key(KEY_1)
	shifted.shift_pressed = true
	assert_true(shifted.is_action("quick_slot_1", true))
	assert_false(_key(KEY_1).is_action("quick_slot_1", true), "a bare 1 is a cast")
	assert_eq(KeyBindings.rebind("quick_slot_1", KEY_2), ["quick_slot_1", "quick_slot_2"],
		"swaps with the other bag slot, never with the ability on 2")
	assert_eq(KeyBindings.key_of("ability_2"), KEY_2)
	var moved := _key(KEY_2)
	moved.shift_pressed = true
	assert_true(moved.is_action("quick_slot_1", true), "still Shift after a rebind")


func test_every_hard_wired_key_is_an_action_now():
	for action in ["open_command", "orbit_left", "orbit_right", "toggle_lighting", "debug_packet_mix",
			"toggle_collision_view", "record_hitches", "screenshot", "toggle_social"]:
		assert_true(action in KeyBindings.all_actions(), action)
		assert_ne(KeyBindings.key_of(action), 0, action + " has a key")
