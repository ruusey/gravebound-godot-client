extends GutTest

## The options: what each switch hides, that a choice is kept, and the
## panel's controls.

const PATH := "user://test_settings.cfg"

var content: GameData
var state: RealmState


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	state.local.id = 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func after_each():
	SpriteOutline.enabled = true
	WallBandPass.enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_every_switch_starts_on_and_a_choice_is_kept():
	for table in [GameSettings.DISPLAY, GameSettings.GRAPHICS]:
		for key in table:
			assert_true(state.settings.is_on(key), key)
	state.settings.load_from(PATH)
	state.settings.set_on("show_names", false)
	state.settings.set_on("vsync", false)
	var again := GameSettings.new()
	again.load_from(PATH)
	assert_false(again.is_on("show_names"), "read back by a new session")
	assert_false(again.is_on("vsync"))
	assert_true(again.is_on("show_chat_bubbles"), "untouched ones keep their default")


func test_an_empty_path_keeps_nothing():
	state.settings.set_on("show_names", false)
	assert_false(FileAccess.file_exists(PATH), "a test's settings never reach the disk")
	assert_false(state.settings.is_on("show_names"), "but still apply")


func test_outlines_and_wall_bands_follow_their_switches():
	state.settings.set_on("sprite_outlines", false)
	assert_false(SpriteOutline.enabled)
	state.settings.set_on("wall_bands", false)
	assert_false(WallBandPass.enabled)
	state.settings.set_on("sprite_outlines", true)
	assert_true(SpriteOutline.enabled)


func test_other_players_bullets_hide_but_ours_and_enemies_never_do():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO),
		WireHelper.player(2, "them", Vector2(10, 0))]})
	var theirs := Projectile.from_fields({"src_entity_id": 2})
	var ours := Projectile.from_fields({"src_entity_id": 1})
	var enemy := Projectile.from_fields({"src_entity_id": 77})
	assert_false(BulletRenderer._hidden(state, theirs), "on by default")
	state.settings.set_on("show_other_bullets", false)
	assert_true(BulletRenderer._hidden(state, theirs))
	assert_false(BulletRenderer._hidden(state, ours))
	assert_false(BulletRenderer._hidden(state, enemy))


func test_ability_effects_by_owner_and_all_at_once():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO),
		WireHelper.player(2, "them", Vector2(10, 0))]})
	var theirs := {"owner": 2}
	var ours := {"owner": 1}
	var boss := {"owner": 500}
	state.settings.set_on("show_ally_effects", false)
	assert_false(EffectRenderer.shown(state, theirs))
	assert_true(EffectRenderer.shown(state, ours))
	assert_true(EffectRenderer.shown(state, boss), "an enemy's warning always shows")
	state.settings.set_on("ability_animations", false)
	assert_false(EffectRenderer.shown(state, ours), "all animations off: even ours")
	assert_false(EffectRenderer.shown(state, boss))


func test_other_players_leave_the_ground_pass_and_the_overlay():
	state.local.position = Vector2.ZERO
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO),
		WireHelper.player(2, "them", Vector2(10, 0))]})
	var view := Rect2(-500, -500, 1000, 1000)
	var players := func() -> int:
		return EntityQueue.new().build(state, content, view).filter(
			func(e: Dictionary) -> bool: return e["kind"] == "players").size()
	assert_eq(players.call(), 2)
	state.settings.set_on("show_other_players", false)
	assert_eq(players.call(), 1, "only ourselves")


func test_the_overlay_drops_names_chips_bubbles_and_numbers():
	var overlay := EntityOverlay.new()
	overlay.setup(state)
	add_child_autofree(overlay)
	await wait_process_frames(1)
	state.local.name = "Ruu"
	state.local.effects = [4]
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "Ruu", Vector2.ZERO)]})
	state.apply_packet("TextPacket", {"from": "Ruu", "to": "Player", "message": "hello"})
	state.apply_packet("TextEffectPacket", {"textEffectId": 0, "entityType": 1, "targetEntityId": 0,
		"text": "-5", "posX": 1.0, "posY": 1.0})
	overlay.refresh()
	var tag: EntityTag = overlay._player_tags.acquire(1)
	assert_true(tag._name.visible)
	assert_gt(overlay.chips, 0)
	assert_eq(overlay.bubbles, 1)
	assert_eq(overlay._labels.texts, 1)
	for key in ["show_names", "show_status_chips", "show_chat_bubbles", "show_damage_numbers"]:
		state.settings.set_on(key, false)
	overlay.refresh()
	assert_false(tag._name.visible, "no name")
	assert_eq(overlay.chips, 0, "no chips")
	assert_eq(overlay.bubbles, 0, "no bubble")
	assert_eq(overlay._labels.texts, 0, "no numbers")


func test_the_transition_cover_can_be_switched_off():
	var screen := TransitionScreen.new()
	screen.setup(state, content)
	add_child_autofree(screen)
	state.begin_transition()
	screen._process(0.1)
	assert_true(screen.visible)
	state.settings.set_on("show_transition_screen", false)
	screen._process(0.1)
	assert_false(screen.visible)


func test_the_panel_has_a_box_a_setting_and_a_click_flips_it():
	var panel := OptionsPanel.new()
	panel.setup(state.settings, null)
	add_child_autofree(panel)
	await wait_process_frames(1)
	assert_eq(panel.boxes.size(), GameSettings.DISPLAY.size() + GameSettings.GRAPHICS.size() + GameSettings.AUDIO.size())
	assert_true(panel.boxes["vsync"].button_pressed)
	panel.boxes["vsync"].button_pressed = false
	assert_false(state.settings.is_on("vsync"), "the click is the setting")
	state.settings.set_on("show_names", false)
	panel.refresh()
	assert_false(panel.boxes["show_names"].button_pressed, "and the boxes follow the settings")
	panel.toggle()
	panel._process(0.0)
	assert_false(panel.visible, "never up outside a realm")


func test_an_unknown_or_unchanged_switch_does_nothing():
	var told := [0]
	state.settings.changed.connect(func() -> void: told[0] += 1)
	state.settings.set_on("no_such_setting", false)
	state.settings.set_on("show_names", true)
	assert_eq(told[0], 0, "nothing changed, so nothing is said or saved")
	assert_true(state.settings.is_on("no_such_setting"), "an unknown key reads as on, as a default would")
	state.settings.set_on("show_names", false)
	assert_eq(told[0], 1)


func test_the_ui_scale_row_shows_the_scale_and_keeps_a_choice():
	var settings := GameSettings.new()
	settings.load_from(PATH)
	var row := ScaleRow.new(settings)
	var drawn := [1.75]   # a box: what the screen is drawn at
	row.current = func() -> float: return drawn[0]
	add_child_autofree(row)
	row.refresh()
	assert_eq(row.value_label.text, "1.75x (auto)", "automatic until chosen, and says so")
	assert_true(row.auto_button.disabled, "nothing to go back to")
	assert_eq(row.slider.value, 1.75)
	row.choose(2.25)
	drawn[0] = 2.25
	row.refresh()
	assert_eq(settings.ui_scale, 2.25)
	assert_eq(row.value_label.text, "2.25x", "the chosen scale, no (auto)")
	assert_false(row.auto_button.disabled)
	var again := GameSettings.new()
	again.load_from(PATH)
	assert_eq(again.ui_scale, 2.25, "kept for next time")
	row.auto_button.pressed.emit()
	assert_eq(settings.ui_scale, 0.0, "Auto hands it back")


func test_dragging_the_slider_shows_the_number_and_applies_only_on_letting_go():
	var settings := GameSettings.new()
	var row := ScaleRow.new(settings)
	add_child_autofree(row)
	row.slider.drag_started.emit()
	row.slider.value = 2.5
	assert_eq(row.value_label.text, "2.5x", "the number as it moves")
	assert_eq(settings.ui_scale, 0.0, "not applied mid-drag")
	row.slider.drag_ended.emit(true)
	assert_eq(settings.ui_scale, 2.5, "applied when let go")


func test_the_options_carry_the_ui_scale_row():
	var options := OptionsPanel.new()
	options.setup(GameSettings.new(), null)
	add_child_autofree(options)
	assert_not_null(options.scale_row)
	assert_true(options.scale_row.is_inside_tree(), "on the Display tab")


func test_the_world_zoom_row_keeps_its_own_setting():
	var settings := GameSettings.new()
	settings.load_from(PATH)
	var row := ScaleRow.new(settings, ScaleRow.WORLD)
	var drawn := [1.75]
	row.current = func() -> float: return drawn[0]
	add_child_autofree(row)
	assert_eq(row.slider.max_value, 4.0, "the world goes to 4x")
	assert_eq(row.value_label.text, "1.75x (auto)")
	row.choose(3.0)
	drawn[0] = 3.0
	row.refresh()
	assert_eq(settings.world_zoom, 3.0)
	assert_eq(settings.ui_scale, 0.0, "the UI scale is not the world's")
	assert_eq(row.value_label.text, "3x")
	var again := GameSettings.new()
	again.load_from(PATH)
	assert_eq(again.world_zoom, 3.0, "kept for next time")
	row.auto_button.pressed.emit()
	assert_eq(settings.world_zoom, 0.0, "Auto hands it back")


func test_the_options_carry_both_scale_rows():
	var options := OptionsPanel.new()
	options.setup(GameSettings.new(), null)
	add_child_autofree(options)
	assert_eq(options.scale_row.setting, ScaleRow.UI)
	assert_eq(options.zoom_row.setting, ScaleRow.WORLD)
	assert_true(options.zoom_row.is_inside_tree())
