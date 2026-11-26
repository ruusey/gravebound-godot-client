extends GutTest

## The effects built for enemies: each draws through the real
## renderer across its life, as an area and as a line, and the numbers of
## its shape.

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


## Casts one as an enemy would (no owner) and sets it `progress` of the way
## through its second.
func _cast_at(kind: int, progress: float, radius := 48.0, target := Vector2(120, 30), tier := 0) -> void:
	state.apply_packet("CreateEffectPacket", {"effectType": kind, "posX": 0.0, "posY": 0.0,
		"radius": radius, "duration": 1000, "targetPosX": target.x, "targetPosY": target.y,
		"tier": tier, "ownerId": 0})
	state.abilities.effects[-1]["started"] = 500 - int(progress * 1000.0)


const KINDS := [EffectType.CONE_WARNING, EffectType.GROUND_CRACK, EffectType.ENRAGE_BURST,
	EffectType.SUMMON_PORTAL, EffectType.FIRE_PILLAR, EffectType.DUST_BURST, EffectType.EMERGE, EffectType.CIRCLE_WARNING]


func test_each_enemy_type_has_a_drawer():
	for kind in KINDS:
		assert_true(Fx.for_type(kind).is_valid(), EffectType.NAMES[kind])


func test_every_phase_of_every_type_draws_through_the_renderer():
	var log := ErrorLog.new()
	OS.add_logger(log)
	for kind in KINDS:
		for p in [0.0, 0.05, 0.2, 0.5, 0.8, 0.95]:
			state.abilities.effects.clear()
			for radius in [0.0, 48.0, 150.0]:
				_cast_at(kind, p, radius)
			assert_gt(await _drawn(), 0, "%s at %.2f" % [EffectType.NAMES[kind], p])
		# a line with no length, and the boss hue sentinels
		state.abilities.effects.clear()
		_cast_at(kind, 0.5, 30.0, Vector2.ZERO)
		for tier in [10, 11, 12]:
			_cast_at(kind, 0.5, 30.0, Vector2(120, 30), tier)
		assert_gt(await _drawn(), 0, EffectType.NAMES[kind])
	OS.remove_logger(log)
	assert_eq(log.errors, [], "no engine errors")


func _drawn() -> int:
	renderer.queue_redraw()
	await wait_process_frames(2)
	return renderer.draw_stats["effects"]


func test_cone_half_angle_defaults_and_clamps():
	assert_almost_eq(FxConeWarning.half_angle(0.0), deg_to_rad(30.0), 0.0001)
	assert_almost_eq(FxConeWarning.half_angle(45.0), deg_to_rad(45.0), 0.0001)
	assert_almost_eq(FxConeWarning.half_angle(2.0), deg_to_rad(5.0), 0.0001)
	assert_almost_eq(FxConeWarning.half_angle(170.0), deg_to_rad(85.0), 0.0001)


func test_cone_wedge_runs_from_apex_to_the_far_arc():
	var points := FxConeWarning.wedge(Vector2.ZERO, 0.0, 100.0, deg_to_rad(30.0))
	assert_eq(points.size(), FxConeWarning.STEPS + 2)
	assert_eq(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		assert_almost_eq((points[i] as Vector2).length(), 100.0, 0.001)


func test_crack_opens_then_fades():
	assert_eq(FxGroundCrack.opened(0.0), 0.0)
	assert_almost_eq(FxGroundCrack.opened(0.15), 0.5, 0.001)
	assert_eq(FxGroundCrack.opened(0.5), 1.0)
	assert_eq(FxGroundCrack.alpha_at(0.5), 1.0)
	assert_almost_eq(FxGroundCrack.alpha_at(0.8), 0.5, 0.001)
	assert_eq(FxGroundCrack.alpha_at(1.0), 0.0)


func test_crack_keeps_its_shape_and_ends_on_its_line():
	var fx := {"pos": Vector2(0, 0), "target": Vector2(200, 0), "started": 7}
	var first := FxGroundCrack.path(fx)
	assert_eq(first, FxGroundCrack.path(fx), "same jag every frame")
	assert_eq(first.size(), FxGroundCrack.SEGMENTS + 1)
	assert_almost_eq(first[0].y, 0.0, 0.001)
	assert_almost_eq(first[-1].y, 0.0, 0.001)


func test_enrage_ring_reaches_past_the_radius():
	assert_eq(FxEnrageBurst.ring_radius(100.0, 0.0), 0.0)
	assert_almost_eq(FxEnrageBurst.ring_radius(100.0, 1.0), 120.0, 0.001)


func test_portal_opens_holds_and_collapses():
	assert_eq(FxSummonPortal.openness(0.0), 0.0)
	assert_eq(FxSummonPortal.openness(0.5), 1.0)
	assert_almost_eq(FxSummonPortal.openness(1.0), 0.0, 0.001)
	assert_lt(FxSummonPortal.openness(0.1), 1.0)


func test_pillar_waits_for_its_tell_then_rises_and_burns_down():
	assert_eq(FxFirePillar.rise(0.1), 0.0, "the tell")
	assert_eq(FxFirePillar.rise(0.5), 1.0)
	assert_almost_eq(FxFirePillar.rise(1.0), 0.0, 0.001)
	assert_between(FxFirePillar.rise(0.2), 0.0, 1.0)


func test_pillar_tongue_tapers_to_one_tip():
	var points := FxFirePillar.tongue(Vector2.ZERO, 20.0, 100.0, 0, 0.0)
	assert_eq(points.size(), FxFirePillar.EDGE_POINTS * 2 + 1)
	var tip: Vector2 = points[FxFirePillar.EDGE_POINTS]
	assert_almost_eq(tip.y, -100.0, 0.001)


func test_dust_spreads_fast_then_settles():
	assert_eq(FxDustBurst.spread(0.0), 0.0)
	assert_eq(FxDustBurst.spread(1.0), 1.0)
	assert_gt(FxDustBurst.spread(0.3), 0.6)


func test_emerge_pit_opens_and_clods_land():
	assert_eq(FxEmerge.pit_radius(100.0, 0.0), 0.0)
	assert_almost_eq(FxEmerge.pit_radius(100.0, 0.5), 55.0, 0.001)
	assert_eq(FxEmerge.lift(0.0, 50.0), 0.0)
	assert_almost_eq(FxEmerge.lift(0.5, 50.0), 50.0, 0.001)
	assert_eq(FxEmerge.lift(1.0, 50.0), 0.0)


func test_circle_fills_from_the_centre_and_holds():
	assert_eq(FxCircleWarning.filled(0.0), 0.0)
	assert_almost_eq(FxCircleWarning.filled(0.5), 0.5, 0.001)
	assert_eq(FxCircleWarning.filled(1.0), 1.0)
	assert_eq(FxCircleWarning.filled(1.5), 1.0)
