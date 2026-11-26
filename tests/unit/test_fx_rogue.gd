extends GutTest

## The rogue's effects -- the ninja dash, beast claws, death blossom,
## reckless slash, star shuriken, blade storm, blade orbit and blade
## blender: their shapes' numbers, taken from the web client's cases, and
## that each draws without error through the real renderer.

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


## Casts one and backdates it so the renderer's clock (500) finds it
## `progress` of the way through.
func _cast_at(kind: int, progress: float, target := Vector2(30, 10), tier := 2) -> void:
	_cast(kind, Vector2.ZERO, 40.0, target, tier)
	state.abilities.effects[-1]["started"] = 500 - int(progress * 1000.0)


func test_each_rogue_type_has_a_drawer():
	assert_true(Fx.for_type(EffectType.NINJA_DASH).is_valid())
	assert_true(Fx.for_type(EffectType.BEAST_CLAWS).is_valid())
	assert_true(Fx.for_type(EffectType.DEATH_BLOSSOM).is_valid())
	assert_true(Fx.for_type(EffectType.RECKLESS_SLASH).is_valid())
	assert_true(Fx.for_type(EffectType.STAR_SHURIKEN).is_valid())
	assert_true(Fx.for_type(EffectType.BLADE_STORM).is_valid())
	assert_true(Fx.for_type(EffectType.BLADE_ORBIT).is_valid())
	assert_true(Fx.for_type(EffectType.BLADE_BLENDER).is_valid())


func test_every_rogue_drawer_draws_through_the_renderer():
	# The six one-shot types at four points in their lives: 24. A long dash
	# (more blades and cuts than the minimum) and one of no length at all,
	# both mid-swing: 2 more. The two blade fields cast three times each at
	# three tiers; only the newest of each survives: 2 more. 28 in all.
	for progress in [0.0, 0.3, 0.7, 0.95]:
		for kind in [13, 28, 30, 32, 33, 44]:
			_cast_at(kind, progress)
	_cast_at(13, 0.5, Vector2(210, 0))
	_cast_at(13, 0.5, Vector2.ZERO)
	for tier in [0, 3, 6]:
		_cast_at(46, 0.4, Vector2.ZERO, tier)
		_cast_at(47, 0.4, Vector2.ZERO, tier)
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(renderer.draw_stats["effects"], 28)


func test_the_shared_shapes():
	assert_eq(FxBladeShapes.lens(Vector2.ZERO, 0.0, 8.0, 2.0),
		[Vector2(8, 0), Vector2(0, 2), Vector2(-8, 0), Vector2(0, -2)])
	var star := FxBladeShapes.star(Vector2.ZERO, 0.0, 20.0)
	assert_eq(star.size(), 8)
	assert_almost_eq(star[0], Vector2(10, 0), Vector2(0.001, 0.001), "a point at half the size")
	assert_almost_eq(star[1].length(), 4.0, 0.001, "the waist at a fifth")


func test_the_dash_fills_in_with_its_length():
	assert_eq(FxNinjaDash.blade_count(70.0), 14, "140 screen px / 14 is 10; never under fourteen")
	assert_eq(FxNinjaDash.blade_count(210.0), 30, "420 screen px / 14")
	assert_eq(FxNinjaDash.slash_count(70.0), 3)
	assert_eq(FxNinjaDash.slash_count(200.0), 10, "400 screen px / 40")
	assert_almost_eq(FxNinjaDash.start_puff(0.25), 0.6, 0.001)
	assert_eq(FxNinjaDash.start_puff(0.7), 0.0)
	assert_almost_eq(FxNinjaDash.arrival(0.25), 0.5, 0.001)
	assert_eq(FxNinjaDash.arrival(0.6), 0.0)


func test_the_vortex_blades_pop_orbit_and_shrink():
	assert_almost_eq(FxNinjaVortex.appear_at(1.0), 0.45, 0.001)
	assert_almost_eq(FxNinjaVortex.blade_scale(0.075), 0.5, 0.001)
	assert_eq(FxNinjaVortex.blade_scale(0.5), 1.0)
	assert_almost_eq(FxNinjaVortex.blade_scale(0.875), 0.5, 0.001)
	assert_eq(FxNinjaVortex.blade_scale(1.0), 0.0)
	assert_eq(FxNinjaVortex.orbit(0, 0), 0.0)
	assert_almost_eq(FxNinjaVortex.orbit(1, 0), 11.499, 0.01, "sin(0.55) of the web's 44px, 22 world")
	assert_almost_eq(FxNinjaVortex.orbit(2, 0), -19.608, 0.01, "even blades sweep the other way")
	assert_almost_eq(FxNinjaVortex.spin(1, 100), 2.0, 0.001)


func test_the_katana_eases_through_the_cut_and_lingers():
	assert_almost_eq(FxNinjaKatana.ease_swing(0.25), 0.125, 0.001)
	assert_almost_eq(FxNinjaKatana.ease_swing(0.5), 0.5, 0.001)
	assert_almost_eq(FxNinjaKatana.ease_swing(0.75), 0.875, 0.001)
	assert_eq(FxNinjaKatana.ease_swing(1.3), 1.0, "held at the end through the afterglow")
	assert_eq(FxNinjaKatana.fade(0.5, 0.8), 0.8)
	assert_almost_eq(FxNinjaKatana.fade(1.2, 1.0), 0.5, 0.001)
	assert_eq(FxNinjaKatana.REACH, 28.0, "the web's 56px sword")


func test_the_claws_rake_twice_and_the_blossom_bursts_open():
	assert_almost_eq(FxBeastClaws.swipe(0.1, 0), 0.75, 0.001, "fast out of the gate")
	assert_eq(FxBeastClaws.swipe(0.1, 1), 0.0, "the second rake not started")
	assert_eq(FxBeastClaws.swipe(0.36, 1), 1.0, "and done by 36%")
	assert_almost_eq(FxBeastClaws.rake_angle(0.0, 0), PI * 0.68, 0.001)
	assert_almost_eq(FxBeastClaws.rake_angle(0.0, 1), PI * 0.32, 0.001, "slanting the other way")
	assert_almost_eq(FxBeastClaws.gouge_length(40.0, 0), 60.8, 0.001, "an outer claw a fifth short of 1.9")
	assert_almost_eq(FxBeastClaws.gouge_length(40.0, 1), 70.933, 0.001)
	var gouge := FxBeastClaws.gouge(Vector2.ZERO, Vector2.RIGHT, 10.0, 2.0, 1.0)
	assert_eq(gouge.size(), 16, "both edges, sharing the two points")
	assert_almost_eq(gouge[0], Vector2(-5, 0), Vector2(0.001, 0.001))
	assert_almost_eq(gouge[FxBeastClaws.STEPS], Vector2(5, 0), Vector2(0.001, 0.001), "pointed at the claw")
	assert_almost_eq(FxDeathBlossom.reach(40.0), 44.0, 0.001)
	assert_almost_eq(FxDeathBlossom.slash_angle(2, 1.0), 3.1416, 0.001, "a quarter turn, plus a quarter by the end")
	assert_eq(FxDeathBlossom.bloom(0.0), 0.0)
	assert_almost_eq(FxDeathBlossom.bloom(0.175), 0.875, 0.001, "most of the way open by half its burst")
	assert_eq(FxDeathBlossom.bloom(0.5), 1.0)
	var petal := FxDeathBlossom.petal(Vector2.ZERO, 0.0, 2.0, 20.0, 3.0, 0.0)
	assert_eq(petal.size(), 10, "both edges, sharing root and tip")
	assert_almost_eq(petal[FxDeathBlossom.PETAL_STEPS], Vector2(20, 0), Vector2(0.001, 0.001), "the tip")
	assert_almost_eq(FxRecklessSlash.reach(40.0), 44.0, 0.001)
	assert_almost_eq(FxRecklessSlash.sweep_t(0.25), 0.5, 0.001, "cleaves across the first half")


func test_the_star_grows_and_spins():
	assert_almost_eq(FxStarShuriken.arm_radius(50.0, 0.0), 30.0, 0.001)
	assert_almost_eq(FxStarShuriken.arm_radius(50.0, 1.0), 50.0, 0.001)
	assert_almost_eq(FxStarShuriken.spin(100), 1.8, 0.001)
	var corners := FxStarShuriken.points_at(Vector2.ZERO, FxStarShuriken.arm_radius(50.0, 0.0), 0.0)
	assert_eq(corners.size(), 4)
	assert_almost_eq(corners[1], Vector2(0, 30), Vector2(0.001, 0.001), "a quarter turn round at the arm")


func test_the_blade_storm_whirls_inside_the_radius():
	assert_almost_eq(FxBladeStorm.orbit_radius(40.0), 34.0, 0.001)
	assert_almost_eq(FxBladeStorm.spin(100), 2.5, 0.001)


func test_the_blade_orbit_keeps_its_phase_across_refreshes():
	assert_eq(FxBladeOrbit.orbit_radius(4.0), 18.0, "never tighter than the web's 36px")
	assert_eq(FxBladeOrbit.orbit_radius(40.0), 40.0)
	assert_almost_eq(FxBladeOrbit.orbit_angle(1, 1000), 4.3708, 0.001, "a quarter turn plus 2.8 rad a second")
	assert_almost_eq(FxBladeOrbit.spin(1, 1000), 12.7, 0.001)
	assert_eq(FxBladeOrbit.clock({"started": 1000}, 250), 1250)
	assert_eq(FxBladeOrbit.clock({"started": 1200}, 50), 1250, "a fresh packet picks up the same instant")


func test_the_blender_spirals_out_from_near_the_centre():
	var first := FxBladeBlender.blade_offset(0, 100.0, 0)
	assert_almost_eq(first, Vector2(14.979, 18.107), Vector2(0.01, 0.01), "a tenth of 1.4 turns out, at 23.5")
	assert_almost_eq(FxBladeBlender.blade_offset(8, 100.0, 0).length(), 91.5, 0.001)
	assert_almost_eq(FxBladeBlender.spin(2, 100), 2.8, 0.001)
