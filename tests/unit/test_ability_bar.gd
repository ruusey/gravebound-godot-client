extends GutTest

## The hotbar on screen, the character sheet, and the cells they are made of.

var state: RealmState
var content: GameData
var client: GraveBoundClient
var transport: FakeTransport
var caster: AbilityCaster
var skills: SkillsPanel
var bar: AbilityBar
var aim: Node2D
var now := 5000


func before_each():
	now = 5000
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return now)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	aim = Node2D.new()
	add_child_autofree(aim)
	caster = AbilityCaster.new(state, client, content, aim)
	skills = SkillsPanel.new()
	skills.setup(state, content, client)
	add_child_autofree(skills)
	bar = AbilityBar.new()
	bar.setup(state, content, caster, skills)
	add_child_autofree(bar)


func _enter(class_id := 2) -> void:
	state.local.id = 9
	state.local.class_id = class_id
	state.local.mana = 500
	state.local.stats = {"hp": 130, "mp": 130, "dex": 12}


func _in_game() -> void:
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	_enter()
	transport.clear_sent()


func _points(available: int, invested := [0, 0, 0, 0]) -> void:
	state.abilities.apply_update({"playerId": 9, "availableSkillPoints": available,
		"investedSlot0": invested[0], "investedSlot1": invested[1],
		"investedSlot2": invested[2], "investedSlot3": invested[3]}, 9)


func _names() -> Array:
	var out: Array = []
	for packet in transport.sent_packets():
		out.append(packet["name"])
	return out


# --- the bar ---------------------------------------------------------------

func test_hidden_until_we_are_in_a_realm():
	bar._process(0.0)
	assert_false(bar.visible)
	_enter()
	bar._process(0.0)
	assert_true(bar.visible)
	bar.toggle()
	bar._process(0.0)
	assert_false(bar.visible)


func test_the_cells_show_the_classs_hotbar():
	_enter()
	_points(0, [2, 0, 0, 0])
	bar._process(0.0)
	assert_eq(bar._cells[0]._fallback.text, "Ar", "the passive, by its initials")
	assert_not_null(bar._cells[1]._icon.texture, "Fire Breath's icon")
	assert_eq(bar._cells[1]._cost.text, "60")
	assert_eq(bar._cells[1].pips(), [2, 5], "two of five pips lit")
	assert_eq(bar._cells[2].pips(), [0, 3])
	assert_null(bar._cells[3]._icon.texture, "Supernova has no sprite key")
	assert_eq(bar._cells[3]._fallback.text, "Su", "so it falls back to text")


func test_an_empty_slot_and_a_missing_passive_are_blank():
	_enter(0)
	bar._process(0.0)
	assert_eq(bar._cells[2]._cost.text, "", "the barbarian's second slot")
	assert_eq(bar._cells[2].pips(), [0, 0])
	state.local.class_id = 99
	bar._process(0.0)
	assert_eq(bar._cells[0]._fallback.text, "")
	assert_eq(bar._cells[1]._fallback.text, "")


func test_the_shade_follows_the_cooldown():
	_enter()
	bar._process(0.0)
	assert_almost_eq(bar._cells[1]._shade.anchor_top, 1.0, 0.001, "nothing cooling")
	state.abilities.start_cooldown(0, 2000)
	bar._process(0.0)
	assert_almost_eq(bar._cells[1]._shade.anchor_top, 0.0, 0.001, "fully shaded")
	now += 1500
	bar._process(0.0)
	assert_almost_eq(bar._cells[1]._shade.anchor_top, 0.75, 0.001)


func test_a_click_casts_and_a_right_click_opens_the_sheet():
	_in_game()
	bar._process(0.0)
	bar._cells[0].pressed.emit(0)
	assert_eq(_names(), [], "the passive is not pressable")
	bar._cells[1].pressed.emit(1)
	assert_eq(_names(), ["UseAbilityPacket"])
	bar._cells[1].secondary.emit(1)
	assert_true(skills.shown)
	bar._cells[0].secondary.emit(0)
	assert_true(skills.shown, "not the passive")


func test_the_card_describes_a_cell():
	_enter()
	_points(0, [1, 0, 0, 0])
	bar._process(0.0)
	var lines := bar.describe(1)
	assert_eq(lines[0][0], "Fire Breath")
	assert_eq(lines[1][0], "Active - Key 1")
	assert_eq(lines[2][0], "A cone of flame.")
	assert_eq(lines[3][0], "MP 60 - Cooldown 2.3s - Instant - Range 352")
	assert_eq(lines[-1][0], "Level 1/5")
	assert_eq(bar.describe(0)[0][0], "Arcane Well")
	assert_eq(bar.describe(0)[1][0], "Class passive - always on")
	state.local.class_id = 0
	bar._process(0.0)
	var texts := bar.describe(3).map(func(line: Array) -> String: return line[0])
	assert_eq(texts[1], "Active - Key 3")
	assert_true(texts.any(func(text: String) -> bool: return text.begins_with("MP 60 - Cooldown 12.0s")))
	assert_eq(bar.describe(2), [], "an empty slot")


func test_the_card_is_no_wider_than_its_content_allows():
	# Seen live: the card ran the whole width of the window.
	_enter()
	bar._process(0.0)
	bar._cells[1].hovered.emit(1, true)
	await wait_process_frames(2)
	var card := bar._tooltip
	assert_lte(card.size.x, ItemTooltip.WIDTH + 2.0, "width %s, plus a 1px border each side" % card.size.x)
	assert_gt(card.size.y, 0.0)
	assert_lt(card.size.y, 200.0, "height %s" % card.size.y)


func test_hovering_opens_and_closes_the_card():
	_enter()
	bar._process(0.0)
	bar._cells[1].hovered.emit(1, true)
	assert_true(bar._tooltip.visible)
	bar._process(0.0)
	assert_true(bar._tooltip.visible, "and it follows the mouse")
	bar._cells[1].hovered.emit(1, false)
	assert_false(bar._tooltip.visible)
	state.local.class_id = 0
	bar._process(0.0)
	bar._cells[2].hovered.emit(2, true)
	assert_false(bar._tooltip.visible, "nothing to say about an empty slot")


func test_without_a_caster_or_a_sheet_a_gesture_is_nothing():
	var mute := AbilityBar.new()
	mute.setup(state, content, null)
	add_child_autofree(mute)
	_enter()
	mute._process(0.0)
	mute._cells[1].pressed.emit(1)
	mute._cells[1].secondary.emit(1)
	assert_true(mute.visible)
	assert_false(mute.captures_mouse(), "the mouse is not over the bar")


# --- the sheet -------------------------------------------------------------

func test_the_sheet_is_closed_until_asked():
	_enter()
	skills._process(0.0)
	assert_false(skills.visible)
	assert_false(skills.captures_mouse(), "hidden, it owns nothing")
	skills.toggle()
	skills._process(0.0)
	assert_true(skills.visible)
	assert_false(bar.captures_mouse(), "hidden, the bar owns nothing either")


func test_the_sheet_shows_stats_points_and_levels():
	_enter()
	_points(2, [1, 3, 0, 0])
	skills.toggle()
	skills._process(0.0)
	assert_string_contains(skills._stats.text, "HP 130")
	assert_string_contains(skills._stats.text, "DEX 12")
	assert_eq(skills._points.text, "Skill points: 2")
	assert_eq(skills._names[0].text, "Fire Breath")
	assert_eq(skills._levels[0].text, "1/5")
	assert_false(skills._buttons[0].disabled)
	assert_eq(skills._levels[1].text, "3/3")
	assert_true(skills._buttons[1].disabled, "capped")
	state.local.class_id = 0
	skills._process(0.0)
	assert_eq(skills._names[1].text, "(empty)")
	assert_true(skills._buttons[1].disabled)


func test_no_points_disables_every_button():
	_enter()
	_points(0)
	skills.toggle()
	skills._process(0.0)
	for button in skills._buttons:
		assert_true(button.disabled)


func test_investing_sends_the_slot_when_the_server_would_take_it():
	_in_game()
	_points(1, [0, 3, 0, 0])
	assert_true(skills.invest(0))
	assert_eq(_names(), ["InvestSkillPointPacket"])
	assert_eq(int(transport.sent_packets()[0]["data"]["slot"]), 0)
	transport.clear_sent()
	assert_false(skills.invest(1), "capped")
	assert_false(skills.invest(3), "no such slot")
	state.local.class_id = 0
	assert_false(skills.invest(1), "nothing bound there")
	state.local.class_id = 2
	_points(0)
	assert_false(skills.invest(0), "no points")
	assert_eq(_names(), [])


func test_a_button_press_invests():
	_in_game()
	_points(1)
	skills.toggle()
	skills._process(0.0)
	skills._buttons[2].pressed.emit()
	assert_eq(int(transport.sent_packets()[0]["data"]["slot"]), 2)


func test_investing_needs_a_realm_and_a_client():
	_enter()
	_points(1)
	assert_false(skills.invest(0))
	var mute := SkillsPanel.new()
	mute.setup(state, content, null)
	add_child_autofree(mute)
	assert_false(mute.invest(0))


# --- a cell ------------------------------------------------------------------

func test_a_cell_reports_its_clicks():
	var cell := AbilityCell.new(2, "2")
	add_child_autofree(cell)
	var seen := []
	cell.pressed.connect(func(index: int) -> void: seen.append(["pressed", index]))
	cell.secondary.connect(func(index: int) -> void: seen.append(["secondary", index]))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	cell._gui_input(click)
	click.pressed = false
	cell._gui_input(click)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	cell._gui_input(right)
	cell._gui_input(InputEventKey.new())
	assert_eq(seen, [["pressed", 2], ["secondary", 2]])


func test_a_cell_shows_and_empties():
	var cell := AbilityCell.new(1, "1")
	add_child_autofree(cell)
	cell.show_ability(null, "Rage", 60, 2, 5)
	assert_eq(cell._fallback.text, "Ra")
	assert_eq(cell._cost.text, "60")
	assert_eq(cell.pips(), [2, 5])
	# The column runs down the right edge from the top corner, lit pips first.
	assert_true(cell._pips.is_lit(0))
	assert_false(cell._pips.is_lit(2))
	assert_eq(cell._pips.pip(0).get_theme_stylebox("panel").bg_color, PipColumn.SPENT)
	assert_eq(cell._pips.pip(4).get_theme_stylebox("panel").bg_color, PipColumn.EMPTY)
	assert_gt(cell._pips.pip(1).position.y, cell._pips.pip(0).position.y, "stacked downward")
	var side := PipColumn.pip_px(AbilityCell.SIZE_PX)
	assert_almost_eq(cell._pips.pip(0).position.x + side, AbilityCell.SIZE_PX - PipColumn.INSET, 0.01)
	assert_almost_eq(cell._pips.pip(0).position.y, PipColumn.INSET, 0.01)
	assert_eq(cell._pips.pip(0).size, Vector2(side, side))
	assert_eq(PipColumn.pip_px(44), 5.0, "the web client's 5px in its 44px cell")
	assert_eq(PipColumn.pip_px(64), 7.0)
	assert_lt(cell._pips.pip(4).position.y + side, float(AbilityCell.SIZE_PX), "five fit inside the cell")
	cell.show_ability(null, "Rage", 60, 5, 3)
	assert_eq(cell.pips(), [3, 3], "rebuilt for a new cap, never over-lit")
	cell.show_ability(null, "Muscle", 0, 0, 0)
	assert_eq(cell._cost.text, "", "a passive has no cost")
	assert_eq(cell.pips(), [0, 0], "nor pips")
	cell.show_empty()
	assert_eq(cell._fallback.text, "")
	cell.set_cooldown(1.5)
	assert_almost_eq(cell._shade.anchor_top, 0.0, 0.001, "clamped")
