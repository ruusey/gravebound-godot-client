extends GutTest

## Skill points, cooldowns, casts in progress and effects landed.

var state: RealmState
var now := 1000


func before_each():
	now = 1000
	state = RealmState.new(null, func() -> int: return now)
	state.local.id = 9


func _update(extra := {}) -> Dictionary:
	var data := {"playerId": 9, "inventory": []}
	data.merge(extra, true)
	return data


func _cast_start(player_id: int, duration := 1200, target := Vector2(200, 60)) -> void:
	state.apply_packet("AbilityCastStartPacket", {"playerId": player_id, "abilityId": 13006,
		"slot": 0, "durationMs": duration, "worldTargetX": target.x, "worldTargetY": target.y})


func _effect(kind: int, duration := 1000, at := Vector2.ZERO, tier := 0) -> void:
	state.apply_packet("CreateEffectPacket", {"effectType": kind, "posX": at.x, "posY": at.y,
		"radius": 40.0, "duration": duration, "targetPosX": 0.0, "targetPosY": 0.0,
		"tier": tier, "ownerId": 9})


# --- points ------------------------------------------------------------------

func test_points_and_levels_ride_the_update_packet():
	state.apply_packet("UpdatePacket", _update({"availableSkillPoints": 2, "investedSlot0": 1,
		"investedSlot1": 0, "investedSlot2": 3, "investedSlot3": 0}))
	assert_eq(state.abilities.available_points, 2)
	assert_eq(state.abilities.invested, [1, 0, 3, 0])


func test_another_players_update_is_not_ours():
	state.apply_packet("UpdatePacket", {"playerId": 10, "inventory": [], "availableSkillPoints": 5})
	assert_eq(state.abilities.available_points, 0)


func test_an_update_bumps_the_version_and_clear_resets():
	var before := state.abilities.version
	state.apply_packet("UpdatePacket", _update({"availableSkillPoints": 1}))
	assert_gt(state.abilities.version, before)
	state.abilities.start_cooldown(0, 500)
	state.reset_world()
	assert_eq(state.abilities.available_points, 0)
	assert_false(state.abilities.on_cooldown(0))


# --- cooldowns ---------------------------------------------------------------

func test_a_cooldown_drains_from_full_to_nothing():
	state.abilities.start_cooldown(1, 2000)
	assert_true(state.abilities.on_cooldown(1))
	assert_almost_eq(state.abilities.cooldown_fraction(1), 1.0, 0.001)
	now += 1000
	assert_almost_eq(state.abilities.cooldown_fraction(1), 0.5, 0.001)
	now += 1000
	assert_false(state.abilities.on_cooldown(1))
	assert_eq(state.abilities.cooldown_fraction(1), 0.0)
	assert_eq(state.abilities.cooldown_fraction(2), 0.0, "a slot never cast")


# --- casts -------------------------------------------------------------------

func test_a_cast_start_is_tracked_and_a_remote_caster_swings():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(9, "me", Vector2.ZERO),
		WireHelper.player(2, "them", Vector2(50, 50))]})
	_cast_start(2)
	assert_eq(state.abilities.cast_progress(2), 0.0)
	assert_true(state.entities.players[2]["attack"].is_active(), "aimed at the target")
	assert_eq(state.entities.players[2]["attack"].facing, "side")
	now += 600
	assert_almost_eq(state.abilities.cast_progress(2), 0.5, 0.001)
	now += 700
	state.advance(0.0, Vector2.ZERO, 0.0)
	assert_eq(state.abilities.cast_progress(2), -1.0, "expired")


func test_our_own_cast_start_does_not_restart_our_pose():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(9, "me", Vector2.ZERO)]})
	_cast_start(9)
	assert_false(state.entities.players[9]["attack"].is_active())
	assert_true(state.abilities.casts.has(9), "but the bar still shows")


func test_a_cast_of_no_duration_is_ignored():
	_cast_start(2, 0)
	assert_false(state.abilities.casts.has(2))


# --- effects -----------------------------------------------------------------

func test_an_effect_lands_and_expires():
	_effect(0, 1000, Vector2(10, 20), 3)
	assert_eq(state.abilities.effects.size(), 1)
	assert_eq(state.abilities.effects[0]["pos"], Vector2(10, 20))
	assert_eq(state.abilities.effects[0]["tier"], 3)
	now += 999
	state.advance(0.0, Vector2.ZERO, 0.0)
	assert_eq(state.abilities.effects.size(), 1)
	now += 1
	state.advance(0.0, Vector2.ZERO, 0.0)
	assert_eq(state.abilities.effects.size(), 0)


func test_a_persistent_effect_replaces_its_predecessor():
	# The server re-sends blade orbit every ~250ms; drawing both stacks them
	# at different phases.
	_effect(46, 1000)
	now += 250
	_effect(46, 1000)
	_effect(47, 1000)
	assert_eq(state.abilities.effects.size(), 2, "one of each persistent type")
	assert_eq(state.abilities.effects[0]["started"], 1250, "the newer one")


func test_the_cast_ring_lingers_for_the_web_clients_duration():
	state.abilities.show_ring(Vector2.ZERO, 96.0)
	now += AbilityState.RING_MS - 1
	state.advance(0.0, Vector2.ZERO, 0.0)
	assert_eq(state.abilities.rings.size(), 1)
	now += 1
	state.advance(0.0, Vector2.ZERO, 0.0)
	assert_eq(state.abilities.rings.size(), 0)
	assert_eq(AbilityState.RING_MS, 700)
