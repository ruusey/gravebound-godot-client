extends GutTest

## The knight and warrior effects: each has a drawer, each draws through the
## real renderer at every phase, and their shapes' numbers are the web
## client's, spelled out from its cases.

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


## Cast one `progress` of the way through: the clock reads 500 and the
## effect lasts 1000.
func _cast_at(kind: int, progress: float, target := Vector2(30, 10), tier := 2) -> void:
	_cast(kind, Vector2.ZERO, 40.0, target, tier)
	state.abilities.effects[-1]["started"] = 500 - int(progress * 1000.0)


func test_each_knight_type_has_a_drawer():
	for kind in [EffectType.KNIGHT_SHOCKWAVE, EffectType.WARRIOR_BUFF, EffectType.SHIELD_DOME,
			EffectType.TAUNT_ROAR, EffectType.BRACE_STANCE, EffectType.WAR_CRY_WAVE,
			EffectType.BANNER_RAISE, EffectType.RAMPAGE_AURA]:
		assert_true(Fx.for_type(kind).is_valid(), "type %d" % kind)


func test_every_knight_drawer_draws_through_the_renderer_at_every_phase():
	# The bash through wind-up, thrust, slam, aftermath and its end, one
	# aimed on the caster, one far off; the rest at start, middle and end.
	for progress in [0.05, 0.3, 0.55, 0.8, 1.0]:
		_cast_at(EffectType.KNIGHT_SHOCKWAVE, progress)
	_cast_at(EffectType.KNIGHT_SHOCKWAVE, 0.55, Vector2.ZERO, 6)
	_cast_at(EffectType.KNIGHT_SHOCKWAVE, 0.55, Vector2(500, -300), 0)
	for kind in [EffectType.WARRIOR_BUFF, EffectType.SHIELD_DOME, EffectType.TAUNT_ROAR,
			EffectType.BRACE_STANCE, EffectType.WAR_CRY_WAVE, EffectType.BANNER_RAISE, EffectType.RAMPAGE_AURA]:
		for progress in [0.0, 0.1, 0.5, 1.0]:
			_cast_at(kind, progress)
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(renderer.draw_stats["effects"], 35)


func test_the_bash_reaches_the_aim_but_no_nearer_than_60_or_further_than_280_web_px():
	assert_almost_eq(FxKnightShockwave.reach(Vector2.ZERO, Vector2(30, 10)), 31.623, 0.001)
	assert_eq(FxKnightShockwave.reach(Vector2.ZERO, Vector2.ZERO), 30.0)
	assert_eq(FxKnightShockwave.reach(Vector2.ZERO, Vector2(500, 0)), 140.0)
	assert_eq(FxKnightShockwave.heading(Vector2(5, 5), Vector2(5, 5)), Vector2(1, 0), "aimed on the knight: east")
	assert_eq(FxKnightShockwave.heading(Vector2.ZERO, Vector2(0, -20)), Vector2(0, -1))


func test_the_chevrons_gather_behind_then_sweep_past_the_slam():
	assert_almost_eq(FxKnightShockwave.chevron_at(0.0, 0), -0.55, 0.0001)
	assert_almost_eq(FxKnightShockwave.chevron_at(0.06, 0), -0.60, 0.0001, "drifting back in the wind-up")
	assert_almost_eq(FxKnightShockwave.chevron_at(0.31, 0), 0.275, 0.0001, "halfway through an eased thrust")
	assert_almost_eq(FxKnightShockwave.chevron_at(0.2, 0), -0.43855, 0.0001, "smoothstep(0.2105): slow off the mark")
	assert_almost_eq(FxKnightShockwave.chevron_at(0.6, 2), 1.10, 0.0001, "held in front after")


func test_the_slam_peaks_at_the_thrusts_end_and_the_flash_straddles_it():
	assert_eq(FxKnightShockwave.slam_strength(0.1), 0.0)
	assert_almost_eq(FxKnightShockwave.slam_strength(0.31), 0.5, 0.0001)
	assert_almost_eq(FxKnightShockwave.slam_strength(0.5), 1.0, 0.0001)
	assert_almost_eq(FxKnightShockwave.slam_strength(0.6), 0.5, 0.0001)
	assert_almost_eq(FxKnightShockwave.slam_strength(0.7), 0.0, 0.0001)
	assert_eq(FxKnightShockwaveImpact.flash(0.5), 1.0)
	assert_almost_eq(FxKnightShockwaveImpact.flash(0.6), 0.5, 0.0001)
	assert_almost_eq(FxKnightShockwaveImpact.flash(0.35), 0.25, 0.0001)
	assert_almost_eq(FxKnightShockwaveImpact.flash(0.7), 0.0, 0.0001)
	assert_eq(FxKnightShockwaveImpact.flash(0.8), 0.0)


func test_the_aftermath_rings_chase_and_the_debris_flies_forward():
	assert_eq(FxKnightShockwaveAftermath.after(0.4), -1.0, "nothing before the thrust ends")
	assert_almost_eq(FxKnightShockwaveAftermath.after(0.75), 0.5, 0.0001)
	var early := FxKnightShockwaveAftermath.ring_radii(0.2)
	assert_eq(early, Vector2(25, 0), "30 + 20 web px; the second ring not yet out")
	var later := FxKnightShockwaveAftermath.ring_radii(0.5)
	assert_almost_eq(later.x, 40.0, 0.0001, "30 + 50 web px")
	assert_almost_eq(later.y, 23.1429, 0.0001, "24 + 78 * 0.2/0.7 web px")
	assert_eq(FxKnightShockwaveAftermath.debris_offset(Vector2.RIGHT, 0, 0.0), Vector2.ZERO)
	var flung := FxKnightShockwaveAftermath.debris_offset(Vector2.RIGHT, 0, 1.0)
	assert_almost_eq(flung.x, -39.598, 0.001, "112 web px out at -135 degrees")
	assert_almost_eq(flung.y, -32.598, 0.001, "plus 14 web px of sag")


func test_the_rally_grows_and_its_core_fades_from_35_percent():
	assert_eq(FxWarriorBuff.buff_radius(40.0, 0.0), 20.0)
	assert_almost_eq(FxWarriorBuff.buff_radius(40.0, 1.0), 42.0, 0.0001)
	assert_almost_eq(FxWarriorBuff.early_alpha(0.2), 0.8, 0.0001)
	assert_almost_eq(FxWarriorBuff.early_alpha(0.33), 0.67, 0.0001, "still just the fade at 33%")
	assert_almost_eq(FxWarriorBuff.early_alpha(0.675), 0.1625, 0.0001)
	assert_almost_eq(FxWarriorBuff.jag_radius(20.0, 0, 0), 18.4, 0.0001)


func test_the_dome_rims_sit_7_and_12_web_px_inside():
	assert_eq(FxShieldDome.rim_radii(40.0), [40.0, 36.5, 34.0])


func test_the_roar_waves_spread_and_the_brace_spreads():
	assert_eq(FxTauntRoar.wave_radius(40.0, 0.0), 10.0, "from a quarter of the radius")
	assert_almost_eq(FxTauntRoar.wave_radius(40.0, 0.5), 41.5, 0.001, "three quarters out by halfway")
	assert_almost_eq(FxTauntRoar.wave_radius(40.0, 1.0), 52.0, 0.001, "to 1.3 of it")
	var arcs := FxTauntRoar.wave_arcs(Vector2.ZERO, 10.0, 0.0)
	assert_eq(arcs.size(), 64, "four arcs of eight segments, as pairs")
	assert_almost_eq(arcs[0].angle(), -deg_to_rad(35.0), 0.001, "the first arc centred on the turn")
	assert_almost_eq(FxBraceStance.brace_radius(40.0, 0.0), 14.0, 0.0001)
	assert_almost_eq(FxBraceStance.brace_radius(40.0, 1.0), 52.0, 0.0001)
	assert_almost_eq(FxBraceStance.turn(1.0), 1.5708, 0.0001, "a quarter turn")


func test_the_war_cry_snaps_out_and_holds_to_65_percent():
	assert_almost_eq(FxWarCryWave.ring_radius(40.0, 0.25), 23.0, 0.0001)
	assert_almost_eq(FxWarCryWave.ring_radius(40.0, 1.0), 44.8, 0.0001, "stopped at 1.12")
	assert_eq(FxWarCryWave.strength(0.5), 1.0)
	assert_eq(FxWarCryWave.strength(0.62), 1.0, "still full at 62%")
	assert_almost_eq(FxWarCryWave.strength(0.825), 0.5, 0.0001)
	assert_eq(FxWarCryWave.strength(1.0), 0.0)


func test_the_banner_unfurls_and_the_aura_flickers():
	assert_almost_eq(FxBannerRaise.cloth_height(40.0, 0.25), 25.6, 0.0001)
	assert_almost_eq(FxBannerRaise.cloth_height(40.0, 1.0), 64.0, 0.0001)
	assert_almost_eq(FxBannerRaise.stomp_radius(40.0, 0.5), 28.0, 0.0001)
	assert_almost_eq(FxRampageAura.ignite(0.07), 0.5, 0.0001, "half way up the flash")
	assert_almost_eq(FxRampageAura.ignite(0.14), 1.0, 0.0001, "peaking at 40% of its 35%")
	assert_almost_eq(FxRampageAura.ignite(0.35), 0.0, 0.0001, "gone by 35%")
	assert_eq(FxRampageAura.ignite(0.5), 0.0)
