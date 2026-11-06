extends GutTest

## The predicted multi-shot fan, and recognising the server's copies of it.

const DEFINITION := {"size": 8, "magnitude": 5.0, "range": 200.0, "damage": 10,
	"flags": [ProjectileKind.PLAYER_PROJECTILE], "angle": 0.0}


func _build(archetype := {}, definitions := [DEFINITION], base_angle := 0.0) -> Dictionary:
	return ShotPredictor.build(1, 7, definitions, base_angle, Vector2(50, 50), archetype, 1000)


func test_single_shot_by_default():
	var bullets := _build()
	assert_eq(bullets.size(), 1)
	var bullet: Projectile = bullets.values()[0]
	assert_eq(bullet["group_id"], 7)
	assert_eq(bullet["pos"], Vector2(50, 50))
	assert_true(bullet["predicted"])


func test_local_ids_are_negative_and_distinct():
	var bullets := _build({"projectileCount": 3})
	for id in bullets:
		assert_lt(id, 0, "predictions must not collide with server ids")
	assert_eq(bullets.size(), 3)


func test_archetype_projectile_count_fans_the_shot():
	assert_eq(_build({"projectileCount": 3}).size(), 3)


func test_fan_is_symmetric_about_the_aim():
	var bullets := _build({"projectileCount": 3, "spreadRad": 0.2})
	var angles: Array = []
	for bullet in bullets.values():
		angles.append(bullet["angle"])
	angles.sort()
	assert_almost_eq(angles[1], 0.0, 0.0001, "the centre shot stays on the aim line")
	assert_almost_eq(angles[0], -0.2, 0.0001)
	assert_almost_eq(angles[2], 0.2, 0.0001)


func test_even_counts_straddle_the_aim():
	var bullets := _build({"projectileCount": 2, "spreadRad": 0.2})
	var angles: Array = []
	for bullet in bullets.values():
		angles.append(bullet["angle"])
	angles.sort()
	assert_almost_eq(angles[0], -0.1, 0.0001)
	assert_almost_eq(angles[1], 0.1, 0.0001)


func test_default_spread_is_used_when_the_archetype_omits_one():
	var bullets := _build({"projectileCount": 2})
	var angles: Array = []
	for bullet in bullets.values():
		angles.append(bullet["angle"])
	angles.sort()
	assert_almost_eq(angles[1] - angles[0], ShotPredictor.DEFAULT_SPREAD_RAD, 0.0001)


func test_projectile_angle_offsets_stack_on_the_aim():
	var offset := {"size": 8, "magnitude": 5.0, "range": 100.0, "flags": [], "angle": PI / 2.0}
	var bullets := ShotPredictor.build(1, 7, [DEFINITION, offset], 0.25, Vector2.ZERO, {}, 0)
	var angles: Array = []
	for bullet in bullets.values():
		angles.append(bullet["angle"])
	angles.sort()
	assert_almost_eq(angles[0], 0.25, 0.0001)
	assert_almost_eq(angles[1], 0.25 + PI / 2.0, 0.0001)


func test_range_multiplier_and_piercing_come_from_the_archetype():
	var bullets := _build({"rangeMul": 1.5, "piercing": true})
	var bullet: Projectile = bullets.values()[0]
	assert_almost_eq(bullet["range"], 300.0, 0.0001)
	assert_true(ProjectileKind.has_flag(bullet, ProjectileKind.PASS_THROUGH_ENEMIES))


func test_non_positive_multipliers_fall_back_to_sane_values():
	var bullets := _build({"projectileCount": 0, "rangeMul": 0.0, "spreadRad": -1.0})
	assert_eq(bullets.size(), 1)
	assert_almost_eq(bullets.values()[0]["range"], 200.0, 0.0001)


func test_every_projectile_in_the_group_is_fanned():
	var bullets := ShotPredictor.build(1, 7, [DEFINITION, DEFINITION], 0.0, Vector2.ZERO,
		{"projectileCount": 3}, 0)
	assert_eq(bullets.size(), 6, "two definitions times a three-shot fan")


# --- claiming --------------------------------------------------------------
#
# claim's contract (ServerGameLogic owner-attributes player shots): a server
# bullet may adopt a prediction only when it is OUR shot (srcEntityId == owner),
# not an ally bolt, from the SAME projectile group, and nearest in angle.

const OWNER := 7


func _prediction(angle: float, position := Vector2.ZERO) -> Dictionary:
	return {-1: Projectile.predicted_shot(-1, 7, position, angle, DEFINITION, 0)}


## A wire bullet the server says WE fired, from the group the prediction is in.
func _own_wire(angle: float, overrides := {}) -> Dictionary:
	var wire := {"angle": angle, "pos": {"x": 0.0, "y": 0.0}, "srcEntityId": OWNER,
		"projectileId": 7, "flags": [ProjectileKind.PLAYER_PROJECTILE]}
	wire.merge(overrides, true)
	return wire


func test_claims_a_player_shot_by_angle_alone():
	var bullets := _prediction(0.5, Vector2(10, 10))
	var wire := _own_wire(0.52, {"pos": {"x": 900.0, "y": 900.0}})
	assert_true(ShotPredictor.claim(bullets, wire, 4242, OWNER))
	assert_eq(bullets[-1]["server_id"], 4242, "the prediction adopts the server id")


func test_rejects_a_different_angle():
	var bullets := _prediction(0.5)
	assert_false(ShotPredictor.claim(bullets, _own_wire(2.0), 1, OWNER))


func test_a_foreign_players_shot_is_not_claimed():
	var bullets := _prediction(0.5)
	var wire := _own_wire(0.5, {"srcEntityId": 999})
	assert_false(ShotPredictor.claim(bullets, wire, 1, OWNER),
		"another player's shot at the same angle is their bullet, not our prediction")


func test_a_different_group_is_not_claimed():
	var bullets := _prediction(0.5)
	var wire := _own_wire(0.5, {"projectileId": 8})
	assert_false(ShotPredictor.claim(bullets, wire, 1, OWNER),
		"an own shot from another weapon or ability must not steal this group's prediction")


func test_an_ally_bolt_is_never_claimed():
	var bullets := _prediction(0.5)
	var wire := _own_wire(0.5, {"flags": [ProjectileKind.PLAYER_PROJECTILE, ProjectileKind.ALLY_PROJECTILE]})
	assert_false(ShotPredictor.claim(bullets, wire, 1, OWNER),
		"a summon bolt is owner-attributed for credit but is the server's own bullet")


func test_a_prediction_is_claimed_only_once():
	var bullets := _prediction(0.5)
	var wire := _own_wire(0.5)
	assert_true(ShotPredictor.claim(bullets, wire, 1, OWNER))
	assert_false(ShotPredictor.claim(bullets, wire, 2, OWNER), "the second server bullet is its own")


func test_server_bullets_are_never_claimed_as_predictions():
	var live := Projectile.from_wire({"id": 99, "angle": 0.5, "pos": {}, "projectileId": 7,
		"srcEntityId": OWNER, "flags": []}, 0)
	var bullets := {99: live}
	assert_false(ShotPredictor.claim(bullets, _own_wire(0.5), 1, OWNER),
		"a live bullet is not a prediction, even at the same angle and group")


func test_angle_wrapping_does_not_defeat_matching():
	var bullets := _prediction(-PI + 0.01)
	assert_true(ShotPredictor.claim(bullets, _own_wire(PI - 0.01), 1, OWNER),
		"angles either side of PI are close")


func test_a_claimed_homing_shot_adopts_the_servers_target():
	# The prediction flies straight -- it can't know the server's fire-time lock.
	var bullets := _prediction(0.5)
	assert_eq((bullets[-1] as Projectile).target_entity_id, 0, "prediction starts with no target")
	var wire := _own_wire(0.52, {"targetEntityId": 4242, "frequency": 5.0,
		"flags": [ProjectileKind.PLAYER_PROJECTILE, ProjectileKind.HOMING]})
	assert_true(ShotPredictor.claim(bullets, wire, 1, OWNER))
	assert_eq((bullets[-1] as Projectile).target_entity_id, 4242, "homes at the enemy the server locked")
	assert_almost_eq((bullets[-1] as Projectile).frequency, 5.0, 0.0001, "adopts the server steer rate")
