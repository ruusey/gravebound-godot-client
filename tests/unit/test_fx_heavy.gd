extends GutTest

## The heavy group's nine effect drawers -- frost nova, rapier stab, low
## swing, disarm flourish, ground pound, the three druid casts and the
## boss beam warning: their shapes' numbers, spelled out from the web
## client's cases, and that each draws through the real renderer.

const HEAVY := [EffectType.FROST_NOVA, EffectType.RAPIER_STAB, EffectType.LOW_SWING,
	EffectType.DISARM_FLOURISH, EffectType.GROUND_POUND, EffectType.DRUID_ROOTS,
	EffectType.DRUID_MOONLIGHT, EffectType.DRUID_WILD_SURGE, EffectType.BEAM_WARNING]

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


func test_each_heavy_type_has_its_own_drawer():
	for kind in HEAVY:
		assert_true(Fx.for_type(kind).is_valid(), "type %d" % kind)


func test_every_heavy_drawer_draws_through_the_renderer():
	# Nine types at four points of their lives (the clock reads 500, the
	# duration is 1000), a frost nova of no radius and a beam of no length.
	for kind in HEAVY:
		for started in [500, 200, -200, -490]:
			_cast(kind)
			state.abilities.effects[-1]["started"] = started
	_cast(EffectType.FROST_NOVA, Vector2.ZERO, 0.0)
	_cast(EffectType.BEAM_WARNING, Vector2(5, 5), 8.0, Vector2(5, 5))
	var log := ErrorLog.new()
	OS.add_logger(log)
	renderer.queue_redraw()
	await wait_process_frames(2)
	OS.remove_logger(log)
	assert_eq(renderer.draw_stats["effects"], 38)
	assert_eq(log.errors, [], "no drawer errored")


func test_the_frost_spikes_reach_from_over_half_the_radius_to_past_it():
	assert_almost_eq(FxFrostNova.spike_reach(40.0, 0.0), 22.0, 0.001)
	assert_almost_eq(FxFrostNova.spike_reach(40.0, 1.0), 44.0, 0.001)
	var shard := FxFrostNova.shard(Vector2.ZERO, 0.0, 20.0)
	assert_eq(shard.size(), 4)
	assert_almost_eq(shard[0].x, 20.0, 0.001, "the tip on the reach")
	assert_almost_eq(shard[1].x, 7.0, 0.001, "the shoulder a third of the way out")
	assert_almost_eq(shard[1].y, 4.5, 0.001, "9 web px either side")
	assert_almost_eq(shard[2].x, 1.0, 0.001, "and the inner point just off the centre")


func test_the_rapier_drives_out_then_eases_back():
	assert_eq(FxRapierStab.blade_span(40.0, 0.0), Vector2(-18.0, 14.0), "starts drawn back")
	assert_eq(FxRapierStab.blade_span(40.0, 0.4), Vector2(20.0, 52.0), "fully driven out at 40%")
	assert_eq(FxRapierStab.blade_span(40.0, 1.0), Vector2(4.0, 22.0), "withdrawn toward the caster")
	assert_eq(FxRapierStab.pierce(0.2), 0.0, "nothing before the blade arrives")
	assert_eq(FxRapierStab.pierce(0.3), 1.0)
	assert_almost_eq(FxRapierStab.pierce(0.65), 0.5, 0.001)
	assert_eq(FxRapierStab.pierce(1.0), 0.0)


func test_the_low_swing_sweeps_across_the_first_half():
	assert_almost_eq(FxLowSwing.sweep_t(0.0), 0.0, 0.001)
	assert_almost_eq(FxLowSwing.sweep_t(0.275), 0.5, 0.001, "half-swept a quarter of the way in (across the first 55%)")
	assert_almost_eq(FxLowSwing.sweep_t(0.55), 1.0, 0.001, "fully swept by 55%")
	assert_almost_eq(FxLowSwing.sweep_t(0.9), 1.0, 0.001, "clamped after the cut has passed")


func test_the_disarm_slashes_stagger_and_the_impact_peaks():
	assert_almost_eq(FxDisarmFlourish.slash_t(0.1, 0), 0.4, 0.001)
	assert_eq(FxDisarmFlourish.slash_t(0.05, 1), -1.0, "the second slash hasn't started")
	assert_almost_eq(FxDisarmFlourish.slash_t(0.35, 1), 1.0, 0.001)
	assert_eq(FxDisarmFlourish.slash_t(0.6, 1), -1.0, "and is gone")
	assert_eq(FxDisarmFlourish.impact(0.2), 0.0, "no impact before 30%")
	assert_almost_eq(FxDisarmFlourish.impact(0.39), 0.6, 0.001)
	assert_almost_eq(FxDisarmFlourish.impact(0.45), 1.0, 0.001, "peaks near 45%")
	assert_eq(FxDisarmFlourish.impact(0.6), 0.0, "gone by 55%")


func test_the_ground_pound_waits_slams_and_rings_out():
	assert_eq(FxGroundPound.shock_radius(40.0, 0.1), 0.0, "no ring during the wind-up")
	assert_almost_eq(FxGroundPound.shock_radius(40.0, 0.286), 20.0, 0.001)
	assert_almost_eq(FxGroundPound.shock_radius(40.0, 1.0), 46.0, 0.001, "holds just past the radius")
	assert_eq(FxGroundPound.flash(0.1), 0.0)
	assert_almost_eq(FxGroundPound.flash(0.15), 1.0, 0.001, "flash on impact")
	assert_almost_eq(FxGroundPound.flash(0.285), 0.5, 0.001)
	assert_eq(FxGroundPound.flash(0.5), 0.0)


func test_the_roots_grow_to_the_radius_by_forty_five_percent():
	assert_almost_eq(FxDruidRoots.grow(0.25), 0.55, 0.001)
	assert_eq(FxDruidRoots.grow(0.5), 1.0)
	assert_almost_eq(FxDruidRoots.ensnare_radius(40.0, 0.0), 24.0, 0.001)
	var root := FxDruidRoots.tendril(Vector2.ZERO, 40.0, 0, 1.0, 0)
	assert_eq(root.size(), 10, "the centre and nine segments")
	# Tendril 0 runs along +x; at its tip the sway is sin(2.4 pi) * 5.
	assert_almost_eq(root[9].x, 40.0, 0.001)
	assert_almost_eq(root[9].y, 4.755, 0.001)


func test_the_moonlight_ring_opens_and_the_moon_breathes():
	assert_almost_eq(FxDruidMoonlight.ring_radius(40.0, 0.0), 14.0, 0.001)
	assert_almost_eq(FxDruidMoonlight.ring_radius(40.0, 0.25), 25.7, 0.001)
	assert_almost_eq(FxDruidMoonlight.ring_radius(40.0, 0.6), 40.0, 0.001, "full by 56%")
	assert_eq(FxDruidMoonlight.moon_px(0), 14.0)
	var mote := FxDruidMoonlight.mote(Vector2.ZERO, 40.0, 0, 0.5, 0)
	assert_almost_eq(mote[0].x, 8.0, 0.001, "mote 0 at a fifth of the radius")
	assert_almost_eq(mote[0].y, -11.0, 0.001, "risen 0.55 of half the radius")
	assert_almost_eq(mote[1], 0.988, 0.001)


func test_the_wild_surge_thorn_rings_rise_in_turn_and_sink_back():
	assert_eq(FxDruidWildSurge.thorn_height(0.0, 0), 0.0, "still underground")
	assert_almost_eq(FxDruidWildSurge.thorn_height(0.3, 0), 1.0, 0.001, "inner ring fully up")
	assert_eq(FxDruidWildSurge.thorn_height(0.1, 1), 0.0, "outer ring waits a beat")
	assert_almost_eq(FxDruidWildSurge.thorn_height(0.45, 1), 1.0, 0.001, "outer ring fully up")
	assert_eq(FxDruidWildSurge.thorn_height(0.8, 0), 0.0, "inner ring sunk")
	assert_gt(FxDruidWildSurge.thorn_height(0.8, 1), 0.0, "outer ring still sinking")


func test_the_beam_warning_is_a_flashing_band_from_boss_to_end():
	var band := FxBeamWarning.corners(Vector2.ZERO, Vector2(100, 0), 5.0)
	assert_eq(band.size(), 4)
	assert_eq(band[0], Vector2(0, 5))
	assert_eq(band[1], Vector2(100, 5))
	assert_eq(band[2], Vector2(100, -5))
	assert_eq(band[3], Vector2(0, -5))
	assert_eq(FxBeamWarning.corners(Vector2(3, 3), Vector2(3, 3), 5.0), [], "no length, no band")
	assert_eq(FxBeamWarning.half_width(0.5), 1.0, "never under 2 web px")
	assert_eq(FxBeamWarning.half_width(12.0), 12.0)
	assert_almost_eq(FxBeamWarning.pulse(0), 0.55, 0.001)
	assert_almost_eq(FxBeamWarning.pulse(131), 1.0, 0.001, "sin(1.572) peaks")
