extends GutTest

## Quests: the log from QuestStatePacket, its cards and their commands, the
## star chip, the key, and the stars under every name.

var content: GameData
var state: RealmState
var client: OpenRealmClient
var transport: FakeTransport


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = OpenRealmClient.new()
	client.connection.transport = transport
	add_child_autofree(client)


func _in_game() -> void:
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	transport.clear_sent()


func _quest(id: int, status: String, auto := true, extra := {}) -> Dictionary:
	var quest := {"id": id, "name": "Quest %d" % id, "desc": "Do the thing.", "cat": "COMBAT",
		"status": status, "auto": auto, "stars": 1,
		"objectives": [{"label": "Slay 25 enemies", "progress": 10, "target": 25}], "rewards": []}
	quest.merge(extra, true)
	return quest


func _snapshot(stars: int, quests: Array, player := 9) -> void:
	state.apply_packet("QuestStatePacket", {"playerId": player, "stars": stars,
		"json": JSON.stringify({"stars": stars, "quests": quests})})


func test_the_log_is_ours_whole_and_kept_across_realms():
	state.local.id = 9
	_snapshot(4, [_quest(1, "ACTIVE")], 77)
	assert_eq(state.progress.quests, [], "someone else's")
	_snapshot(4, [_quest(1, "COMPLETE"), _quest(2, "AVAILABLE", false), _quest(3, "ACTIVE")])
	assert_eq(state.progress.stars, 4)
	assert_eq(state.progress.sorted_quests().map(func(q: Dictionary) -> int: return int(q["id"])), [3, 2, 1],
		"active, then available, then complete")
	_snapshot(5, [_quest(3, "ACTIVE")])
	assert_eq(state.progress.quests.size(), 1, "a snapshot replaces, it does not merge")
	state.reset_world()
	assert_eq(state.progress.stars, 5, "not sent again on a realm change, so not cleared")
	state.apply_packet("QuestStatePacket", {"playerId": 9, "stars": 5, "json": "{not json"})
	assert_eq(state.progress.quests, [], "a payload that does not parse empties the list")


func test_rewards_read_as_the_web_words_them():
	var text := func(reward: Dictionary) -> String: return QuestCard.reward_text(reward, content)
	assert_eq(text.call({"type": "FAME", "amount": 1500}), "1,500 Fame")
	assert_eq(text.call({"type": "ITEM", "amount": 1, "targetId": 100}), "Short Bow")
	assert_eq(text.call({"type": "POTION", "amount": 3, "targetId": 101}), "Scattergun x3")
	assert_eq(text.call({"type": "ITEM", "amount": 1, "targetId": 9999}), "Item #9999")
	assert_eq(text.call({"type": "SKILL_XP", "amount": 250, "skillId": 1}), "250 Melee Combat Mastery XP")
	assert_eq(text.call({"type": "STAT_POINT", "amount": 2, "stat": "VIT"}), "+2 VIT")
	assert_eq(text.call({"type": "STAT_POINT", "amount": 1}), "+1 Stat Point")
	assert_eq(text.call({"type": "UNLOCK_VAULT_CHEST", "amount": 2}), "2 Vault Chests")
	assert_eq(text.call({"type": "UNLOCK_CHARACTER_SLOT", "amount": 1}), "1 Character Slot")
	assert_eq(text.call({"type": "SOMETHING_NEW", "amount": 1}), "SOMETHING_NEW")


func test_a_card_offers_only_what_the_server_would_take():
	var asked := []
	var act := func(verb: String, id: int) -> void: asked.append([verb, id])
	var available := QuestCard.new(_quest(6, "AVAILABLE", false), content, act)
	var chosen := QuestCard.new(_quest(7, "ACTIVE", false), content, act)
	var automatic := QuestCard.new(_quest(1, "ACTIVE", true), content, act)
	var done := QuestCard.new(_quest(2, "COMPLETE"), content, act)
	for card in [available, chosen, automatic, done]:
		autofree(card)
	assert_not_null(available.accept_button)
	available.accept_button.pressed.emit()
	assert_not_null(chosen.abandon_button)
	chosen.abandon_button.pressed.emit()
	assert_eq(asked, [["accept", 6], ["abandon", 7]])
	assert_null(automatic.abandon_button, "an auto-started quest cannot be abandoned")
	assert_null(done.accept_button)
	assert_null(done.abandon_button)
	assert_almost_eq(done.modulate.a, 0.82, 0.001, "a finished quest is dimmed")


func test_a_card_carries_its_tags_and_rewards():
	var card := QuestCard.new(_quest(4, "ACTIVE", true, {"scoped": true, "repeatable": true,
		"rewards": [{"type": "FAME", "amount": 300}, {"type": "UNLOCK_CHARACTER_SLOT", "amount": 2}]}),
		content, func(_v: String, _i: int) -> void: pass)
	autofree(card)
	var texts := card.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_has(texts, "Quest 4  [CHARACTER]  [REPEATABLE]")
	assert_has(texts, "300 Fame")
	assert_has(texts, "2 Character Slots")
	assert_has(texts, "IN PROGRESS")


func test_a_status_the_client_does_not_know_goes_last():
	state.local.id = 9
	_snapshot(0, [_quest(1, "LOCKED"), _quest(2, "COMPLETE"), _quest(3, "ACTIVE")])
	assert_eq(state.progress.sorted_quests().map(func(q: Dictionary) -> int: return int(q["id"])), [3, 2, 1])


func test_an_objective_bar_is_its_progress():
	var box := VBoxContainer.new()
	autofree(box)
	var bar := QuestObjectiveRow.add(box, {"label": "Slay", "progress": 30, "target": 25}, 200)
	assert_eq([bar.value, bar.max_value], [25.0, 25.0], "clamped at the target")
	assert_string_contains((box.get_child(0).get_child(0) as Label).text, "[x]", "and ticked")


func test_the_panel_lists_the_cards_and_sends_the_command():
	_in_game()
	var panel := QuestLogPanel.new()
	panel.setup(state, content, client)
	add_child_autofree(panel)
	await wait_process_frames(1)
	_snapshot(3, [_quest(1, "ACTIVE"), _quest(6, "AVAILABLE", false)])
	panel._process(0.0)
	assert_true(panel.visible)
	assert_eq(panel.chip.text, "3 Stars")
	assert_false(panel._dialog.visible, "the log is shut until asked for")
	panel.chip.pressed.emit()
	panel._process(0.0)
	assert_true(panel._dialog.visible)
	assert_eq(panel._cards.get_child_count(), 2)
	assert_true(panel.act("accept", 6))
	var sent := transport.sent_packets()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["name"], "CommandPacket")
	var id := state.local.id
	state.local.id = 0
	panel._process(0.0)
	assert_false(panel.captures_mouse(), "out of a realm it is not up to be clicked")
	state.local.id = id
	panel.close()
	panel._process(0.0)
	assert_false(panel._dialog.visible)
	panel.toggle()
	_snapshot(3, [])
	panel._process(0.0)
	await wait_process_frames(1)
	assert_eq(panel._cards.get_child_count(), 1)
	assert_eq((panel._cards.get_child(0) as Label).text, "No active quests.")


func test_l_opens_the_log_in_a_realm_and_can_be_rebound():
	var panel := QuestLogPanel.new()
	panel.setup(state, content, client)
	add_child_autofree(panel)
	await wait_process_frames(1)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	panel._unhandled_input(key)
	assert_false(panel.shown, "not from the sign-in screen")
	state.local.id = 9
	panel._unhandled_input(key)
	assert_true(panel.shown)
	assert_eq(KeyBindings.default_key("toggle_quests"), KEY_L)
	assert_true(KeyBindings.ACTIONS.has("toggle_quests"), "on the Controls tab, so it can be rebound")


func test_stars_ride_the_update_and_sit_under_the_name():
	state.local.id = 9
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(9, "Ruu", Vector2.ZERO),
		WireHelper.player(10, "Mingau", Vector2(40, 0))]})
	state.apply_packet("UpdatePacket", {"playerId": 10, "stars": 7, "stats": {}})
	assert_eq(state.entities.players[10]["stars"], 7)
	var overlay := EntityOverlay.new()
	overlay.setup(state)
	add_child_autofree(overlay)
	await wait_process_frames(1)
	overlay.refresh()
	var theirs: EntityTag = overlay._player_tags.acquire(10)
	var mine: EntityTag = overlay._player_tags.acquire(9)
	assert_true(theirs._stars.visible)
	assert_eq(theirs._stars.text, "7")
	assert_true(theirs._star.visible, "a drawn star, not a glyph the web font lacks")
	assert_eq(theirs._stars.label_settings.font_color, Color("ffd34d"), "the web's gold, really applied")
	assert_gt(theirs._stars.position.y, theirs._mp.position.y, "under the bars")
	assert_false(mine._stars.visible, "no stars, no line")
