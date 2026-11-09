extends GutTest

## The forge on screen, and the packets its buttons send.

var state: RealmState
var content: GameData
var client: GraveBoundClient
var transport: FakeTransport
var actions: ForgeActions
var panel: ForgePanel


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	actions = ForgeActions.new(state, client, content)
	panel = ForgePanel.new()
	panel.setup(state, content, actions)
	add_child_autofree(panel)


func _enter() -> void:
	state.local.id = 9
	state.local.class_id = 2


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
	var item := content.item_definition(item_id).duplicate(true)
	item.merge(extra, true)
	state.local.inventory.put(slot, item)


func _open() -> void:
	state.apply_packet("OpenForgePacket", {"playerId": 9})


func _bench(target := 5, crystal := 6, essence := 7) -> void:
	_put(target, 102)
	_put(crystal, 300)
	_put(essence, 310, {"stackCount": 50})
	state.forge.assign("target", target)
	state.forge.assign("crystal", crystal)
	state.forge.assign("essence", essence)


func _sent() -> Array:
	return transport.sent_packets()


# --- the actions -------------------------------------------------------------

func test_placing_checks_the_zone():
	_enter()
	_open()
	_put(5, 102)
	_put(6, 300)
	_put(7, 310)
	_put(8, 200)
	assert_eq(actions.place("target", 5), "")
	assert_eq(actions.place("target", 6), "Only equipment can be enchanted.")
	assert_eq(actions.place("crystal", 6), "")
	assert_eq(actions.place("crystal", 7), "That isn't a crystal or gem.")
	assert_eq(actions.place("essence", 7), "")
	assert_eq(actions.place("essence", 8), "That isn't essence.")
	assert_eq(actions.place("target", 30), "Drag an item from the bag.", "an empty slot")
	assert_eq(actions.place("anvil", 5), "Drag an item from the bag.", "no such zone")
	assert_eq(state.forge.index_of("target"), 5)
	assert_eq(state.forge.index_of("crystal"), 6)
	assert_eq(state.forge.index_of("essence"), 7)


func test_nothing_is_placed_on_a_closed_forge():
	_enter()
	_put(5, 102)
	assert_eq(actions.place("target", 5), "Drag an item from the bag.")
	assert_eq(state.forge.index_of("target"), ForgeBench.NONE)


func test_enchant_sends_the_bench_and_the_pixel():
	_in_game()
	_open()
	_bench()
	assert_eq(actions.problem(), "")
	assert_true(actions.enchant())
	var packets := _sent()
	assert_eq(packets.size(), 1)
	assert_eq(packets[0]["name"], "ForgeEnchantPacket")
	var data: Dictionary = packets[0]["data"]
	assert_eq(int(data["targetItemSlot"]), 5)
	assert_eq(int(data["crystalItemId"]), 300)
	assert_eq(int(data["crystalSlotIndex"]), 6)
	assert_eq(int(data["essenceSlotIndex"]), 7)
	var expected := ForgePixel.pick(content.item_texture(102), state.local.inventory.item_at(5))
	assert_eq(int(data["pixelX"]), expected.x)
	assert_eq(int(data["pixelY"]), expected.y)


func test_enchant_is_refused_by_the_rules_before_the_wire():
	_in_game()
	_open()
	_bench()
	_put(7, 310, {"stackCount": 3})
	assert_false(actions.enchant())
	assert_eq(actions.problem(), "Need 10 essence (have 3).")
	state.forge.close()
	_put(7, 310, {"stackCount": 50})
	assert_false(actions.enchant(), "closed")
	assert_eq(_sent().size(), 0)


func test_disenchant_needs_something_on_the_item():
	_in_game()
	_open()
	_put(5, 102)
	state.forge.assign("target", 5)
	assert_false(actions.disenchant())
	_put(5, 102, {"enchantments": [{"statId": 0, "deltaValue": 1, "pixelX": 0, "pixelY": 0}]})
	assert_true(actions.disenchant())
	var packets := _sent()
	assert_eq(packets[0]["name"], "ForgeDisenchantPacket")
	assert_eq(int(packets[0]["data"]["targetItemSlot"]), 5)


func test_nothing_is_sent_outside_a_realm():
	_enter()
	_open()
	_bench()
	assert_false(actions.enchant())
	assert_eq(_sent().size(), 0)


# --- the panel ---------------------------------------------------------------

func test_the_forge_shows_when_the_server_opens_it():
	_enter()
	panel._process(0.0)
	assert_false(panel.visible)
	_open()
	panel._process(0.0)
	assert_true(panel.visible)
	assert_eq(panel._status.text, "Pick an item.", "the web client's first issue, on an empty bench")
	assert_true(panel._enchant.disabled)
	assert_true(panel._disenchant.disabled)
	state.forge.close()
	panel._process(0.0)
	assert_false(panel.visible)


func test_a_full_bench_reads_green_and_arms_enchant():
	_enter()
	_open()
	_bench()
	panel._process(0.0)
	assert_not_null(panel._zones["target"]._icon.texture)
	assert_not_null(panel._zones["crystal"]._icon.texture)
	assert_eq(panel._zones["essence"]._count.text, "x50")
	assert_eq(panel._status.text, "Broken Wand - Common   Crystal slots: 0/1")
	assert_eq(panel._cost.text, "Cost: 1 Vit Crystal + 10 Weapon Essence -> +1 VIT")
	assert_false(panel._enchant.disabled)
	assert_true(panel._disenchant.disabled, "nothing on it yet")


func test_a_problem_reads_red_after_the_summary():
	_enter()
	_open()
	_bench()
	_put(7, 311, {"stackCount": 50})
	panel._process(0.0)
	assert_eq(panel._status.text, "Broken Wand - Common   Crystal slots: 0/1   Essence type must be Weapon.")
	assert_true(panel._enchant.disabled)


func test_a_drop_on_a_zone_takes_or_refuses_the_item():
	_enter()
	_open()
	_put(5, 102)
	_put(8, 200)
	panel._process(0.0)
	panel._zones["target"].dropped.emit(5, ForgePanel.ZONE_BASE)
	panel._process(0.0)
	assert_eq(state.forge.index_of("target"), 5)
	assert_not_null(panel._zones["target"]._icon.texture)
	panel._zones["crystal"].dropped.emit(8, ForgePanel.ZONE_BASE + 1)
	panel._process(0.0)
	assert_eq(state.forge.index_of("crystal"), ForgeBench.NONE)
	assert_string_contains(panel._status.text, "That isn't a crystal or gem.")
	# A right-click clears the zone and the message with it.
	panel._zones["target"].secondary.emit(ForgePanel.ZONE_BASE, false)
	panel._process(0.0)
	assert_eq(state.forge.index_of("target"), ForgeBench.NONE)
	assert_eq(panel._status.text, "Pick an item.")


func test_the_buttons_send():
	# An Epic robe with one of its four crystals set: room to enchant, and
	# something to disenchant.
	_in_game()
	_open()
	_bench()
	_put(5, 103, {"enchantments": [{"statId": 0, "deltaValue": 1, "pixelX": 0, "pixelY": 0}]})
	_put(7, 311, {"stackCount": 50})
	panel._process(0.0)
	panel._enchant.pressed.emit()
	panel._disenchant.pressed.emit()
	var names: Array = _sent().map(func(p: Dictionary) -> String: return p["name"])
	assert_eq(names, ["ForgeEnchantPacket", "ForgeDisenchantPacket"])


func test_the_bench_forgets_a_consumed_crystal_on_the_next_look():
	_enter()
	_open()
	_bench()
	panel._process(0.0)
	state.local.inventory.put(6, {})
	panel._process(0.0)
	assert_eq(state.forge.index_of("crystal"), ForgeBench.NONE)
	assert_null(panel._zones["crystal"]._icon.texture)
	assert_string_contains(panel._status.text, "Pick a Crystal or Gem.")


func test_the_card_opens_over_a_zone():
	_enter()
	_open()
	_bench()
	panel._process(0.0)
	panel._zones["target"].hovered.emit(ForgePanel.ZONE_BASE, true)
	assert_true(panel._tooltip.visible)
	panel._process(0.0)
	assert_true(panel._tooltip.visible, "and it follows the mouse while open")
	assert_string_contains(panel._tooltip._lines.get_child(0).text, "Broken Wand")
	panel._zones["target"].hovered.emit(ForgePanel.ZONE_BASE, false)
	assert_false(panel._tooltip.visible)
	assert_eq(ForgePanel.zone_of(ForgePanel.ZONE_BASE + 2), "essence")
	assert_eq(ForgePanel.zone_of(5), "")


func test_without_actions_a_gesture_is_nothing():
	var mute := ForgePanel.new()
	mute.setup(state, content, null)
	add_child_autofree(mute)
	_enter()
	_open()
	mute._process(0.0)
	mute._zones["target"].dropped.emit(5, ForgePanel.ZONE_BASE)
	mute._enchant.pressed.emit()
	mute._disenchant.pressed.emit()
	assert_true(mute.visible)
	await wait_process_frames(1)
	assert_false(mute.captures_mouse(), "centred, so not under a mouse at the origin")
