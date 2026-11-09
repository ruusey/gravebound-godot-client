extends GutTest

## The v0.9.0 motion types: speed curves, line-segment spin, homing and
## anchoring. Every expected value here is computed from
## com.gravebound.game.entity.Bullet, because a disagreement with the server is
## a bullet drawn where it is not.

var entities: EntityRegistry
var player: LocalPlayer
var now := 1000


func before_each():
	now = 1000
	entities = EntityRegistry.new(func() -> int: return now)
	player = LocalPlayer.new()
	player.id = 42
	player.position = Vector2(100, 100)


func _bullet(overrides := {}) -> Projectile:
	var bullet := {
		"pos": Vector2.ZERO, "size": 8, "angle": 0.0, "magnitude": 4.0,
		"range": 1000.0, "traveled": 0.0, "flags": [], "invert": false,
		"time_step": 0.0, "amplitude": 0.0, "frequency": 0.0,
		"orbit_centre": Vector2.ZERO, "orbit_radius": 0.0, "orbit_phase": 0.0,
		"lifetime_ticks": 64, "src_entity_id": 0, "target_entity_id": 0,
		"anchor_offset": Vector2.ZERO, "created_ms": now,
	}
	bullet.merge(overrides, true)
	return Projectile.from_fields(bullet)


# --- speed curves ----------------------------------------------------------

func test_a_bullet_without_the_flags_is_unscaled():
	assert_eq(ProjectileSpeed.multiplier(_bullet(), now), 1.0)


func test_decay_starts_at_full_speed_and_ends_stopped():
	var bullet := _bullet({"flags": [ProjectileKind.SPEED_DECAY]})
	assert_almost_eq(ProjectileSpeed.multiplier(bullet, now), 1.0, 0.0001, "p=0")
	# lifetime_ticks 64 at 64Hz is exactly one second.
	assert_almost_eq(ProjectileSpeed.multiplier(bullet, now + 1000), 0.0, 0.0001, "p=1")


func test_ramp_starts_stopped_and_ends_at_full_speed():
	var bullet := _bullet({"flags": [ProjectileKind.SPEED_RAMP]})
	assert_almost_eq(ProjectileSpeed.multiplier(bullet, now), 0.0, 0.0001, "p=0")
	assert_almost_eq(ProjectileSpeed.multiplier(bullet, now + 1000), 1.0, 0.0001, "p=1")


func test_the_curve_matches_the_server_formula_midway():
	# k defaults to 4, so at p=0.5 decay is (e^-2 - e^-4)/(1 - e^-4).
	var decay := _bullet({"flags": [ProjectileKind.SPEED_DECAY]})
	assert_almost_eq(ProjectileSpeed.multiplier(decay, now + 500), 0.119203, 0.00001)
	var ramp := _bullet({"flags": [ProjectileKind.SPEED_RAMP]})
	assert_almost_eq(ProjectileSpeed.multiplier(ramp, now + 500), 0.119203, 0.00001)


func test_frequency_sharpens_the_curve():
	var sharp := _bullet({"flags": [ProjectileKind.SPEED_DECAY], "frequency": 8.0})
	var default_k := _bullet({"flags": [ProjectileKind.SPEED_DECAY]})
	assert_lt(ProjectileSpeed.multiplier(sharp, now + 500),
		ProjectileSpeed.multiplier(default_k, now + 500), "a larger k decays faster")


func test_progress_is_clamped_past_the_lifetime():
	var bullet := _bullet({"flags": [ProjectileKind.SPEED_RAMP]})
	assert_almost_eq(ProjectileSpeed.multiplier(bullet, now + 10_000), 1.0, 0.0001)


func test_a_missing_lifetime_falls_back_to_the_server_default():
	# 192 ticks / 64Hz == 3s, so 1.5s in is the halfway point.
	var bullet := _bullet({"flags": [ProjectileKind.SPEED_DECAY], "lifetime_ticks": 0})
	assert_almost_eq(ProjectileSpeed.multiplier(bullet, now + 1500), 0.119203, 0.00001)


func test_a_speed_curved_bullet_moves_slower_than_a_plain_one():
	var curved := _bullet({"flags": [ProjectileKind.SPEED_RAMP], "angle": 0.0})
	var plain := _bullet({"angle": 0.0})
	ProjectileMotion.step(curved, 1.0, now)
	ProjectileMotion.step(plain, 1.0, now)
	assert_lt(curved["traveled"], plain["traveled"], "the ramp starts from a standstill")


# --- line-segment spin -----------------------------------------------------

func test_a_line_segment_with_a_frequency_sweeps():
	var wall := _bullet({"flags": [ProjectileKind.LINE_SEGMENT], "frequency": 90.0,
		"magnitude": 0.0})
	ProjectileMotion.step(wall, 1.0, now)
	assert_almost_eq(wall["angle"], PI / 2.0, 0.0001, "90 degrees per tick")


func test_a_line_segment_without_a_frequency_holds_its_angle():
	var wall := _bullet({"flags": [ProjectileKind.LINE_SEGMENT], "angle": 0.25})
	ProjectileMotion.step(wall, 1.0, now)
	assert_eq(wall["angle"], 0.25)


func test_an_ordinary_bullet_never_spins():
	var bullet := _bullet({"frequency": 90.0, "amplitude": 0.0, "angle": 0.0})
	ProjectileMotion.step(bullet, 1.0, now)
	assert_eq(bullet["angle"], 0.0, "frequency alone does not rotate a plain shot")


# --- homing ----------------------------------------------------------------

func _load_enemy(id: int, position: Vector2) -> void:
	entities.apply_load({"enemies": [WireHelper.enemy(id, 1, position)]})


func test_homing_turns_toward_the_target():
	_load_enemy(7, Vector2(100, -8))     # centre (108, 0)
	var bullet := _bullet({"flags": [ProjectileKind.HOMING], "target_entity_id": 7,
		"frequency": 180.0, "pos": Vector2(-4, -4)})   # centre (0, 0)
	ProjectileTracking.steer(bullet, entities, player, 1.0)
	# Velocity is (sin a, cos a), so facing +x is an angle of PI/2.
	assert_almost_eq(bullet["angle"], PI / 2.0, 0.001)


func test_homing_turns_no_faster_than_its_frequency():
	_load_enemy(7, Vector2(100, -8))
	var bullet := _bullet({"flags": [ProjectileKind.HOMING], "target_entity_id": 7,
		"frequency": 1.0, "pos": Vector2(-4, -4)})
	ProjectileTracking.steer(bullet, entities, player, 1.0)
	assert_almost_eq(bullet["angle"], deg_to_rad(1.0), 0.0001, "one degree this tick")


func test_homing_takes_the_shortest_way_round():
	_load_enemy(7, Vector2(-100, -8))    # directly behind, at angle -PI/2
	var bullet := _bullet({"flags": [ProjectileKind.HOMING], "target_entity_id": 7,
		"frequency": 10.0, "pos": Vector2(-4, -4), "angle": 0.0})
	ProjectileTracking.steer(bullet, entities, player, 1.0)
	assert_lt(bullet["angle"], 0.0, "turns the short way, not the long way")


func test_homing_at_the_local_player_uses_the_predicted_position():
	# The roster copy of the local player lags prediction, and the server is
	# steering at where the player actually is.
	entities.apply_load({"players": [WireHelper.player(42, "me", Vector2.ZERO)]})
	player.position = Vector2(0, 500)
	var bullet := _bullet({"flags": [ProjectileKind.HOMING], "target_entity_id": 42,
		"frequency": 180.0, "pos": Vector2(-4, -4)})
	ProjectileTracking.steer(bullet, entities, player, 1.0)
	assert_almost_eq(bullet["angle"], 0.0, 0.05, "aimed down the +y axis at the prediction")


func test_homing_at_a_vanished_target_flies_on():
	var bullet := _bullet({"flags": [ProjectileKind.HOMING], "target_entity_id": 999,
		"frequency": 180.0, "angle": 0.25})
	ProjectileTracking.steer(bullet, entities, player, 1.0)
	assert_eq(bullet["angle"], 0.25, "no target, no steering")


func test_a_bullet_with_no_target_id_is_left_alone():
	var bullet := _bullet({"flags": [ProjectileKind.HOMING], "angle": 0.25})
	ProjectileTracking.steer(bullet, entities, player, 1.0)
	assert_eq(bullet["angle"], 0.25)


# --- anchoring -------------------------------------------------------------

func test_an_anchored_bullet_follows_its_source():
	_load_enemy(7, Vector2(50, 50))
	var wall := _bullet({"flags": [ProjectileKind.ANCHORED], "src_entity_id": 7,
		"pos": Vector2(60, 55)})
	ProjectileTracking.capture_anchor(wall, entities, player)
	assert_eq(wall["anchor_offset"], Vector2(10, 5))

	# Anchoring tracks the enemy's *rendered* position, so the wall stays
	# visually attached; that position is interpolated INTERP_DELAY_MS behind,
	# so the clock has to move past the new snapshot for it to count -- and
	# the snapshot has to be a later one, not a correction of the first,
	# which would be eased over rather than adopted.
	now += 50
	_load_enemy(7, Vector2(70, 50))
	now += int(EntitySnapshots.INTERP_DELAY_MS) + 50
	ProjectileTracking.anchor(wall, entities, player)
	assert_eq(wall["pos"], Vector2(80, 55), "the wall moved with the enemy")


func test_an_anchored_bullet_holds_position_when_its_source_is_gone():
	var wall := _bullet({"flags": [ProjectileKind.ANCHORED], "src_entity_id": 404,
		"pos": Vector2(60, 55)})
	ProjectileTracking.capture_anchor(wall, entities, player)
	ProjectileTracking.anchor(wall, entities, player)
	assert_eq(wall["pos"], Vector2(60, 55), "left where it was, to expire on its own")


func test_anchoring_to_the_local_player_tracks_the_prediction():
	entities.apply_load({"players": [WireHelper.player(42, "me", Vector2.ZERO)]})
	var wall := _bullet({"flags": [ProjectileKind.ANCHORED], "src_entity_id": 42,
		"pos": Vector2(105, 100)})
	ProjectileTracking.capture_anchor(wall, entities, player)
	player.position = Vector2(200, 100)
	ProjectileTracking.anchor(wall, entities, player)
	assert_eq(wall["pos"], Vector2(205, 100))


func test_an_anchored_wall_captures_late_when_its_source_arrives_after_it():
	# A wall reloads on the bullets-only delta BEFORE its boss has loaded, so the
	# arrival capture finds no source. When the source appears, anchoring must capture
	# the offset from the pos the wall still holds -- not reposition it with the zero
	# default, which collapsed a whole wall-box onto the boss's top-left corner.
	var wall := _bullet({"flags": [ProjectileKind.ANCHORED], "src_entity_id": 7,
		"pos": Vector2(60, 55)})
	ProjectileTracking.capture_anchor(wall, entities, player)
	assert_false(wall["anchor_captured"], "no source yet, nothing captured")

	_load_enemy(7, Vector2(50, 50))
	ProjectileTracking.anchor(wall, entities, player)
	assert_true(wall["anchor_captured"], "captured once the source arrived")
	assert_eq(wall["pos"], Vector2(60, 55), "held its server position, not the enemy corner")
	assert_eq(wall["anchor_offset"], Vector2(10, 5))

	now += 50
	_load_enemy(7, Vector2(70, 50))
	now += int(EntitySnapshots.INTERP_DELAY_MS) + 50
	ProjectileTracking.anchor(wall, entities, player)
	assert_eq(wall["pos"], Vector2(80, 55), "tracks the enemy after the late capture")


# --- wired into the simulation ---------------------------------------------

func _system() -> ProjectileSystem:
	return ProjectileSystem.new(player, null, func() -> int: return now, entities)


func _wire(overrides := {}) -> Dictionary:
	var wire := {
		"id": 1, "projectileId": 10, "size": 8, "pos": {"x": 60.0, "y": 55.0},
		"angle": 0.0, "magnitude": 0.0, "range": 1000.0, "damage": 1, "flags": [],
		"lifetimeTicks": 64, "srcEntityId": 0, "createdTime": 0,
	}
	wire.merge(overrides, true)
	return wire


func test_an_anchored_bullet_captures_its_offset_when_it_arrives():
	_load_enemy(7, Vector2(50, 50))
	var system := _system()
	system.apply_load({"bullets": [_wire({
		"flags": [ProjectileKind.ANCHORED], "srcEntityId": 7})]})
	assert_eq(system.bullets[1]["anchor_offset"], Vector2(10, 5))


func test_advancing_re_anchors_a_wall_to_its_moved_source():
	_load_enemy(7, Vector2(50, 50))
	var system := _system()
	system.apply_load({"bullets": [_wire({
		"flags": [ProjectileKind.ANCHORED], "srcEntityId": 7})]})
	now += 50
	_load_enemy(7, Vector2(90, 50))
	now += int(EntitySnapshots.INTERP_DELAY_MS) + 50
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets[1]["pos"], Vector2(100, 55), "followed its source")


func test_a_wall_reloaded_before_its_source_does_not_collapse_onto_it():
	# The real reload order: the wall's bullets-only delta arrives first, the boss loads
	# after. advance() must capture the offset late rather than snap the wall to the boss.
	var system := _system()
	system.apply_load({"bullets": [_wire({
		"flags": [ProjectileKind.ANCHORED], "srcEntityId": 7})]})
	_load_enemy(7, Vector2(50, 50))
	system.advance(RealmState.TICK_DELTA)
	assert_eq(system.bullets[1]["pos"], Vector2(60, 55),
		"kept its server position instead of snapping to the enemy corner")


func test_advancing_steers_a_homing_bullet():
	_load_enemy(7, Vector2(500, -8))
	var system := _system()
	system.apply_load({"bullets": [_wire({
		"flags": [ProjectileKind.HOMING], "magnitude": 1.0, "frequency": 180.0,
		"pos": {"x": -4.0, "y": -4.0}, "targetEntityId": 7})]})
	system.advance(RealmState.TICK_DELTA)
	assert_almost_eq(system.bullets[1]["angle"], PI / 2.0, 0.05, "turned toward the enemy")


func test_a_system_without_a_roster_leaves_tracking_bullets_straight():
	# ProjectileSystem is constructible without an entity registry; those
	# bullets must still fly rather than crash on the missing roster.
	var bare := ProjectileSystem.new(player, null, func() -> int: return now)
	bare.apply_load({"bullets": [_wire({
		"flags": [ProjectileKind.HOMING], "magnitude": 1.0, "frequency": 180.0,
		"targetEntityId": 7})]})
	bare.advance(RealmState.TICK_DELTA)
	assert_eq(bare.bullets[1]["angle"], 0.0, "no roster, no steering")
