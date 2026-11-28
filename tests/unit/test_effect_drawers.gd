extends GutTest

## The registry, the renderer's contract with every drawer, the shared
## helpers, the generic fallback, and the shapes of the first six ported.
## Each group's own types are pinned in its tests/unit/test_fx_<group>.gd.

var state: RealmState
var renderer: WorldRenderer


func before_each():
	state = RealmState.new(null, func() -> int: return 500)
	renderer = WorldRenderer.new()
	renderer.setup(state, GameData.new())
	add_child_autofree(renderer)
	var camera := Camera2D.new()
	add_child_autofree(camera)
	camera.make_current()


func _cast(kind: int, at := Vector2.ZERO, radius := 40.0, target := Vector2(30, 10), tier := 2) -> void:
	state.apply_packet("CreateEffectPacket", {"effectType": kind, "posX": at.x, "posY": at.y,
		"radius": radius, "duration": 1000, "targetPosX": target.x, "targetPosY": target.y,
		"tier": tier, "ownerId": 1})


func test_every_type_the_server_names_has_a_drawer():
	for kind in EffectType.NAMES:
		assert_true(Fx.for_type(kind).is_valid(), EffectType.NAMES[kind])
	for retired in [21, 48, 49, 50, 999]:
		assert_false(Fx.for_type(retired).is_valid(), "id %d" % retired)


func test_every_drawer_draws_without_error_through_the_renderer():
	# Every named type, early, mid and late in its life and at its end, as
	# an area and as a line to a far end at radius 0 -- one type at a time,
	# since the state keeps only the newest MAX_EFFECTS. The counts prove each
	# was visited; the log is what proves none of them errored.
	var log := ErrorLog.new()
	OS.add_logger(log)
	for kind in EffectType.NAMES:
		state.abilities.effects.clear()
		for progress in [0.0, 0.3, 0.7, 1.0]:
			_cast(kind, Vector2.ZERO, 40.0, Vector2(30, 10), 3)
			state.abilities.effects[-1]["started"] = 500 - int(progress * 1000)
			_cast(kind, Vector2(5, 5), 0.0, Vector2(60, 0), 6)
			state.abilities.effects[-1]["started"] = 500 - int(progress * 1000)
		assert_gt(await _drawn(), 0, EffectType.NAMES[kind])
	# The melee swing's four weapon archetypes ride in the tier byte.
	state.abilities.effects.clear()
	for archetype in [FxMeleeSwing.SWORD, FxMeleeSwing.AXE, FxMeleeSwing.HAMMER, FxMeleeSwing.DAGGER]:
		for progress in [0.0, 0.5, 0.8]:
			_cast(EffectType.MELEE_SWING, Vector2(10, 10), 24.0, Vector2.ZERO, archetype)
			state.abilities.effects[-1]["started"] = 500 - int(progress * 1000)
	assert_eq(await _drawn(), 12, "the four swings at three points in their stroke")
	OS.remove_logger(log)
	assert_eq(log.errors, [], "no drawer errored")


func _drawn() -> int:
	renderer.queue_redraw()
	await wait_process_frames(2)
	return renderer.draw_stats["effects"]


func test_a_beam_is_drawn_while_it_crosses_the_view_from_off_screen():
	_cast(EffectType.BEAM_WARNING, Vector2(-4000, 0), 6.0, Vector2(4000, 0))
	_cast(EffectType.HEAL_RADIUS, Vector2(-4000, 0), 40.0, Vector2.ZERO)
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(renderer.draw_stats["effects"], 1, "the beam crosses the camera; the heal at the boss does not")


func test_an_effects_reach_takes_in_its_far_end_but_not_the_origin():
	var beam := {"pos": Vector2(100, 0), "target": Vector2(300, 50), "radius": 5.0}
	assert_eq(EffectRenderer.bounds(beam), Rect2(95, -5, 210, 60))
	var area := {"pos": Vector2(100, 0), "target": Vector2.ZERO, "radius": 20.0}
	assert_eq(EffectRenderer.bounds(area), Rect2(80, -20, 40, 40), "a zero target is no target")


func test_the_web_clients_pixel_constants_are_halved_here():
	assert_eq(Fx.S, 0.5, "the web draws at 2x; its 5px rim is 2.5 world px")


func test_the_purify_circle_snaps_out_and_holds():
	assert_almost_eq(FxPurifyCircle.grow(0.2), 0.44, 0.001)
	assert_eq(FxPurifyCircle.grow(0.5), 1.0, "full by 45% and held")


func test_the_wizard_burst_grows_and_its_waves_are_staggered():
	assert_eq(FxWizardBurst.burst_radius(80.0, 0.0), 40.0)
	assert_almost_eq(FxWizardBurst.burst_radius(80.0, 1.0), 88.0, 0.001)
	assert_eq(Fx.wave(0.1, 0.2), -1.0, "the second wave has not started")
	assert_almost_eq(Fx.wave(0.6, 0.2), 0.5, 0.001)
	assert_eq(Fx.wave(1.0, 0.0), -1.0, "and a wave that has gone is gone")


func test_the_smoke_billows_out_to_twice_the_radius():
	assert_eq(FxSmokePoof.puff_radius(50.0, 0.0), 30.0)
	assert_eq(FxSmokePoof.puff_radius(50.0, 1.0), 100.0)


func test_the_bolt_connects_its_ends_and_shivers_the_same_way_twice():
	var rng := Fx.rng_for({"started": 5, "pos": Vector2(1, 2)}, 300)
	var path := FxChainLightning.spine(Vector2(0, 0), Vector2(70, 0), rng)
	assert_eq(path[0], Vector2(0, 0))
	assert_eq(path[path.size() - 1], Vector2(70, 0))
	assert_eq(path.size(), 21, "a segment every 3.5 world px, twenty of them")
	var jitter := 0.0
	for point in path:
		jitter = maxf(jitter, absf(point.y))
	assert_gt(jitter, 0.0, "jagged")
	assert_lt(jitter, 14.0 + 0.001, "never more than 28 web px, 14 world, across the line")
	var again := FxChainLightning.spine(Vector2(0, 0), Vector2(70, 0),
		Fx.rng_for({"started": 5, "pos": Vector2(1, 2)}, 310))
	assert_eq(path, again, "the same tick of its age rolls the same shape")
	var later := FxChainLightning.spine(Vector2(0, 0), Vector2(70, 0),
		Fx.rng_for({"started": 5, "pos": Vector2(1, 2)}, 400))
	assert_ne(path, later, "the next tick rolls a new one")
	assert_eq(FxChainLightning.strike(0.1), 1.0)
	assert_almost_eq(FxChainLightning.strike(0.59), 0.5, 0.001)


func test_the_seal_and_the_swing_size_from_the_radius():
	assert_eq(FxPaladinSeal.base_radius(100.0, 0.0), 70.0)
	assert_eq(FxPaladinSeal.base_radius(100.0, 1.0), 100.0)
	assert_almost_eq(FxMeleeSwing.span(24.0), 72.0, 0.001)
	assert_eq(FxMeleeSwing.span(4.0), 64.0, "never under 64: a far cursor does not size it either")
	assert_eq(FxMeleeSwing.span(64.0), 120.0, "a big weapon tops out at 120")


func test_a_swing_stays_on_screen_long_enough_to_read():
	state.apply_packet("CreateEffectPacket", {"effectType": EffectType.MELEE_SWING, "posX": 10.0, "posY": 0.0,
		"radius": 24.0, "duration": 165, "targetPosX": 0.0, "targetPosY": 0.0, "tier": FxMeleeSwing.SWORD})
	assert_eq(state.abilities.effects[-1]["duration_ms"], 300, "the sword's afterglow outlasts the 165ms swing")
	assert_eq(FxMeleeSwing.hold_ms(FxMeleeSwing.HAMMER, 900), 900, "a longer window from the server is kept")


func test_the_generic_form_is_the_natives_in_the_tier_colour():
	assert_almost_eq(FxGeneric.radius_at(90.0, 0.1), 27.0, 0.001, "snaps out over the first third")
	assert_eq(FxGeneric.radius_at(90.0, 0.5), 90.0)
	assert_eq(FxGeneric.alpha_at(0.5), 1.0, "held to 70%")
	assert_almost_eq(FxGeneric.alpha_at(0.85), 0.5, 0.01, "then fades")
	assert_almost_eq(FxGeneric.alpha_at(1.0), 0.0, 0.002)


func test_an_id_this_build_does_not_know_draws_the_generic_form_or_the_boss_one():
	# 21 and 48 are retired, so they can never gain a drawer: they stand in
	# for whatever a newer server adds.
	_cast(21)
	_cast(48)
	for tier in [10, 11, 12]:
		_cast(21, Vector2(20, 20), 40.0, Vector2.ZERO, tier)
	for fx in state.abilities.effects:
		fx["started"] = 100
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(renderer.draw_stats["effects"], 5)
	assert_eq(FxGeneric.last_form, "boss", "the sentinel, drawn last, took the boss form")
	state.abilities.effects = state.abilities.effects.slice(0, 2)
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(FxGeneric.last_form, "generic")
	# Early, under the opening flash, and at no radius at all, which draws nothing.
	state.abilities.effects[0]["started"] = 450
	_cast(49, Vector2.ZERO, 0.0)
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(renderer.draw_stats["effects"], 3)
