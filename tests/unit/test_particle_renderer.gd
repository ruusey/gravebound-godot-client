extends GutTest

## Drawing the particle field, and the afterimage behind a shot.

var data: GameData
var state: RealmState
var renderer: WorldRenderer


func before_each():
	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(data, func() -> int: return 0)
	renderer = WorldRenderer.new()
	renderer.setup(state, data)
	add_child_autofree(renderer)


func _draw() -> void:
	renderer.queue_redraw()
	await wait_process_frames(2)


func test_the_particle_layer_sits_under_the_bullets():
	var order := renderer.get_children()
	assert_lt(order.find(renderer.particles), order.find(renderer.bullets), "fx under bodies")
	assert_gt(order.find(renderer.particles), order.find(renderer.entities), "and over the bodies and walls")
	assert_eq(renderer.particles.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "a soft dot sampled nearest is a stepped one")


func test_every_particle_in_view_is_drawn_and_the_rest_culled():
	state.particles.spawn(Vector2(10, 10), Vector2.ZERO, 1.0, 4.0, 4.0, Color.RED)
	state.particles.spawn(Vector2(20, 20), Vector2.ZERO, 1.0, 4.0, 4.0, Color.RED)
	state.particles.spawn(Vector2(5000, 5000), Vector2.ZERO, 1.0, 4.0, 4.0, Color.RED)
	await _draw()
	assert_eq(renderer.particles.drawn, 2)
	assert_eq(renderer.draw_stats["particles"], 2, "and the HUD can say so")


func test_a_bare_layer_draws_nothing():
	var bare := ParticleRenderer.new()
	bare.drawn = 9
	add_child_autofree(bare)
	bare.queue_redraw()
	await wait_process_frames(2)
	assert_eq(bare.drawn, 0)


func test_the_soft_dot_is_the_web_client_s_gradient_built_once():
	assert_eq(ParticleRenderer.alpha_at_distance(0.0), 1.0)
	assert_almost_eq(ParticleRenderer.alpha_at_distance(0.45), 0.55, 0.001)
	assert_almost_eq(ParticleRenderer.alpha_at_distance(0.225), 0.775, 0.001, "a straight ramp between stops")
	assert_eq(ParticleRenderer.alpha_at_distance(1.0), 0.0)
	assert_eq(ParticleRenderer.alpha_at_distance(1.5), 0.0)
	var dot := ParticleRenderer.soft_dot()
	assert_eq(dot.get_size(), Vector2(32, 32))
	var image := dot.get_image()
	assert_almost_eq(image.get_pixel(15, 15).a, 1.0, 0.05, "full at the centre")
	assert_eq(image.get_pixel(0, 0).a, 0.0, "gone in the corner")
	assert_same(ParticleRenderer.soft_dot(), dot, "one texture for every particle")


func test_a_group_with_a_trail_colour_is_drawn_five_times_behind_itself():
	# Fixture group 25 carries trailColor; 24 carries particle fx but no colour.
	state.projectiles.bullets[1] = Projectile.from_wire({"id": 1, "projectileId": 25, "size": 8,
		"pos": {"x": 10.0, "y": 10.0}, "angle": 0.0, "magnitude": 0.0, "range": 100.0, "flags": [],
		"invert": false, "timeStep": 0, "amplitude": 0, "frequency": 0, "orbitCenterX": 0.0,
		"orbitCenterY": 0.0, "orbitRadius": 0.0, "orbitPhase": 0.0, "damage": 1, "createdTime": 0}, 0)
	state.projectiles.bullets[2] = Projectile.from_wire({"id": 2, "projectileId": 24, "size": 8,
		"pos": {"x": 20.0, "y": 20.0}, "angle": 0.0, "magnitude": 0.0, "range": 100.0, "flags": [],
		"invert": false, "timeStep": 0, "amplitude": 0, "frequency": 0, "orbitCenterX": 0.0,
		"orbitCenterY": 0.0, "orbitRadius": 0.0, "orbitPhase": 0.0, "damage": 1, "createdTime": 0}, 0)
	await _draw()
	assert_eq(renderer.bullets.drawn, 2)
	assert_eq(renderer.bullets.afterimaged, 1)


func test_the_afterimage_trails_straight_back_along_the_heading():
	# Heading is (sin a, cos a): at angle 0 the shot flies down the screen,
	# so the copies sit above it, farthest first, smaller and dimmer.
	var copies := BulletAfterimage.plan(Vector2(100, 100), 20.0, 0.0, Color.RED)
	assert_eq(copies.size(), 5)
	assert_almost_eq(copies[0]["at"].y, 100.0 - 20.0 * 0.34 * 5, 0.001, "the fifth, 34% of the size apart")
	assert_almost_eq(copies[0]["at"].x, 100.0, 0.001)
	assert_almost_eq(copies[4]["at"].y, 100.0 - 20.0 * 0.34, 0.001, "the first is nearest")
	assert_almost_eq(copies[4]["size"], 20.0 * 0.88, 0.001, "12% smaller a copy")
	assert_almost_eq(copies[0]["size"], 20.0 * 0.4, 0.001)
	assert_almost_eq(copies[4]["colour"].a, 0.55 * 0.8, 0.001, "the nearest is the brightest")
	assert_eq(copies[0]["colour"].a, 0.0, "the farthest has faded out")
	assert_eq(copies[4]["colour"].r, 1.0, "the group's tint")
	var right := BulletAfterimage.plan(Vector2.ZERO, 10.0, PI * 0.5, Color.WHITE)
	assert_lt(right[4]["at"].x, 0.0, "a shot flying right trails to the left")
