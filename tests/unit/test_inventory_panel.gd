extends GutTest

## The bag on screen, and the card that opens over an item.

var state: RealmState
var content: GameData
var panel: InventoryPanel
var client: GraveBoundClient
var transport: FakeTransport
var actions: InventoryActions


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	actions = InventoryActions.new(state, client, content)
	panel = InventoryPanel.new()
	panel.setup(state, content, actions)
	add_child_autofree(panel)


func _enter() -> void:
	state.local.id = 9
	state.local.class_id = 2
	state.local.position = Vector2.ZERO


func _in_game() -> void:
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	transport.clear_sent()


func _put(slot: int, item_id: int, extra := {}) -> void:
	var item := content.item_definition(item_id).duplicate()
	item.merge(extra, true)
	state.local.inventory.put(slot, item)


func _bag_at_feet(items: Array) -> void:
	state.entities.apply_load({"containers": [{"lootContainerId": 3, "uid": "", "isChest": false,
		"tier": 0, "items": items, "pos": {"x": 4.0, "y": 0.0}, "spawnedTime": 0,
		"contentsChanged": false, "soulboundPlayerId": 0}]})


func _frame() -> void:
	panel._process(0.0)


func _packet_names() -> Array:
	var names: Array = []
	for packet in transport.sent_packets():
		names.append(packet["name"])
	return names


# --- showing ---------------------------------------------------------------

func test_hidden_until_we_are_in_a_realm():
	_frame()
	assert_false(panel.visible)
	_enter()
	_frame()
	assert_true(panel.visible)


func test_tab_puts_it_away_and_brings_it_back():
	_enter()
	panel.toggle()
	_frame()
	assert_false(panel.visible)
	panel.toggle()
	_frame()
	assert_true(panel.visible)


func test_does_nothing_without_state():
	var bare := InventoryPanel.new()
	add_child_autofree(bare)
	bare._process(0.0)
	assert_false(bare.visible)


func test_slots_show_the_items_in_their_positions():
	_enter()
	_put(0, 102)
	_put(5, 200)
	_frame()
	assert_not_null(panel._equipment[0]._icon.texture, "the weapon slot")
	assert_null(panel._equipment[1]._icon.texture, "the empty armor slot")
	assert_not_null(panel._backpack[0]._icon.texture, "the first backpack cell")
	assert_null(panel._backpack[1]._icon.texture)


func test_the_second_page_is_slots_25_to_44():
	_enter()
	_put(25, 100)
	_frame()
	assert_null(panel._backpack[0]._icon.texture, "not on page one")
	panel.set_page(1)
	_frame()
	assert_eq(panel._backpack[0].index, 25)
	assert_eq(panel._backpack[19].index, 44)
	assert_not_null(panel._backpack[0]._icon.texture)
	assert_true(panel._tabs[1].button_pressed)
	assert_false(panel._tabs[0].button_pressed)
	panel.set_page(7)
	assert_eq(panel.page, 1, "clamped to the pages there are")


func test_the_page_buttons_switch_pages():
	_enter()
	panel._tabs[1].pressed.emit()
	_frame()
	assert_eq(panel.page, 1)


func test_redraws_only_when_the_bag_changed():
	_enter()
	_frame()
	# Straight into the array, no version bump: the panel must not notice.
	state.local.inventory.slots[5] = content.item_definition(200).duplicate()
	_frame()
	assert_null(panel._backpack[0]._icon.texture)
	state.local.inventory.put(5, content.item_definition(200).duplicate())
	_frame()
	assert_not_null(panel._backpack[0]._icon.texture)


func test_stack_counts_show_on_stacks_of_more_than_one():
	_enter()
	_put(5, 105, {"stackCount": 7})
	_put(6, 105, {"stackCount": 1})
	_put(7, 102)
	_frame()
	assert_eq(panel._backpack[0]._count.text, "x7")
	assert_eq(panel._backpack[1]._count.text, "")
	assert_eq(panel._backpack[2]._count.text, "")


func test_the_potion_buttons_show_the_pools():
	_enter()
	state.local.inventory.apply_update({"playerId": 9, "inventory": [], "hpPotions": 3, "mpPotions": 1})
	_frame()
	assert_string_contains(panel._hp.text, "3")
	assert_string_contains(panel._mp.text, "1")


func test_the_loot_strip_opens_beside_a_bag_and_closes_without_one():
	_enter()
	_frame()
	assert_false(panel._loot_box.visible)
	_bag_at_feet([{"itemId": 100}, {"itemId": -1}])
	_frame()
	assert_true(panel._loot_box.visible)
	assert_eq(panel._loot[0].index, Inventory.GROUND_LOOT_START)
	assert_not_null(panel._loot[0]._icon.texture)
	assert_null(panel._loot[1]._icon.texture)
	state.entities.apply_unload({"containers": [3]})
	_frame()
	assert_false(panel._loot_box.visible)


func test_a_pickup_redraws_the_strip_without_a_version():
	_enter()
	_bag_at_feet([{"itemId": 100}, {"itemId": 102}])
	_frame()
	_bag_at_feet([{"itemId": 102}])
	_frame()
	assert_null(panel._loot[1]._icon.texture)


func test_captures_nothing_while_hidden():
	assert_false(panel.captures_mouse())


# --- gestures ---------------------------------------------------------------

func test_gestures_reach_the_server():
	_in_game()
	_put(5, 200)
	_put(6, 105, {"stackCount": 4})
	_frame()
	var slot: ItemSlot = panel._backpack[0]
	slot.dropped.emit(5, 6)
	slot.activated.emit(5)
	slot.secondary.emit(5, false)
	slot.thrown.emit(5)
	panel._backpack[1].secondary.emit(6, true)
	panel._hp.pressed.emit()
	assert_eq(_packet_names(), ["MoveItemPacket", "MoveItemPacket", "MoveItemPacket",
		"MoveItemPacket", "SplitStackPacket"], "and no drink from an empty pool")


func test_without_a_client_a_gesture_is_nothing():
	# A scripted capture builds the panel with nowhere to send to.
	var mute := InventoryPanel.new()
	mute.setup(state, content, InventoryActions.new(state, null, content))
	add_child_autofree(mute)
	_enter()
	_put(5, 200)
	mute._process(0.0)
	var slot: ItemSlot = mute._backpack[0]
	slot.dropped.emit(5, 6)
	slot.activated.emit(5)
	slot.secondary.emit(5, true)
	slot.secondary.emit(5, false)
	slot.thrown.emit(5)
	mute._hp.pressed.emit()
	slot.hovered.emit(5, true)
	assert_true(mute._tooltip.visible, "the card still reads the bag")
	assert_true(mute.visible, "still standing")


func test_the_card_opens_over_an_item_and_closes_off_it():
	_enter()
	_put(5, 102)
	_frame()
	panel._backpack[0].hovered.emit(5, true)
	assert_true(panel._tooltip.visible)
	assert_string_contains(panel._tooltip._lines.get_child(0).text, "Broken Wand")
	_frame()
	assert_true(panel._tooltip.visible, "and it follows the mouse frame to frame")
	# Onto another item: the card is rebuilt, not appended to.
	_put(6, 200)
	_frame()
	panel._backpack[1].hovered.emit(6, true)
	assert_string_contains(panel._tooltip._lines.get_child(0).text, "Health Potion")
	assert_lt(panel._tooltip._lines.get_child_count(), 5, "the wand's lines are gone")
	panel._backpack[0].hovered.emit(5, false)
	assert_false(panel._tooltip.visible)
	panel._backpack[2].hovered.emit(7, true)
	assert_false(panel._tooltip.visible, "nothing to say about an empty cell")


func test_the_card_is_no_taller_than_its_lines():
	# Seen live: the card ran from the bar to the top of the window. A
	# wrapping label measured at zero width wraps a character per line.
	_enter()
	_put(5, 103)
	_frame()
	panel._backpack[0].hovered.emit(5, true)
	await wait_process_frames(2)
	var card := panel._tooltip
	assert_lte(card.size.x, ItemTooltip.WIDTH + 2.0, "width %s, plus a 1px border each side" % card.size.x)
	assert_lt(card.size.y, 180.0, "height %s for %d lines" % [card.size.y, card._lines.get_child_count()])
	# And a shorter card after a taller one shrinks back.
	panel._backpack[0].hovered.emit(5, false)
	_put(6, 100)
	_frame()
	panel._backpack[1].hovered.emit(6, true)
	await wait_process_frames(2)
	assert_lt(panel._tooltip.size.y, card.size.y + 1.0, "shrank for fewer lines: %s" % panel._tooltip.size.y)


func test_the_card_stays_inside_the_viewport():
	_enter()
	_put(5, 102)
	_frame()
	var bounds := panel._tooltip.get_viewport_rect().size
	panel._backpack[0].hovered.emit(5, true)
	panel._tooltip.follow(bounds - Vector2.ONE)
	var card := panel._tooltip
	assert_true(card.position.x + card.size.x <= bounds.x, "flipped back off the right edge")
	assert_true(card.position.y + card.size.y <= bounds.y, "and held up off the bottom")
	assert_true(card.position.x >= 0.0 and card.position.y >= 0.0)


func test_the_card_goes_when_the_panel_does():
	_enter()
	_put(5, 102)
	_frame()
	panel._backpack[0].hovered.emit(5, true)
	panel.toggle()
	_frame()
	assert_false(panel._tooltip.visible)


# --- a slot -----------------------------------------------------------------

func test_a_drag_carries_the_slot_index_and_nothing_from_an_empty_cell():
	_enter()
	_put(5, 200)
	_frame()
	assert_eq(panel._backpack[0].drag_payload(), {"slot": 5})
	assert_null(panel._backpack[1].drag_payload())
	# The engine's own entry point refuses too; the filled branch needs a
	# real drag, since set_drag_preview errors outside one.
	assert_null(panel._backpack[1]._get_drag_data(Vector2.ZERO))


func test_a_slot_accepts_another_slots_drag_and_reports_the_drop():
	_enter()
	_frame()
	var slot: ItemSlot = panel._backpack[0]
	assert_true(slot._can_drop_data(Vector2.ZERO, {"slot": 6}))
	assert_false(slot._can_drop_data(Vector2.ZERO, "junk"))
	var seen := []
	slot.dropped.connect(func(from: int, to: int) -> void: seen.append([from, to]))
	slot._drop_data(Vector2.ZERO, {"slot": 6})
	slot._drop_data(Vector2.ZERO, {"slot": 5})
	assert_eq(seen, [[6, 5]], "a drop on itself is not a move")


func test_a_drag_that_lands_nowhere_is_a_throw():
	_enter()
	_frame()
	var slot: ItemSlot = panel._backpack[0]
	var thrown := []
	slot.thrown.connect(func(index: int) -> void: thrown.append(index))
	slot.notification(Control.NOTIFICATION_DRAG_END)
	assert_eq(thrown, [], "not a drag of ours")
	slot._dragging = true
	slot.notification(Control.NOTIFICATION_DRAG_END)
	assert_eq(thrown, [5])
	assert_false(slot._dragging)


func test_the_panel_itself_swallows_a_drop():
	assert_true(panel._root._can_drop_data(Vector2.ZERO, {"slot": 5}))
	assert_false(panel._root._can_drop_data(Vector2.ZERO, 5))
	panel._root._drop_data(Vector2.ZERO, {"slot": 5})
	assert_eq(transport.sent.size(), 0)


func test_a_double_click_activates_and_a_right_click_is_secondary():
	_enter()
	_frame()
	var slot: ItemSlot = panel._backpack[0]
	var seen := []
	slot.activated.connect(func(index: int) -> void: seen.append(["activated", index]))
	slot.secondary.connect(func(index: int, split: bool) -> void: seen.append(["secondary", index, split]))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	slot._gui_input(click)
	click.double_click = true
	slot._gui_input(click)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.shift_pressed = true
	slot._gui_input(right)
	right.pressed = false
	slot._gui_input(right)
	assert_eq(seen, [["activated", 5], ["secondary", 5, true]])


# --- the card ---------------------------------------------------------------

func test_the_card_says_what_the_item_is():
	var lines := ItemTooltip.describe({"name": "Wool Robe", "rarity": 3, "tier": 2,
		"description": "Itchy.", "damage": {"min": 0, "max": 0},
		"stats": {"def": 2, "spd": -1, "hp": 0}})
	assert_eq(lines.size(), 5)
	assert_eq(lines[0][0], "Wool Robe")
	assert_eq(lines[0][1], ItemTooltip.RARITY_COLOURS[3], "named in the rarity colour")
	assert_eq(lines[1][0], "Rare - Tier 2")
	assert_eq(lines[2][0], "Itchy.")
	assert_eq(lines[3], ["+2 DEF", ItemCard.GAIN])
	assert_eq(lines[4], ["-1 SPD", ItemCard.LOSS])


func test_the_card_names_damage_and_consumables():
	var lines := ItemTooltip.describe({"name": "Wand", "damage": {"min": 1, "max": 4}, "consumable": true})
	assert_eq(lines[1][0], "Mundane - Consumable", "no tier line without a tier")
	assert_eq(lines[2][0], "Damage: 1-4 (scales with STR)")


func test_the_card_copes_with_nothing_to_say():
	var lines := ItemTooltip.describe({"rarity": 99})
	assert_eq(lines.size(), 2)
	assert_eq(lines[0][0], "Unknown Item")
	assert_eq(lines[1][0], "Legendary", "an unknown rarity is clamped, not an error")
