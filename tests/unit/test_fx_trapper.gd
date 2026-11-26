extends GutTest

## The trapper's nine effects: each draws through the real renderer in
## every phase, and the numbers of its shape, spelled out from the web
## client's cases.

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


## Casts one and sets it `progress` of the way through its second.
func _cast_at(kind: int, progress: float, radius := 40.0, tier := 2) -> void:
	_cast(kind, Vector2.ZERO, radius, Vector2(30, 10), tier)
	state.abilities.effects[-1]["started"] = 500 - int(progress * 1000.0)


func _near(actual: Color, expected: Color, what: String) -> void:
	for c in 3:
		assert_almost_eq(actual[c], expected[c], 0.003, "%s channel %d" % [what, c])


func test_each_trapper_type_has_a_drawer():
	for kind in [EffectType.CURSE_RADIUS, EffectType.POISON_SPLASH, EffectType.TRAP_THROW,
			EffectType.TRAP_PLACED, EffectType.TRAP_TRIGGER, EffectType.SNARE_GEAR,
			EffectType.COMBUSTION_TRAP, EffectType.CALTROPS, EffectType.HASTE_WIND]:
		assert_true(Fx.for_type(kind).is_valid(), "type %d" % kind)


func test_every_phase_of_every_type_draws_through_the_renderer():
	for p in [0.2, 0.5]:
		_cast_at(EffectType.CURSE_RADIUS, p)
	for tier in [10, 11, 12]:
		_cast_at(EffectType.CURSE_RADIUS, 0.5, 40.0, tier)
	for tier in [2, 10, 11, 12]:
		_cast_at(EffectType.POISON_SPLASH, 0.3, 0.0, tier)
	_cast_at(EffectType.POISON_SPLASH, 0.99, 0.0)
	_cast_at(EffectType.POISON_SPLASH, 0.5)
	for p in [0.3, 0.99]:
		_cast_at(EffectType.TRAP_THROW, p, 0.0)
	for p in [0.5, 0.9]: # either side of the snare's fade at 85%
		_cast_at(EffectType.TRAP_THROW, p)
		_cast_at(EffectType.TRAP_PLACED, p)
	for p in [0.1, 0.24, 0.26, 0.29, 0.31, 0.9]:
		_cast_at(EffectType.TRAP_TRIGGER, p)
	for kind in [EffectType.SNARE_GEAR, EffectType.COMBUSTION_TRAP, EffectType.CALTROPS, EffectType.HASTE_WIND]:
		_cast_at(kind, 0.5)
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(renderer.draw_stats["effects"], 27)


func test_a_throw_is_a_line_effect_with_somewhere_to_land():
	assert_true(FxThrownArc.is_throw({"radius": 0.0, "target": Vector2(30, 10)}))
	assert_false(FxThrownArc.is_throw({"radius": 40.0, "target": Vector2(30, 10)}), "a splash has a radius")
	assert_false(FxThrownArc.is_throw({"radius": 0.0, "target": Vector2.ZERO}), "and a throw a target")


func test_the_throw_lifts_half_its_length_at_the_middle():
	assert_eq(FxThrownArc.point(Vector2(0, 0), Vector2(100, 0), 0.0), Vector2(0, 0))
	assert_eq(FxThrownArc.point(Vector2(0, 0), Vector2(100, 0), 1.0), Vector2(100, 0))
	assert_eq(FxThrownArc.point(Vector2(0, 0), Vector2(100, 0), 0.5), Vector2(50, -50))
	assert_eq(FxThrownArc.point(Vector2(0, 0), Vector2(100, 0), 0.25), Vector2(25, -37.5))
	assert_eq(FxThrownArc.toward_head(0.25, 0.5), 0.5)
	assert_almost_eq(FxThrownArc.toward_head(0.05, 0.0), 5.0, 0.001, "the head never divides by under 0.01")


func test_the_curse_shockwave_and_its_spiralling_motes():
	assert_almost_eq(FxCurseRadius.shock_radius(100.0, 0.0), 55.0, 0.001)
	assert_almost_eq(FxCurseRadius.shock_radius(100.0, 0.2), 85.0, 0.001)
	assert_almost_eq(FxCurseRadius.shock_radius(100.0, 0.5), 105.0, 0.001, "out by a third and held")
	assert_almost_eq(FxCurseRadius.inward(0, 0.5), 0.65, 0.001)
	assert_almost_eq(FxCurseRadius.inward(9, 0.5), 0.15, 0.001, "wrapped back out to the rim")


func test_the_boss_grenade_takes_the_web_clients_danger_colours():
	_near(FxCurseRadius.boss_colours(10)[0], Color("ff0d0d"), "red fill")
	_near(FxCurseRadius.boss_colours(10)[2], Color("ff7355"), "red second edge")
	_near(FxCurseRadius.boss_colours(11)[0], Color("14b83c"), "green fill")
	_near(FxCurseRadius.boss_colours(11)[1], Color("33e055"), "green edge")
	_near(FxCurseRadius.boss_colours(12)[1], Color("3399ff"), "blue edge")
	_near(FxCurseRadius.boss_colours(12)[2], Color("73c0ff"), "blue second edge")
	_near(FxCurseRadius.boss_colours(13)[0], Color("ff0d0d"), "any other sentinel is red")


func test_the_poison_vial_and_its_cloud():
	var body := func(tier: int) -> Color: return FxPoisonSplash.THROW_COLOURS[FxPoisonSplash.palette(tier)][3]
	assert_eq(body.call(2), Color("40cc30"), "the assassin's vial is green")
	assert_eq(body.call(10), Color("ff4d0d"), "the 10 grenade red")
	assert_eq(body.call(11), Color("40cc30"), "11 stays green")
	assert_eq(body.call(12), Color("2d7dff"), "and 12 blue")
	assert_eq(FxPoisonSplash.cloud_radius(50.0, 0.0), 20.0)
	assert_eq(FxPoisonSplash.cloud_radius(50.0, 1.0), 50.0)
	assert_eq(FxPoisonSplash.drip_fall_px(4, 0.5), 10.0)


func test_the_thrown_trap_spins_and_lands_as_a_snare_with_teeth():
	assert_almost_eq(FxTrapThrow.glint_angle(1, 0), PI / 2.0, 0.001)
	assert_almost_eq(FxTrapThrow.glint_angle(0, 100), 1.0, 0.001)
	assert_eq(FxSnareRing.fade(0.5), 1.0)
	assert_almost_eq(FxSnareRing.fade(0.925), 0.5, 0.001, "over the last 15%")
	assert_eq(FxSnareRing.tip_depth(20.0), 7.0, "14 web px on a small trap, 7 world")
	assert_almost_eq(FxSnareRing.tip_depth(100.0), 18.0, 0.001)
	assert_almost_eq(FxSnareRing.base_half_angle(), 0.15708, 0.0001)


func test_the_trigger_closes_holds_then_sprays():
	assert_eq(FxTrapTrigger.close_radius(40.0, 0.25), 30.0)
	assert_eq(FxTrapTrigger.flash_alpha(0.29), 1.0)
	assert_almost_eq(FxTrapTrigger.flash_alpha(0.65), 0.5, 0.001)
	assert_eq(FxTrapTrigger.spray(0.2), -1.0, "no blood before the bite")
	assert_almost_eq(FxTrapTrigger.spray(0.625), 0.5, 0.001)
	assert_eq(FxTrapTrigger.fleck_offset(0, 0.0), Vector2.ZERO)
	assert_eq(FxTrapTrigger.fleck_offset(0, 1.0), Vector2(20, 6), "40 web px out, 12 down, halved")


func test_the_gear_snaps_shut_and_the_blast_swells():
	assert_eq(FxSnareGear.gear_radius(100.0, 0.0), 100.0)
	assert_almost_eq(FxSnareGear.gear_radius(100.0, 0.3), 92.5, 0.001, "a quarter of the clamp by half the snap")
	assert_almost_eq(FxSnareGear.gear_radius(100.0, 0.6), 70.0, 0.001, "shut at 60%")
	assert_almost_eq(FxSnareGear.gear_radius(100.0, 1.0), 70.0, 0.001)
	assert_almost_eq(FxSnareGear.tooth(100.0), 14.0, 0.001)
	assert_eq(FxSnareGear.tooth(20.0), 4.0, "never under 4 units")
	assert_eq(FxSnareGear.cog_outline(Vector2.ZERO, 50.0, 10.0, 0.0).size(), 48, "four corners a tooth")
	var pit := FxSnareGear.pit_outline(Vector2.ZERO, 40.0, 20.0, 0.0)
	assert_eq(pit.size(), 36, "a jaw and three rim points each")
	assert_almost_eq(pit[1], Vector2(20, 0), Vector2(0.001, 0.001), "the first jaw's tip")
	assert_almost_eq(FxCombustionTrap.ring_radius(100.0, 0.0), 40.0, 0.001)
	assert_almost_eq(FxCombustionTrap.ring_radius(100.0, 1.0), 110.0, 0.001)
	assert_almost_eq(FxCombustionTrap.ember_reach(1), 0.383, 0.001)


func test_the_caltrops_spread_over_the_field_and_land():
	assert_eq(FxCaltrops.count(20.0), 8, "never fewer than eight")
	assert_eq(FxCaltrops.count(48.0), 9)
	assert_eq(FxCaltrops.count(200.0), 18, "never more than eighteen")
	assert_almost_eq(FxCaltrops.size(48.0), 7.2, 0.001)
	assert_eq(FxCaltrops.size(200.0), 12.0)
	assert_almost_eq(FxCaltrops.offset(100.0, 0, 10).length(), 19.677, 0.001, "88% of the radius by sqrt(0.05)")
	assert_almost_eq(FxCaltrops.offset(100.0, 0, 10).angle(), 0.5, 0.001)
	assert_almost_eq(FxCaltrops.offset(100.0, 9, 10).length(), 85.772, 0.001, "the last near the rim")
	assert_almost_eq(FxCaltrops.toss(0.1, 0, 10), 0.833, 0.001)
	assert_eq(FxCaltrops.toss(0.2, 9, 10), 1.0, "all landed by a fifth")
	var star := FxCaltrops.star(Vector2.ZERO, 0.0, 10.0)
	assert_eq(star.size(), 6, "three spikes and three waists")
	assert_almost_eq(star[0], Vector2(10, 0), Vector2(0.001, 0.001))
	assert_almost_eq(star[1].length(), 2.6, 0.001)


func test_the_wind_streaks_wheel_and_widen():
	assert_almost_eq(FxHasteWind.streak_orbit(100.0, 0, 0.0), 40.5, 0.001)
	assert_almost_eq(FxHasteWind.streak_orbit(100.0, 3, 1.0), 115.5, 0.001, "1.05 of the radius, a fifth wider")
	assert_almost_eq(FxHasteWind.streak_angle(0, 1000), 6.5, 0.001, "6.5 radians a second")
	assert_almost_eq(FxHasteWind.streak_angle(1, 1000), PI * 0.5 + 7.28, 0.001, "a quarter turn on, 12% faster")
	assert_almost_eq(FxHasteWind.strength(0.05), 0.5, 0.001)
	assert_eq(FxHasteWind.strength(0.5), 1.0)
	assert_almost_eq(FxHasteWind.strength(0.825), 0.5, 0.001)
	assert_almost_eq(FxHasteWind.gust_phase(1, 0.5), 0.62, 0.001)
