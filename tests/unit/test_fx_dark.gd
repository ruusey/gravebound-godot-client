extends GutTest

## The necromancer's dark group -- vampirism, poison cloud, life drain,
## bone spikes, death pact, soul vortex, vampiric latch: their shapes'
## numbers, taken from the web client's cases, and that each draws without
## error through the real renderer.

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


func test_every_dark_type_has_its_own_drawer():
	for kind in [EffectType.VAMPIRISM, EffectType.POISON_CLOUD, EffectType.LIFE_DRAIN, EffectType.BONE_SPIKES,
			EffectType.DEATH_PACT_AURA, EffectType.SOUL_VORTEX, EffectType.VAMPIRIC_LATCH]:
		assert_true(Fx.for_type(kind).is_valid(), "type %d" % kind)


func test_every_dark_drawer_draws_through_the_renderer():
	# Each of the seven at the start, a third of the way and nearly gone
	# (the clock reads 500, the duration is 1000), then a vampirism too
	# small for its skull and one at the top tier. An error in any drawer
	# would abort the draw and the count would fall short.
	for started in [500, 150, -400]:
		for kind in [1, 22, 23, 24, 43, 45, 52]:
			_cast(kind)
			state.abilities.effects[-1]["started"] = started
	_cast(EffectType.VAMPIRISM, Vector2(5, 5), 10.0)
	_cast(EffectType.VAMPIRISM, Vector2(5, 5), 40.0, Vector2.ZERO, 6)
	renderer.queue_redraw()
	await wait_process_frames(2)
	assert_eq(renderer.draw_stats["effects"], 23)


func test_vampirism_motes_close_in_on_two_rings():
	assert_eq(FxVampirism.mote_distance(100.0, 0.0, 0), 100.0, "even motes on the outer ring")
	assert_almost_eq(FxVampirism.mote_distance(100.0, 0.0, 1), 79.0, 0.001, "odd ones at 0.4 + 0.6 * 0.65")
	assert_eq(FxVampirism.mote_distance(100.0, 0.5, 0), 50.0, "halfway in at half time")
	assert_almost_eq(FxVampirism.tendril_wobble(0.25, 0.0), 2.25, 0.001, "6 web px * 0.75 left, halved")
	assert_almost_eq(FxVampirism.tendril_wobble(1.0, 0.7), 0.0, 0.001, "still at the centre")
	assert_almost_eq(FxVampirism.skull_size(100.0, 0), 14.4, 0.001)
	assert_eq(FxVampirism.SKULL_MIN, 2.0, "no skull under 4 web px")
	assert_lt(FxVampirism.skull_size(10.0, 0), 2.0, "so a small drain has none")


func test_the_poison_cloud_bubbles_sit_inside_and_swell():
	assert_eq(FxPoisonCloud.bubble_distance(100.0, 0), 20.0)
	assert_almost_eq(FxPoisonCloud.bubble_distance(100.0, 1), 22.585, 0.001)
	assert_eq(FxPoisonCloud.bubble_px(0, 0), 4.0)
	assert_almost_eq(FxPoisonCloud.bubble_px(0, 1), 4.0 + 2.2 * sin(1.4), 0.001, "each index a beat further on")


func test_the_life_drain_streams_wind_inward():
	assert_eq(FxLifeDrain.stream_radius(100.0, 0.0), 102.0, "the rim plus 4 web px")
	assert_eq(FxLifeDrain.stream_radius(100.0, 1.0), 2.0)
	assert_almost_eq(FxLifeDrain.stream_angle(1, 0.5, 0), 4.0944, 0.001, "a third round, plus two radians")
	assert_almost_eq(FxLifeDrain.stream_angle(0, 0.0, 1000), 4.0, 0.001, "and four radians a second")


func test_the_bone_spikes_erupt_in_a_ring_and_sink():
	assert_eq(FxBoneSpikes.outer_count(48.0), 6)
	assert_eq(FxBoneSpikes.outer_count(200.0), 10)
	assert_eq(FxBoneSpikes.inner_count(48.0), 3)
	assert_eq(FxBoneSpikes.inner_count(200.0), 4)
	assert_almost_eq(FxBoneSpikes.spike_offset(100.0, 0), Vector2(0, -85), Vector2(0.001, 0.001),
		"the ring starts straight up, at 85%")
	assert_almost_eq(FxBoneSpikes.spike_offset(100.0, 10).length(), 40.0 * (1.0 + 0.08 * sin(29.0)), 0.001,
		"the inner ring at 40%")
	assert_almost_eq(FxBoneSpikes.spike_offset(100.0, 10).angle(), PI / 4.0, 0.001)
	assert_eq(FxBoneSpikes.delay(100.0, 10), 0.0, "the inner ones first")
	assert_almost_eq(FxBoneSpikes.delay(100.0, 5), 0.15, 0.001, "the ring sweeping round")
	assert_eq(FxBoneSpikes.rise(0.05, 0.06), 0.0, "not up yet")
	assert_almost_eq(FxBoneSpikes.rise(0.2, 0.06), 1.0 + 0.2 * sin(PI / 1.5), 0.001, "overshooting")
	assert_almost_eq(FxBoneSpikes.rise(0.5, 0.06), 1.0, 0.001, "settled")
	assert_almost_eq(FxBoneSpikes.rise(0.9, 0.06), 0.5, 0.001, "sinking")
	assert_almost_eq(FxBoneSpikes.spike_height(48.0, 0), 21.12, 0.001, "0.55 of the radius, the shortest")
	assert_almost_eq(FxBoneSpikes.spike_height(200.0, 0), 38.4, 0.001, "48 at most")
	var fang := FxBoneSpikes.fang(Vector2.ZERO, 4.0, 20.0, 0.0)
	assert_eq(fang.size(), 5)
	assert_eq(fang[2], Vector2(0, -20), "the tip")
	var order := FxBoneSpikes.depth_order(48.0)
	assert_eq(order.size(), 9)
	assert_eq(order[0], 0, "the top of the ring drawn first")


func test_the_death_pact_wisps_orbit_in_their_bands():
	assert_eq(FxDeathPactAura.wisp_orbit(100.0, 0), 40.0)
	assert_almost_eq(FxDeathPactAura.wisp_orbit(100.0, 1), 89.7, 0.001, "0.4 + 4.697 mod 0.6")


func test_the_death_pact_beats_twice_and_its_sigil_closes():
	assert_eq(FxDeathPactAura.heartbeat(0), 1.0, "the first thump")
	assert_almost_eq(FxDeathPactAura.heartbeat(225), 0.49, 0.001, "the softer second")
	assert_eq(FxDeathPactAura.heartbeat(450), 0.0, "quiet between beats")
	assert_eq(FxDeathPactAura.heartbeat(900), 1.0, "and again")
	assert_almost_eq(FxDeathPactAura.beat_phase(1350), 0.5, 0.001)
	var sigil := FxDeathPactAura.sigil(Vector2.ZERO, 10.0, 0.0)
	assert_eq(sigil.size(), 6, "five strokes, closed")
	assert_almost_eq(sigil[0], Vector2(0, -10), Vector2(0.001, 0.001), "point up")
	assert_almost_eq(sigil[5], sigil[0], Vector2(0.001, 0.001))


func test_the_soul_vortex_arms_sink_and_its_motes_cycle():
	assert_eq(FxSoulVortex.arm_radius(100.0, 0.0), 101.0, "the rim plus 2 web px")
	assert_almost_eq(FxSoulVortex.arm_radius(100.0, 1.0), 6.0, 0.001, "a twentieth of the radius plus 2 web px")
	assert_almost_eq(FxSoulVortex.mote_phase(0.0, 0), 0.137, 0.001)
	assert_almost_eq(FxSoulVortex.mote_phase(0.5, 1), 0.158, 0.001, "wraps past 1")
	assert_almost_eq(FxSoulVortex.mote_orbit(100.0, 0.0, 0), 35.946, 0.01)


func test_the_latch_tendrils_sway_more_toward_the_rim():
	assert_almost_eq(FxVampiricLatch.sway(0.0, 1.0 / 6.0), 0.5, 0.001, "6 web px * a sixth, halved")
	assert_almost_eq(FxVampiricLatch.sway(PI * 0.5, 1.0), -3.0, 0.001, "the full 6 web px at the rim")
	assert_almost_eq(FxVampiricLatch.sway(1.0, 0.0), 0.0, 0.001, "and none at the heart")
