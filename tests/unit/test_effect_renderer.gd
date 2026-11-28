extends GutTest

## What a cast leaves on the ground, and who is still casting.

var state: RealmState
var content: GameData
var renderer: WorldRenderer
var now := 1000


func before_each():
	now = 1000
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return now)
	state.local.id = 1
	renderer = WorldRenderer.new()
	renderer.setup(state, content)
	add_child_autofree(renderer)
	var camera := Camera2D.new()
	add_child_autofree(camera)
	camera.make_current()


func _effect(at: Vector2, duration := 1000) -> void:
	state.apply_packet("CreateEffectPacket", {"effectType": 0, "posX": at.x, "posY": at.y,
		"radius": 40.0, "duration": duration, "targetPosX": 0.0, "targetPosY": 0.0,
		"tier": 2, "ownerId": 1})


func _drawn() -> int:
	return renderer.draw_stats.get("effects", -1)


func test_the_layer_sits_between_the_bullets_and_the_labels():
	assert_gt(renderer.effects.get_index(), renderer.bullets.get_index())
	assert_lt(renderer.effects.get_index(), renderer.debug.get_index())


func test_nothing_is_drawn_with_nothing_landed():
	await wait_process_frames(2)
	assert_eq(_drawn(), 0)


func test_an_effect_in_view_is_drawn_and_one_far_away_is_not():
	_effect(Vector2(20, 20))
	_effect(Vector2(9000, 9000))
	await wait_process_frames(2)
	assert_eq(_drawn(), 1)


func test_the_cast_ring_and_a_cast_bar_count_too():
	state.abilities.show_ring(Vector2.ZERO, 96.0)
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "them", Vector2(30, 30))]})
	state.apply_packet("AbilityCastStartPacket", {"playerId": 2, "abilityId": 13006, "slot": 0,
		"durationMs": 1000, "worldTargetX": 80.0, "worldTargetY": 30.0})
	state.apply_packet("AbilityCastStartPacket", {"playerId": 77, "abilityId": 13006, "slot": 0,
		"durationMs": 1000, "worldTargetX": 0.0, "worldTargetY": 0.0})
	await wait_process_frames(2)
	assert_eq(_drawn(), 2, "the ring and the bar; a caster not in the roster has no bar")


func test_an_expired_effect_is_gone_from_the_count():
	_effect(Vector2.ZERO, 500)
	now += 500
	state.advance(0.0, Vector2.ZERO, 0.0)
	await wait_process_frames(2)
	assert_eq(_drawn(), 0)


func test_the_tier_palette_is_the_web_clients():
	assert_eq(EffectRenderer.TIER_COLOURS.size(), 7)
	assert_eq(EffectRenderer.TIER_COLOURS[0], Color("c0c0c0"))
	assert_eq(EffectRenderer.TIER_COLOURS[6], Color("c060ff"))


func test_effects_are_drawn_in_among_the_bodies_not_over_them():
	_effect(Vector2(20, 20))
	state.abilities.show_ring(Vector2.ZERO, 96.0)
	await wait_process_frames(2)
	assert_eq(renderer.entities.effects.drawn, 1, "the effect is drawn in the entities' depth pass")
	assert_eq(renderer.effects.drawn, 1, "the overlay keeps only the cast ring")
	assert_eq(_drawn(), 2)


func _placed(effects: Array, bodies: Array, kind := 0) -> PackedInt64Array:
	var realm := RealmState.new(content, func() -> int: return now)
	for at in effects:
		realm.abilities.effects.append({"type": kind, "pos": at, "radius": 20.0, "duration_ms": 1000,
			"target": Vector2.ZERO, "tier": 0, "owner": 0, "started": now})
	var depths := PackedInt64Array()
	for body in bodies:
		depths.append(EntityQueue.depth(body))
	var sorted := SortedEffects.new()
	sorted.collect(realm, Rect2(-1000, -1000, 2000, 2000))
	sorted.place(bodies, depths)
	return sorted.slots()


func test_an_effect_draws_before_the_first_body_it_touches():
	var far := {"pos": Vector2(400, 0), "size": 32.0}
	var target := {"pos": Vector2(0, 0), "size": 32.0}
	var in_front := {"pos": Vector2(0, 30), "size": 32.0}
	var slots := _placed([Vector2(16, 16)], [far, target, in_front])
	assert_eq(slots[0], 1, "under the body it plays on; the far body does not move it")


func test_an_effect_touching_no_body_draws_after_them_all():
	var body := {"pos": Vector2(0, 100), "size": 32.0}
	var slots := _placed([Vector2(300, 0)], [body])
	assert_eq(slots[0], 1, "after every body, so over every wall")


func test_a_melee_swing_draws_over_the_bodies_it_hits():
	var target := {"pos": Vector2(0, 0), "size": 32.0}
	var in_front := {"pos": Vector2(0, 30), "size": 32.0}
	var slots := _placed([Vector2(16, 16)], [target, in_front], EffectType.MELEE_SWING)
	assert_eq(slots[0], 2, "after every body, so the swing stays on top of what it hits")


func test_a_raised_body_is_found_after_the_ground_ones():
	var ground := {"pos": Vector2(500, 500), "size": 32.0}
	var flying := {"pos": Vector2(0, 0), "size": 64.0, "layer": 1}
	var slots := _placed([Vector2(32, 32)], [ground, flying])
	assert_eq(slots[0], 1)
