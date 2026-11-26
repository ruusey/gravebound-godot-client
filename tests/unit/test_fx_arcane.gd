extends GutTest

## The arcane group: stasis field, blink glyph, lightning strike, mana
## bolt, time stop and the arcane and storm auras. Their shapes' numbers,
## worked from the web client's cases, and that each draws through the
## real renderer at the start, middle and end of its life.

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


func test_each_arcane_type_has_its_own_drawer():
	for kind in [EffectType.STASIS_FIELD, EffectType.BLINK_GLYPH, EffectType.LIGHTNING_STRIKE,
			EffectType.MANA_BOLT, EffectType.TIME_STOP, EffectType.ARCANE_AURA, EffectType.STORM_AURA]:
		assert_true(Fx.for_type(kind).is_valid(), "type %d" % kind)
	assert_eq(Fx.for_type(2), Callable(FxStasisField.draw))
	assert_eq(Fx.for_type(20), Callable(FxBlinkGlyph.draw))
	assert_eq(Fx.for_type(25), Callable(FxLightningStrike.draw))
	assert_eq(Fx.for_type(26), Callable(FxManaBolt.draw))
	assert_eq(Fx.for_type(27), Callable(FxTimeStop.draw))
	assert_eq(Fx.for_type(38), Callable(FxArcaneAura.draw))
	assert_eq(Fx.for_type(42), Callable(FxStormAura.draw))


func test_every_arcane_drawer_draws_through_the_renderer():
	# Seven types at 10%, 50% and 95% of a 1000ms life, the clock at 500:
	# the flash, the held ring and the last of the fade. None branches on
	# tier, so two tiers are enough to show it does not matter.
	var starts := [400, 0, -450]
	for start in starts:
		for kind in [2, 20, 25, 26, 27, 38, 42]:
			_cast(kind, Vector2(5, 5), 40.0, Vector2(30, 10), 6 if start == 0 else 1)
			state.abilities.effects[-1]["started"] = start
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(state.abilities.effects.size(), 21)
	assert_eq(renderer.draw_stats["effects"], 21)


func test_the_stasis_field_flashes_then_frosts():
	assert_eq(FxStasisField.flash(0.0), 1.0)
	assert_almost_eq(FxStasisField.flash(0.075), 0.5, 0.001)
	assert_eq(FxStasisField.flash(0.15), 0.0, "gone by 15%")
	assert_eq(FxStasisField.flash(0.5), 0.0)
	var hexes := FxStasisField.hex_centres(100.0)
	assert_eq(hexes.size(), 7, "one in the middle, six round it")
	assert_eq(hexes[0], Vector2.ZERO)
	assert_almost_eq(hexes[1].x, 35.2, 0.001, "0.22 * 1.6 of the radius out")
	assert_almost_eq(hexes[4].x, -35.2, 0.001)
	var crack := FxStasisField.fracture(Vector2.ZERO, 100.0, 0, 0)
	assert_eq(crack.size(), 5)
	assert_eq(crack[0], Vector2.ZERO)
	assert_almost_eq(crack[4].x, 100.0, 0.001, "to the rim")
	assert_almost_eq(crack[4].y, -1.1177, 0.001, "sin(6) of 4% of the radius sideways")


func test_the_stasis_wisps_drift_out_and_rise():
	assert_almost_eq(FxStasisField.wisp_phase(0, 0.5), 0.75, 0.0001)
	assert_almost_eq(FxStasisField.wisp_phase(1, 0.0), 0.683, 0.0001)
	assert_almost_eq(FxStasisField.wisp_phase(1, 0.3), 0.133, 0.0001, "wrapped round")
	var start := FxStasisField.wisp(Vector2.ZERO, 100.0, 0, 0.0)
	assert_almost_eq(start.x, 30.0, 0.001)
	assert_almost_eq(start.y, 0.0, 0.001)
	var later := FxStasisField.wisp(Vector2.ZERO, 100.0, 0, 0.5)
	assert_almost_eq(later.x, 71.25, 0.001, "30% plus 55% of three quarters")
	assert_almost_eq(later.y, -5.25, 0.001, "three quarters of 14 web px, 7 world, up")


func test_the_blink_glyph_opens_by_halfway_and_holds():
	assert_almost_eq(FxBlinkGlyph.ring_radius(100.0, 0.0), 40.0, 0.001)
	assert_almost_eq(FxBlinkGlyph.ring_radius(100.0, 0.25), 75.0, 0.001)
	assert_almost_eq(FxBlinkGlyph.ring_radius(100.0, 0.5), 110.0, 0.001)
	assert_almost_eq(FxBlinkGlyph.ring_radius(100.0, 0.9), 110.0, 0.001)
	assert_eq(FxBlinkGlyph.column_height(100.0, 0.0), 0.0)
	assert_almost_eq(FxBlinkGlyph.column_height(100.0, 0.15), 180.0, 0.001, "shot up by 15%")
	assert_eq(FxBlinkGlyph.column_strength(0.1), 1.0)
	assert_almost_eq(FxBlinkGlyph.column_strength(0.7), 0.0, 0.001, "gone by 70%")
	var star := FxBlinkGlyph.hexagram(Vector2.ZERO, 10.0, 0.0)
	assert_eq(star.size(), 2, "two triangles")
	assert_eq(star[0].size(), 4, "each closed")


func test_the_lightning_strike_falls_from_overhead_onto_the_mark():
	assert_almost_eq(FxLightningStrike.height(50.0), 110.0, 0.001)
	var bolt := FxLightningStrike.bolt(Vector2.ZERO, 50.0, 0)
	assert_eq(bolt.size(), 7, "six segments")
	assert_almost_eq(bolt[0].x, 0.0, 0.001)
	assert_almost_eq(bolt[0].y, -110.0, 0.001)
	assert_almost_eq(bolt[3].x, -3.2404, 0.001, "sin(5.1) * 14 web px halfway down: 7 web, 3.5 world")
	assert_almost_eq(bolt[3].y, -55.0, 0.001)
	assert_eq(bolt[6], Vector2.ZERO, "lands dead on")
	assert_almost_eq(FxLightningStrike.bolt(Vector2.ZERO, 50.0, 31)[0].x, 3.9991, 0.001, "the top sways 8 web px")
	assert_almost_eq(FxLightningStrike.impact_radius(50.0, 0.0), 20.0, 0.001)
	assert_almost_eq(FxLightningStrike.impact_radius(50.0, 1.0), 60.0, 0.001)


func test_the_mana_bolt_has_six_turning_arms():
	assert_eq(FxManaBolt.arm_angle(0, 0), 0.0)
	assert_almost_eq(FxManaBolt.arm_angle(3, 0), PI, 0.0001)
	assert_almost_eq(FxManaBolt.arm_angle(0, 1000), 3.0, 0.0001)


func test_the_clock_has_twelve_ticks_and_frozen_hands():
	var top := FxTimeStop.tick(Vector2.ZERO, 40.0, 0)
	assert_almost_eq(top[0].x, 37.0, 0.001, "6 web px in")
	assert_almost_eq(top[1].x, 33.0, 0.001, "to 14")
	var three := FxTimeStop.tick(Vector2.ZERO, 40.0, 3)
	assert_almost_eq(three[0].y, 37.0, 0.001)
	assert_almost_eq(three[0].x, 0.0, 0.001)
	var tips := FxTimeStop.hands(40.0)
	assert_eq(tips[0], Vector2(0.0, -22.0))
	assert_eq(tips[1], Vector2(28.0, 4.0))


func test_the_arcane_sparks_breathe_on_their_orbit():
	assert_almost_eq(FxArcaneAura.orbit_radius(100.0, 0, 0), 85.0, 0.001)
	assert_almost_eq(FxArcaneAura.orbit_radius(100.0, 0, 157), 100.0, 0.01, "at the crest of its sine")
	assert_almost_eq(FxArcaneAura.orbit_radius(100.0, 0, 471), 70.0, 0.01, "and the trough")
	assert_almost_eq(FxArcaneAura.spark_angle(2, 0), PI / 2.0, 0.0001)
	assert_almost_eq(FxArcaneAura.spark_angle(0, 200), 1.0, 0.0001)


func test_the_storm_bolts_reach_the_rim_bent_a_little():
	var bolt := FxStormAura.bolt(Vector2.ZERO, 100.0, 0, 0)
	assert_eq(bolt.size(), 6, "five segments from the centre")
	assert_eq(bolt[0], Vector2.ZERO)
	assert_almost_eq(bolt[5].length(), 100.0, 0.001)
	assert_almost_eq(bolt[5].angle(), -0.15343, 0.0001, "0.16 * sin(5) off its heading")
	assert_almost_eq(bolt[1].length(), 20.0, 0.001)
