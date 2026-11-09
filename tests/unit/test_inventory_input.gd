extends GutTest

## The keys that reach into the bag.

const ACTIONS := ["toggle_inventory", "pick_up", "drink_hp", "drink_mp",
	"quick_slot_1", "quick_slot_2", "quick_slot_8"]

var state: RealmState
var content: GameData
var client: GraveBoundClient
var transport: FakeTransport
var actions: InventoryActions
var panel: InventoryPanel
var input: InventoryInput


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)
	transport = FakeTransport.new()
	client = GraveBoundClient.new()
	client.connection.transport = transport
	add_child_autofree(client)
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	transport.deliver(WireHelper.login_response(9, 2, Vector2.ZERO))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	transport.clear_sent()
	actions = InventoryActions.new(state, client, content)
	panel = InventoryPanel.new()
	panel.setup(state, content, actions)
	add_child_autofree(panel)
	input = InventoryInput.new(client, actions, panel)


func after_each():
	for action in ACTIONS:
		Input.action_release(action)


func test_a_key_typed_into_the_chat_line_is_not_the_bags():
	input.keyboard_captured = func() -> bool: return true
	Input.action_press("toggle_inventory")
	input.tick(0.0)
	assert_true(panel.shown, "Tab in the chat line is a letter: the bag stays up")
	Input.action_release("toggle_inventory")
	input.keyboard_captured = func() -> bool: return false
	Input.action_press("toggle_inventory")
	input.tick(0.0)
	assert_false(panel.shown, "and counts again once the line closes")


func _put(slot: int, item_id: int, extra := {}) -> void:
	var item := content.item_definition(item_id).duplicate()
	item.merge(extra, true)
	state.local.inventory.put(slot, item)


func _from_slots() -> Array:
	var out: Array = []
	for packet in transport.sent_packets():
		out.append(int(packet["data"].get("fromSlotIndex", -99)))
	return out


func test_the_keys_are_bound():
	for action in ACTIONS:
		assert_true(InputMap.has_action(action), action)


func test_f_picks_up_the_first_thing_in_the_bag_once_per_press():
	state.entities.apply_load({"containers": [{"lootContainerId": 3, "uid": "", "isChest": false,
		"tier": 0, "items": [{"itemId": 100}], "pos": {"x": 0.0, "y": 0.0}, "spawnedTime": 0,
		"contentsChanged": false, "soulboundPlayerId": 0}]})
	Input.action_press("pick_up")
	input.tick(0.0)
	input.tick(0.0)
	assert_eq(_from_slots(), [Inventory.GROUND_LOOT_START], "held is not pressed again")
	Input.action_release("pick_up")
	input.tick(0.0)
	Input.action_press("pick_up")
	input.tick(0.0)
	assert_eq(_from_slots().size(), 2, "a second press is")


func test_z_and_x_drink_from_the_pools():
	state.local.inventory.hp_potions = 1
	Input.action_press("drink_hp")
	Input.action_press("drink_mp")
	input.tick(0.0)
	assert_eq(_from_slots(), [Inventory.HP_POTION_SLOT], "the MP pool is empty")


func test_shift_digits_use_the_first_eight_backpack_slots():
	_put(5, 200)
	_put(12, 102)
	Input.action_press("quick_slot_1")
	Input.action_press("quick_slot_8")
	input.tick(0.0)
	assert_eq(_from_slots(), [5, 12])
	var packets := transport.sent_packets()
	assert_true(bool(packets[0]["data"]["consume"]), "the potion is drunk")
	assert_eq(int(packets[1]["data"]["targetSlotIndex"]), 0, "the wand is equipped")


func test_tab_toggles_the_panel_once_per_press():
	Input.action_press("toggle_inventory")
	input.tick(0.0)
	assert_false(panel.shown)
	input.tick(0.0)
	assert_false(panel.shown, "held is not pressed again")


func test_tab_outside_a_realm_is_the_login_forms_not_ours():
	# Moving from the email field to the password field once hid the bag
	# before the player had ever seen it.
	client.stop_playing()
	Input.action_press("toggle_inventory")
	input.tick(0.0)
	assert_true(panel.shown)
	# Nor is the press remembered as already-seen for when the realm arrives.
	client.state = GraveBoundClient.State.IN_GAME
	input.tick(0.0)
	assert_false(panel.shown, "a Tab still held on arrival counts then")


func test_the_bag_keys_do_nothing_outside_a_realm():
	_put(5, 200)
	state.local.inventory.hp_potions = 1
	client.stop_playing()
	Input.action_press("pick_up")
	Input.action_press("drink_hp")
	Input.action_press("quick_slot_1")
	input.tick(0.0)
	assert_eq(transport.sent_packets().size(), 0)
