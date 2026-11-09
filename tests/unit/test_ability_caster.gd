extends GutTest

## Casting: the gates, the packet, and the projectiles drawn ahead of it.

var state: RealmState
var content: GameData
var client: GraveBoundClient
var transport: FakeTransport
var caster: AbilityCaster
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
	client.connect_to_server("h", 1)
	transport.become_connected()
	client._process(0.0)
	client.login("a", "b", "c")
	# A wizard: Fire Breath (a projectile group, reach 352), Frost Spike,
	# Supernova (a cursor-spawned group with a homing shot in it).
	transport.deliver(WireHelper.login_response(9, 2, Vector2(100, 100)))
	client._process(0.0)
	state.local.enter_realm(client.login_response)
	state.local.mana = 500
	transport.clear_sent()
	aim = Node2D.new()
	add_child_autofree(aim)
	caster = AbilityCaster.new(state, client, content, aim)


func _casts() -> Array:
	var out: Array = []
	for packet in transport.sent_packets():
		if packet["name"] == "UseAbilityPacket":
			out.append(packet["data"])
	return out


func _centre() -> Vector2:
	return state.local.centre()


func test_a_cast_sends_the_point_and_the_slot():
	var target := _centre() + Vector2(86, 0)
	assert_true(caster.cast(0, target))
	var casts := _casts()
	assert_eq(casts.size(), 1)
	assert_almost_eq(float(casts[0]["posX"]), target.x, 0.001)
	assert_almost_eq(float(casts[0]["posY"]), target.y, 0.001)
	assert_eq(int(casts[0]["abilityIndex"]), 0)


func test_the_point_is_pulled_in_to_the_abilitys_reach():
	# The server clamps the same way before it reads the point, so the
	# projectile predicted from the clamped point is the one that arrives.
	caster.cast(0, _centre() + Vector2(1000, 0))
	assert_almost_eq(float(_casts()[0]["posX"]), _centre().x + 352.0, 0.001)
	assert_almost_eq(float(_casts()[0]["posY"]), _centre().y, 0.001)


func test_a_self_cast_lands_on_the_caster_and_faces_front():
	state.local.class_id = 0   # a barbarian, whose third slot is Rage
	assert_true(caster.cast(2, _centre() + Vector2(300, 300)))
	assert_almost_eq(float(_casts()[0]["posX"]), _centre().x, 0.001)
	assert_almost_eq(float(_casts()[0]["posY"]), _centre().y, 0.001)
	assert_eq(state.local.attack.facing, "down")
	assert_eq(state.abilities.rings.size(), 0, "no ring for no reach")


func test_the_pose_aims_where_the_cast_went():
	caster.cast(0, _centre() + Vector2(-100, 10))
	assert_eq(state.local.attack.facing, "side")
	assert_true(state.local.facing_left)
	assert_eq(state.abilities.rings.size(), 1)
	assert_eq(state.abilities.rings[0]["radius"], 352.0)


func test_mana_is_taken_at_once_and_gates_the_next_cast():
	state.local.mana = 100
	assert_true(caster.cast(0, _centre() + Vector2(50, 0)))
	assert_eq(state.local.mana, 40)
	now += AbilityCaster.GLOBAL_COOLDOWN_MS
	assert_false(caster.cast(1, _centre() + Vector2(50, 0)), "Frost Spike costs 70")
	assert_eq(_casts().size(), 1)


func test_a_second_passes_between_any_two_casts():
	assert_true(caster.cast(0, _centre() + Vector2(50, 0)))
	assert_false(caster.cast(1, _centre() + Vector2(50, 0)))
	now += AbilityCaster.GLOBAL_COOLDOWN_MS - 1
	assert_false(caster.cast(1, _centre() + Vector2(50, 0)))
	now += 1
	assert_true(caster.cast(1, _centre() + Vector2(50, 0)))
	assert_eq(AbilityCaster.GLOBAL_COOLDOWN_MS, 1000, "the web client's ABILITY_COOLDOWN_MS")


func test_a_slot_waits_out_its_own_cooldown():
	assert_true(caster.cast(0, _centre() + Vector2(50, 0)))
	assert_eq(state.abilities.cooldown_total[0], 2500)
	now += 1000
	assert_false(caster.cast(0, _centre() + Vector2(50, 0)), "the global second has passed, the slot has not")
	now += 1500
	assert_true(caster.cast(0, _centre() + Vector2(50, 0)))


func test_invested_points_shorten_the_cooldown_as_the_server_does():
	state.abilities.invested[0] = 2
	caster.cast(0, _centre() + Vector2(50, 0))
	assert_eq(state.abilities.cooldown_total[0], 2500 - 2 * 200)


func test_a_projectile_group_is_predicted_from_the_caster():
	var target := _centre() + Vector2(100, 0)
	caster.cast(0, target)
	assert_eq(state.projectiles.bullets.size(), 1)
	var id: int = state.projectiles.bullets.keys()[0]
	assert_lt(id, 0, "a local id, out of the server's space")
	var bullet: Projectile = state.projectiles.bullets[id]
	assert_eq(bullet["group_id"], 12)
	assert_eq(bullet["pos"], state.local.position, "from the caster")
	assert_almost_eq(bullet["angle"], ProjectileAngle.aim(_centre(), target), 0.0001, "aimed at the point")
	# The content says [12] as a float; a flag test on the bullet must still
	# find it, or a predicted wall draws as a straight shot.
	assert_true(ProjectileKind.has_flag(bullet, 12), "content flags survive as ints")


func test_cursor_spawned_shots_and_homing_ones():
	# Supernova's group: one shot that spawns at the point on its own preset
	# heading, and one homing shot that is left to the server.
	var target := _centre() + Vector2(100, 0)
	caster.cast(2, target)
	assert_eq(state.projectiles.bullets.size(), 1)
	var bullet: Projectile = state.projectiles.bullets.values()[0]
	assert_eq(bullet["pos"], target - Vector2.ONE * GameConstants.PLAYER_SIZE * 0.5)
	assert_almost_eq(bullet["angle"], PI / 2.0, 0.0001, "the preset heading, not the aim")
	assert_false(ProjectileKind.HOMING in bullet["flags"])


func test_predicted_ids_never_collide_with_a_weapon_shot():
	state.local.inventory.put(0, {"itemId": 100, "damage": {"projectileGroupId": 10}})
	state.projectiles.fire_basic_attack(_centre() + Vector2(50, 0))
	caster.cast(0, _centre() + Vector2(50, 0))
	assert_eq(state.projectiles.bullets.size(), 2)


func test_an_ability_that_fires_nothing_predicts_nothing():
	caster.cast(1, _centre() + Vector2(50, 0))
	assert_eq(_casts().size(), 1)
	assert_eq(state.projectiles.bullets.size(), 0)
	# A group with no projectiles in it, which the content does ship.
	content.library.abilities[13007]["effects"] = [{"type": "PROJECTILE_GROUP", "projectileGroupId": 14}]
	now += 4000   # Frost Spike's own cooldown, not just the global second
	assert_true(caster.cast(1, _centre() + Vector2(50, 0)))
	assert_eq(state.projectiles.bullets.size(), 0)


func test_nothing_casts_without_a_binding_content_or_a_realm():
	state.local.class_id = 0
	assert_false(caster.cast(1, _centre()), "the barbarian's second slot is empty")
	state.local.class_id = 2
	assert_false(caster.cast(3, _centre()), "no fourth slot")
	assert_false(caster.cast(-1, _centre()))
	var blind := AbilityCaster.new(state, client, null, aim)
	assert_false(blind.cast(0, _centre()))
	client.stop_playing()
	assert_false(caster.cast(0, _centre()))
	assert_eq(_casts().size(), 0)
	assert_eq(state.local.mana, 500, "and nothing was paid")
