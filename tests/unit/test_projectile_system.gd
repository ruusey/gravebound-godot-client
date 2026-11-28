extends GutTest

## Bullet ownership: adopting server bullets, simulating them, and firing.

var system: ProjectileSystem
var player: LocalPlayer
var content: GameData
var now := 1000


func before_each():
	now = 1000
	content = GameData.new()
	await content.load_from(FileContentSource.new(_fixture_root()))
	player = LocalPlayer.new()
	player.id = 42
	player.position = Vector2(100, 100)
	player.inventory.put(0, {"itemId": 100, "damage": {"projectileGroupId": 10}})
	system = ProjectileSystem.new(player, content, func() -> int: return now)


func _fixture_root() -> String:
	return ProjectSettings.globalize_path("res://tests/fixtures/datadir")


func _wire_bullet(id: int, overrides := {}) -> Dictionary:
	var wire := {
		"id": id, "projectileId": 10, "size": 8, "pos": {"x": 0.0, "y": 0.0},
		"dX": 0.0, "dY": 0.0, "angle": 0.0, "magnitude": 5.0, "range": 500.0,
		"damage": 3, "flags": [], "invert": false, "timeStep": 0,
		"amplitude": 0, "frequency": 0, "createdTime": 0,
		"orbitCenterX": 0.0, "orbitCenterY": 0.0, "orbitRadius": 0.0, "orbitPhase": 0.0,
	}
	wire.merge(overrides, true)
	return wire


# --- inbound ---------------------------------------------------------------

func test_adopts_server_bullets():
	system.apply_load({"bullets": [_wire_bullet(1), _wire_bullet(2)]})
	assert_eq(system.bullets.size(), 2)


func test_an_already_known_bullet_is_not_re_added():
	system.apply_load({"bullets": [_wire_bullet(1)]})
	system.advance(RealmState.TICK_DELTA)
	var travelled: Vector2 = system.bullets[1]["pos"]
	system.apply_load({"bullets": [_wire_bullet(1)]})
	assert_eq(system.bullets[1]["pos"], travelled, "the in-flight bullet is not reset")


func test_new_bullets_are_fast_forwarded_by_latency():
	system.latency_ms = 200.0
	system.apply_load({"bullets": [_wire_bullet(1, {"angle": PI / 2.0})]})
	assert_gt(system.bullets[1]["pos"].x, 0.0, "advanced toward where the server has it")


func test_a_melee_weapon_swings_but_predicts_no_projectile():
	# The web client's _isMelee: the swing is an invisible server-side AoE,
	# so nothing travelling is predicted -- the placeholder that was drawn
	# instead was the bug. The shot still goes to the server, and we swing.
	player.inventory.put(0, {"itemId": 107, "damage": {"projectileGroupId": 10}})
	var shot := system.fire_basic_attack(Vector2(200, 100))
	assert_false(shot.is_empty(), "the swing is still sent")
	assert_eq(shot["projectileGroupId"], 10)
	assert_eq(system.bullets.size(), 0, "no placeholder projectile")
	assert_true(player.attack.is_active(), "the swing animation plays")
	player.inventory.put(0, {"itemId": 100, "damage": {"projectileGroupId": 10}})
	system.fire_basic_attack(Vector2(200, 100))
	assert_eq(system.bullets.size(), 1, "a bow still predicts its arrow")


func test_unload_removes_bullets():
	system.apply_load({"bullets": [_wire_bullet(1), _wire_bullet(2)]})
	system.apply_unload({"bullets": [1]})
	assert_false(system.bullets.has(1))
	assert_true(system.bullets.has(2))


func test_unload_also_removes_the_prediction_that_claimed_that_id():
	system.fire_basic_attack(Vector2(200, 100))
	var local_id: int = system.bullets.keys()[0]
	system.apply_load({"bullets": [_wire_bullet(555, {
		"angle": system.bullets[local_id]["angle"], "srcEntityId": player.id,
		"flags": [ProjectileKind.PLAYER_PROJECTILE]})]})
	assert_eq(system.bullets.size(), 1, "the server copy was recognised as ours")
	system.apply_unload({"bullets": [555]})
	assert_eq(system.bullets.size(), 0, "unloading the server id clears the prediction")


# --- simulation ------------------------------------------------------------

func test_advance_moves_bullets():
	system.apply_load({"bullets": [_wire_bullet(1, {"angle": 0.0, "magnitude": 4.0})]})
	system.advance(RealmState.TICK_DELTA)
	assert_almost_eq(system.bullets[1]["pos"].y, 4.0, 0.001)


func test_advance_drops_our_own_shots_at_their_range():
	system.apply_load({"bullets": [_wire_bullet(1, {"range": 5.0, "magnitude": 10.0, "srcEntityId": player.id})]})
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets.size(), 0)


func test_an_enemy_shot_past_its_range_waits_for_the_server():
	# Server-authoritative: a client-side range guess once hid a bullet the
	# server kept flying (the invisible projectile that still killed).
	system.apply_load({"bullets": [_wire_bullet(1, {"range": 5.0, "magnitude": 10.0})]})
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets.size(), 1)
	system.apply_unload({"bullets": [1]})
	assert_eq(system.bullets.size(), 0)


# --- terrain (the server's proccessTerrainHit) -------------------------------

## A system whose collision layer holds `tile_id` under a bullet loaded at the origin.
func _over_tile(tile_id: int) -> void:
	var tiles := TileMapState.new(content)
	tiles.layers[GameConstants.COLLISION_LAYER] = {Vector2i(0, 0): tile_id}
	system = ProjectileSystem.new(player, content, func() -> int: return now, null, tiles)


func test_a_solid_prop_stops_a_plain_shot():
	_over_tile(9)   # Anvil: collision, not a wall
	system.apply_load({"bullets": [_wire_bullet(1)]})
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets.size(), 0)


func test_a_pass_through_terrain_shot_crosses_a_solid_prop():
	_over_tile(9)
	system.apply_load({"bullets": [_wire_bullet(1, {"flags": [ProjectileKind.PASS_THROUGH_TERRAIN]})]})
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets.size(), 1)


func test_a_wall_stops_even_a_pass_through_terrain_shot():
	_over_tile(2)   # Wall
	system.apply_load({"bullets": [
		_wire_bullet(1, {"flags": [ProjectileKind.PASS_THROUGH_TERRAIN]}),
		_wire_bullet(2, {"flags": [ProjectileKind.PASS_THROUGH_TERRAIN], "srcEntityId": player.id})]})
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets.size(), 0, "an enemy's and our own")


func test_advance_on_an_empty_table_is_cheap():
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets.size(), 0)


func test_clear_empties_the_table():
	system.apply_load({"bullets": [_wire_bullet(1)]})
	system.clear()
	assert_eq(system.bullets.size(), 0)


# --- firing ----------------------------------------------------------------

func test_weapon_projectile_group_comes_from_the_equipped_item():
	assert_eq(system.weapon_projectile_group(), 10)


func test_weapon_group_falls_back_to_content():
	player.inventory.put(0, {"itemId": 101})
	assert_eq(system.weapon_projectile_group(), 11, "resolved from game-items.json")


func test_no_weapon_means_no_group():
	player.inventory.clear()
	assert_eq(system.weapon_projectile_group(), 0)


func test_firing_returns_the_shoot_packet():
	var shot := system.fire_basic_attack(Vector2(200, 100))
	assert_false(shot.has("entityId"), "v0.9.0 takes the shooter from the connection")
	assert_eq(shot["projectileGroupId"], 10)
	assert_almost_eq(shot["destX"], 200.0, 0.001)
	assert_almost_eq(shot["srcX"], player.centre().x, 0.001, "from the body centre, as the server fires")
	assert_eq(shot["projectileId"], 1, "shot numbers increase per shot")


func test_firing_spawns_predicted_bullets_immediately():
	system.fire_basic_attack(Vector2(200, 100))
	assert_eq(system.bullets.size(), 1)
	assert_true(system.bullets.values()[0]["predicted"])


func test_firing_aims_at_the_cursor():
	system.fire_basic_attack(Vector2(1000, 100))
	var direction := ProjectileAngle.direction(system.bullets.values()[0]["angle"])
	assert_almost_eq(direction.x, 1.0, 0.001, "aimed to the right")


func test_firing_turns_the_player():
	system.fire_basic_attack(Vector2(1000, 100))
	assert_eq(player.facing, "side")
	system.fire_basic_attack(Vector2(100, 1000))
	assert_eq(player.facing, "front")


func test_archetype_fan_applies_to_predicted_shots():
	player.inventory.put(0, {"itemId": 101, "damage": {"projectileGroupId": 11}})
	system.fire_basic_attack(Vector2(200, 100))
	# Group 11 has two projectiles, archetype 2 fires three each.
	assert_eq(system.bullets.size(), 6)


func test_firing_without_a_weapon_does_nothing():
	player.inventory.clear()
	assert_eq(system.fire_basic_attack(Vector2(200, 100)), {})
	assert_eq(system.bullets.size(), 0)


func test_firing_with_an_unknown_group_does_nothing():
	player.inventory.put(0, {"itemId": 102, "damage": {"projectileGroupId": 999}})
	assert_eq(system.fire_basic_attack(Vector2(200, 100)), {})


func test_firing_with_an_empty_group_does_nothing():
	player.inventory.put(0, {"itemId": 103, "damage": {"projectileGroupId": 14}})
	assert_eq(system.fire_basic_attack(Vector2(200, 100)), {})


func test_firing_before_login_does_nothing():
	player.id = 0
	assert_eq(system.fire_basic_attack(Vector2(200, 100)), {})


func test_firing_without_content_does_nothing():
	var bare := ProjectileSystem.new(player, null)
	assert_eq(bare.fire_basic_attack(Vector2(200, 100)), {})


# --- remote swings ----------------------------------------------------------

func _with_entities() -> EntityRegistry:
	var entities := EntityRegistry.new(func() -> int: return now)
	system = ProjectileSystem.new(player, content, func() -> int: return now, entities)
	return entities


func test_a_remote_bullet_starts_its_shooters_swing():
	# Nothing on the wire announces an attack; the shot is the only signal.
	var entities := _with_entities()
	entities.apply_load({"players": [WireHelper.player(7, "them", Vector2.ZERO)]})
	system.apply_load({"bullets": [_wire_bullet(1, {"srcEntityId": 7, "angle": PI / 2.0})]})

	var pose: AttackPose = entities.players[7]["attack"]
	assert_true(pose.is_active())
	assert_eq(pose.facing, "side", "angle PI/2 is (1, 0) -- straight right")


func test_the_swing_follows_the_bullet_not_the_feet():
	var entities := _with_entities()
	entities.apply_load({"players": [WireHelper.player(7, "them", Vector2.ZERO)]})
	system.apply_load({"bullets": [_wire_bullet(1, {"srcEntityId": 7, "angle": 0.0})]})
	assert_eq(entities.players[7]["attack"].facing, "down",
		"velocity is (sin a, cos a), so angle 0 is (0, 1) -- down the screen")

	system.apply_load({"bullets": [_wire_bullet(2, {"srcEntityId": 7, "angle": PI})]})
	assert_eq(entities.players[7]["attack"].facing, "up", "and PI is (0, -1)")


func test_our_own_bullets_do_not_restart_our_swing():
	# The local pose starts on input. The server echoes the same shots back,
	# and adopting one would reset the swing to frame 0 partway through.
	var entities := _with_entities()
	player.attack.begin(Vector2.RIGHT)
	player.attack.tick(AttackPose.FRAME_SECONDS * 2.5)
	system.apply_load({"bullets": [_wire_bullet(1, {"srcEntityId": player.id})]})
	assert_eq(player.attack.frame, 2, "untouched")


func test_a_bullet_from_nobody_is_ignored():
	var entities := _with_entities()
	system.apply_load({"bullets": [_wire_bullet(1, {"srcEntityId": 999})]})
	assert_false(entities.players.has(999))
