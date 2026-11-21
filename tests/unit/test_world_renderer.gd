extends GutTest

## The renderer draws through a real (headless) canvas, so these exercise the
## actual _draw paths and assert on what survived culling.

var renderer: WorldRenderer
var state: RealmState
var data: GameData
var camera: Camera2D
var now := 10_000


func before_each():
	now = 10_000
	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(data, func() -> int: return now)

	renderer = WorldRenderer.new()
	renderer.setup(state, data)
	renderer.tiles.chunks.repaint_interval_ms = 0
	add_child_autofree(renderer)

	camera = Camera2D.new()
	add_child_autofree(camera)
	camera.make_current()


func after_each():
	renderer.queue_free()
	camera.queue_free()


func _render() -> void:
	renderer.queue_redraw()
	await wait_process_frames(2)


# --- structure -------------------------------------------------------------

func test_setup_stores_its_dependencies():
	assert_eq(renderer.state, state)
	assert_eq(renderer.game_data, data)


func test_there_is_a_node_per_layer_not_per_entity():
	# The whole point of immediate mode: a busier realm costs commands, not
	# nodes. Four layers whatever is on screen.
	state.local.id = 1
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(1, 0, 0, 0)]})
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(1, "me", Vector2.ZERO)],
		"enemies": [WireHelper.enemy(3, 1, Vector2(16, 16))],
	})
	await _render()
	var layers := renderer.get_child_count()
	assert_eq(layers, 8, "liquid, ground, entities, wall tops, particles, bullets, effects, the debug view")

	for i in 20:
		state.apply_packet("LoadPacket", {"enemies": [
			WireHelper.enemy(100 + i, 1, Vector2(i * 8, i * 8))]})
	await _render()
	assert_eq(renderer.get_child_count(), layers, "twenty more enemies, no more nodes")
	assert_gt(renderer.draw_stats["enemies"], 1, "and they are drawn")


func test_the_layers_stack_in_draw_order():
	# Child order is draw order. Nothing sets z_index: it is relative to the
	# parent on a CanvasItem, and a stray value is what once put a map layer
	# over the players.
	assert_eq(renderer.get_children(), [renderer.liquid, renderer.tiles, renderer.entities,
		renderer.wall_tops, renderer.particles, renderer.bullets, renderer.effects, renderer.debug])
	for layer in renderer.get_children():
		assert_eq(layer.z_index, 0, "%s leans on child order, not z_index" % layer)


func test_every_layer_samples_nearest_whatever_the_project_default():
	# The web export drew the zoomed world with linear filtering while the
	# unzoomed Controls stayed crisp; the layers say nearest themselves.
	assert_eq(renderer.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	for layer in renderer.get_children():
		# The one exception says so itself: a soft dot sampled nearest is a
		# stepped one, and the particle layer draws nothing else.
		if layer == renderer.particles:
			assert_eq(layer.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "particles")
			continue
		assert_eq(layer.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, layer.get_class())


func test_each_layer_carries_its_own_material():
	# The reason for the split: a shader on the ground must not touch the
	# characters standing on it, and the web client keeps bullets out of its
	# graded container for the same reason.
	var ground := CanvasItemMaterial.new()
	renderer.tiles.material = ground
	assert_eq(renderer.tiles.material, ground)
	assert_null(renderer.entities.material, "an effect on one layer stays there")
	# The bright overlays share one unlit material so the scene lights skip them.
	assert_eq(renderer.bullets.material.light_mode, CanvasItemMaterial.LIGHT_MODE_UNSHADED)
	for overlay in [renderer.particles, renderer.effects, renderer.debug]:
		assert_eq(overlay.material, renderer.bullets.material, "overlays share the unlit material")


func test_draw_is_a_no_op_without_state():
	var bare := WorldRenderer.new()
	add_child_autofree(bare)
	await _render()
	assert_eq(bare.draw_stats["tiles"], 0, "an unconfigured renderer draws nothing")


# --- tiles -----------------------------------------------------------------

func test_draws_tiles_in_view():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, 0, 0, 0), WireHelper.tile(2, 1, 0, 0), WireHelper.tile(3, 0, 1, 1),
	]})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 3, "all three are near the camera")


func test_culls_tiles_outside_the_view():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, 0, 0, 0), WireHelper.tile(1, 0, 5000, 5000),
	]})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 1, "the distant tile is culled")


func test_tiles_arrive_incrementally():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(1, 0, 0, 0)]})
	await _render()
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(1, 0, 5, 5)]})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 2, "a delta adds to what is already revealed")


func test_a_realm_change_clears_the_terrain():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, 0, 0, 0), WireHelper.tile(1, 0, 1, 0)]})
	await _render()
	state.apply_packet("LoadMapPacket", {"realmId": 2, "tiles": [WireHelper.tile(1, 0, 1, 1)]})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 1, "the old realm's tiles are gone")


func test_map_layers_draw_in_order():
	# Layer 1 must land on top of layer 0, not under it.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, 0, 0, 0), WireHelper.tile(2, 1, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 2)
	var layers: Array = state.tiles.layers.keys()
	layers.sort()
	assert_eq(layers, [0, 1], "the draw walks layers in ascending order")


func test_unknown_tile_id_falls_back_to_a_placeholder_and_warns_once():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(4242, 0, 0, 0), WireHelper.tile(4242, 0, 0, 1)]})
	await _render()
	await _render()
	assert_eq(renderer.tiles.missing_tiles.size(), 1,
		"one warning per unknown id, not per tile per frame")
	assert_eq(renderer.draw_stats["tiles"], 2, "placeholders are still drawn")


func test_void_tiles_are_not_drawn():
	# Tile id 0 is "no tile". The overlay layer is almost entirely void, so
	# drawing it paints black over the ground -- which is exactly what the
	# live nexus looked like before this.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, 0, 0, 0), WireHelper.tile(0, 1, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 1, "the ground tile only")


func test_a_void_overlay_does_not_hide_the_ground():
	var ground: Array = []
	var void_layer: Array = []
	for x in range(0, 4):
		for y in range(0, 4):
			ground.append(WireHelper.tile(1, 0, x, y))
			void_layer.append(WireHelper.tile(0, 1, x, y))
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": ground + void_layer})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 16, "16 ground cells, 16 voids skipped")


func test_real_tiles_on_the_overlay_layer_still_draw():
	# Walls live on the same layer as the void, and must not be skipped with it.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, 0, 0, 0), WireHelper.tile(0, 1, 0, 0),
		WireHelper.tile(61, 1, 1, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 2, "ground plus the wall, not the void")


func test_collision_overlay_can_be_toggled():
	state.apply_packet("LoadMapPacket", {"realmId": 1,
		"tiles": [WireHelper.tile(2, GameConstants.COLLISION_LAYER, 0, 0)]})
	renderer.show_collision = true
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 1, "the overlay draws on top of the tile")
	renderer.show_collision = false
	await _render()
	assert_eq(renderer.draw_stats["tiles"], 1)


# --- entities --------------------------------------------------------------

func test_draws_every_entity_kind():
	state.local.id = 1
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(1, "me", Vector2.ZERO), WireHelper.player(2, "you", Vector2(16, 16))],
		"enemies": [WireHelper.enemy(3, 1, Vector2(32, 32))],
		"containers": [{"lootContainerId": 5, "items": [], "pos": {"x": 4.0, "y": 4.0}}],
		"portals": [{"id": 6, "portalId": 1, "toRealmId": 2, "pos": {"x": 12.0, "y": 12.0}}],
	})
	state.projectiles.bullets[9] = Projectile.from_wire({
		"id": 9, "projectileId": 10, "size": 8, "pos": {"x": 8.0, "y": 8.0},
		"angle": 0.0, "magnitude": 5.0, "range": 100.0, "flags": []}, now)
	await _render()

	assert_eq(renderer.draw_stats["players"], 2)
	assert_eq(renderer.draw_stats["enemies"], 1)
	assert_eq(renderer.draw_stats["containers"], 1)
	assert_eq(renderer.draw_stats["portals"], 1)
	assert_eq(renderer.draw_stats["bullets"], 1)


func test_ground_entities_are_drawn_back_to_front():
	# The queue is the draw order. A 16px enemy standing at y=100 has its feet
	# at 116; a 32px player at y=90 has its feet at 122, so the player is
	# nearer the viewer and must draw last.
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(2, "you", Vector2(0, 90))],
		"enemies": [WireHelper.enemy(3, 1, Vector2(0, 100))],
	})
	var order := _draw_order()
	assert_eq(order, ["enemies", "players"], "the lower feet draw later, on top")


func test_sorting_uses_the_feet_not_the_top_left():
	# Top-left order would put the player (y=90) behind the enemy (y=100) and
	# draw it first; sorting on the feet reverses that.
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(2, "you", Vector2(0, 90))],
		"enemies": [WireHelper.enemy(3, 1, Vector2(0, 95))],
	})
	var queue := _queue()
	assert_eq(queue[0]["pos"].y, 95.0, "enemy feet 111")
	assert_eq(queue[1]["pos"].y, 90.0, "player feet 122 draws in front")


func test_remote_entities_are_culled():
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(2, "far", Vector2(9000, 9000))],
		"enemies": [WireHelper.enemy(3, 1, Vector2(9000, 9000))],
		"containers": [{"lootContainerId": 5, "items": [], "pos": {"x": 9000.0, "y": 9000.0}}],
		"portals": [{"id": 6, "pos": {"x": 9000.0, "y": 9000.0}}],
	})
	state.projectiles.bullets[9] = Projectile.from_wire({
		"id": 9, "projectileId": 10, "size": 8, "pos": {"x": 9000.0, "y": 9000.0},
		"angle": 0.0, "magnitude": 0.0, "range": 100.0, "flags": []}, now)
	await _render()
	for key in ["players", "enemies", "bullets", "containers", "portals"]:
		assert_eq(renderer.draw_stats[key], 0, "%s far from the camera are culled" % key)


func test_local_player_is_always_drawn_even_off_camera():
	# Drawn at its predicted position regardless of the view rect, so the
	# camera can never lose you.
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.position = Vector2(9000, 9000)
	await _render()
	assert_eq(renderer.draw_stats["players"], 1)


func test_the_local_player_follows_its_predicted_position():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.position = Vector2(64, 64)
	var queue := _queue()
	assert_eq(queue[0]["pos"], Vector2(64, 64), "not the interpolated roster position")


func test_enemy_without_a_sprite_falls_back_to_a_block():
	state.apply_packet("LoadPacket", {"enemies": [WireHelper.enemy(3, 9999, Vector2.ZERO)]})
	await _render()
	assert_eq(renderer.draw_stats["enemies"], 1, "a content gap still draws something")


func test_moving_remote_player_uses_the_walk_clip():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "you", Vector2.ZERO)]})
	state.apply_packet("ObjectMovePacket", {"movements": [
		{"entityId": 2, "entityType": 0, "posX": 4.0, "posY": 0.0,
			"velX": 1.0, "velY": 0.0, "flags": 0}]})
	await _render()
	assert_eq(renderer.draw_stats["players"], 1)


func test_player_without_an_animation_set_falls_back_to_a_block():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "you", Vector2.ZERO, 0, 404)]})
	await _render()
	assert_eq(renderer.draw_stats["players"], 1)


func test_walking_left_mirrors_the_local_sprite():
	# The sheet has no left-facing clip, so walking left is the side clip
	# mirrored. Driven through face_toward, the same path a held key takes.
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.moving = true

	state.local.face_toward(Vector2.LEFT)
	assert_eq(state.local.facing, "side")
	assert_true(_queue()[0]["flip"], "walking left mirrors the sprite")

	state.local.face_toward(Vector2.RIGHT)
	assert_false(_queue()[0]["flip"], "walking right draws it as authored")


func test_a_mirrored_player_is_drawn():
	# Exercises the mirror draw path, not just the flip flag: mirroring goes
	# through a scale transform, because draw_texture_rect's last argument is
	# `transpose` and a negative-width rect displaces the sprite.
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.moving = true
	state.local.face_toward(Vector2.LEFT)
	await _render()
	assert_eq(renderer.draw_stats["players"], 1, "drawn, mirrored, without error")


func test_a_mirrored_player_without_art_still_draws_its_block():
	state.local.id = 1
	state.local.class_id = 404
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO, 0, 404)]})
	state.local.moving = true
	state.local.face_toward(Vector2.LEFT)
	await _render()
	assert_eq(renderer.draw_stats["players"], 1, "the placeholder mirrors too")


func test_vertical_movement_does_not_mirror():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.moving = true
	state.local.face_toward(Vector2.LEFT)
	state.local.face_toward(Vector2.DOWN)
	assert_eq(state.local.facing, "front")
	assert_false(_queue()[0]["flip"], "a front-facing clip is never mirrored")


func _move_remote(id: int, velocity: Vector2) -> void:
	state.apply_packet("ObjectMovePacket", {"movements": [{
		"entityId": id, "entityType": 0, "posX": 0.0, "posY": 0.0,
		"velX": velocity.x, "velY": velocity.y, "flags": 0}]})
	state.advance(RealmState.TICK_DELTA, Vector2.ZERO, 0.0)


func test_a_remote_player_faces_where_it_is_going():
	# Both reference clients derive facing from velocity for every player,
	# not just the local one; ours used to draw every remote front-facing.
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "you", Vector2.ZERO)]})
	_move_remote(2, Vector2(-1, 0))
	var queue := _queue()
	assert_true(queue[0]["flip"], "walking left mirrors a remote too")

	_move_remote(2, Vector2(0, 1))
	assert_false(_queue()[0]["flip"], "front-facing clips are never mirrored")


func test_a_stopped_remote_keeps_its_last_facing():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "you", Vector2.ZERO)]})
	_move_remote(2, Vector2(-1, 0))
	_move_remote(2, Vector2.ZERO)
	assert_true(_queue()[0]["flip"], "settles facing the way it was walking")


func test_the_local_mirror_does_not_leak_onto_remotes():
	# Each player carries its own facing; a mirrored local must not flip a
	# remote that has never moved.
	state.local.face_toward(Vector2.LEFT)
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "you", Vector2.ZERO)]})
	assert_false(_queue()[0]["flip"], "the local mirror must not leak onto others")


func test_a_turning_enemy_is_rotated_instead_of_mirrored():
	data.library.enemies[1]["rotateToMotion"] = true
	state.apply_packet("LoadPacket", {"enemies": [WireHelper.enemy(3, 1, Vector2.ZERO)]})
	_move_remote_enemy(3, Vector2(-2, 0))
	var item: Dictionary = _queue()[0]
	assert_false(item["flip"], "a turning body never mirrors")
	assert_true(item.has("rotation"))
	await _render()
	assert_eq(renderer.draw_stats["enemies"], 1, "drawn rotated without error")


func test_an_ordinary_enemy_is_not_rotated():
	state.apply_packet("LoadPacket", {"enemies": [WireHelper.enemy(3, 1, Vector2.ZERO)]})
	_move_remote_enemy(3, Vector2(0, 2))
	assert_false(_queue()[0].has("rotation"), "mirrored as usual, not turned")


func test_a_higher_draw_layer_draws_over_lower_feet():
	# A flyer high on the screen still covers a walker standing below it.
	data.library.enemies[2]["drawLayer"] = 1
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(2, "you", Vector2(0, 120))],
		"enemies": [WireHelper.enemy(3, 2, Vector2(0, 0)), WireHelper.enemy(4, 1, Vector2(0, 100))],
	})
	var order: Array = []
	for item in _queue():
		order.append(item["pos"].y)
	assert_eq(order, [100.0, 120.0, 0.0], "the layered enemy draws last")


func _move_remote_enemy(id: int, velocity: Vector2) -> void:
	state.apply_packet("ObjectMovePacket", {"movements": [{
		"entityId": id, "entityType": 1, "posX": 0.0, "posY": 0.0,
		"velX": velocity.x, "velY": velocity.y, "flags": 0}]})
	state.advance(RealmState.TICK_DELTA, Vector2.ZERO, 0.0)


func test_bullets_with_a_sprite_are_drawn_rotated():
	# Group 10 exists in the fixture content, so this takes the textured path
	# rather than the placeholder circle.
	state.projectiles.bullets[1] = Projectile.from_wire({
		"id": 1, "projectileId": 10, "size": 8, "pos": {"x": 0.0, "y": 0.0},
		"angle": 1.0, "magnitude": 5.0, "range": 100.0, "flags": []}, now)
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 1)


func test_bullets_without_a_sprite_fall_back_to_a_circle():
	state.projectiles.bullets[2] = Projectile.from_wire({
		"id": 2, "projectileId": 9999, "size": 8, "pos": {"x": 0.0, "y": 0.0},
		"angle": 0.0, "magnitude": 5.0, "range": 100.0, "flags": []}, now)
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 1)


func _wall(id: int, position: Vector2, length: int, flags: Array) -> void:
	state.projectiles.bullets[id] = Projectile.from_wire({
		"id": id, "projectileId": 10, "size": 16,
		"pos": {"x": position.x, "y": position.y}, "angle": 0.0,
		"magnitude": 0.0, "range": 100.0, "flags": flags, "length": length}, now)


func test_a_melee_swing_draws_nothing():
	# An invisible area effect: the wielder's swing animation stands in for
	# it, and both reference clients skip the sprite.
	_wall(1, Vector2.ZERO, 0, [ProjectileKind.MELEE_SWING])
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 0)


func test_a_line_segment_wall_is_drawn():
	_wall(1, Vector2.ZERO, 96, [ProjectileKind.LINE_SEGMENT])
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 1, "one bullet, however many tiles it stacks")


func test_a_wall_anchored_offscreen_still_draws_its_body():
	# The anchor is the centre; a long wall can reach well into view from
	# outside it, so the cull has to allow for the span.
	var view := ViewRect.of(renderer)
	_wall(1, Vector2(view.end.x + 40.0, 0.0), 400, [ProjectileKind.LINE_SEGMENT])
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 1)


func test_a_short_projectile_offscreen_is_still_culled():
	var view := ViewRect.of(renderer)
	_wall(1, Vector2(view.end.x + 40.0, 0.0), 0, [])
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 0)


func test_expired_bullets_stop_being_drawn():
	state.projectiles.bullets[1] = Projectile.from_wire({
		"id": 1, "projectileId": 10, "size": 8, "pos": {"x": 0.0, "y": 0.0},
		"angle": 0.0, "magnitude": 5.0, "range": 1.0, "flags": []}, now)
	await _render()
	state.projectiles.advance(GameConstants.TICK_DELTA)
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 0)


# --- overlay ---------------------------------------------------------------

func test_the_overlay_draws_names_and_health_bars():
	state.local.id = 1
	state.local.name = "Ruu"
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(1, "", Vector2.ZERO), WireHelper.player(2, "You", Vector2(20, 20))],
		"enemies": [WireHelper.enemy(3, 1, Vector2(40, 40), 0, 30)],
	})
	await _render()
	assert_eq(renderer.draw_stats["players"], 2, "labels draw above the world without error")


func test_a_full_health_enemy_gets_no_bar():
	state.apply_packet("LoadPacket", {"enemies": [WireHelper.enemy(3, 1, Vector2.ZERO, 0, 100)]})
	await _render()
	assert_eq(renderer.draw_stats["enemies"], 1, "full health: no bar, still drawn")


func test_a_player_with_no_name_gets_no_label():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "", Vector2.ZERO)]})
	await _render()
	assert_eq(renderer.draw_stats["players"], 1, "an unnamed remote player draws no label")


func test_distant_labels_and_bars_are_skipped():
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(2, "Far", Vector2(9000, 9000))],
		"enemies": [WireHelper.enemy(3, 1, Vector2(9000, 9000), 0, 10)],
	})
	await _render()
	assert_eq(renderer.draw_stats["players"], 0)


# --- view rect -------------------------------------------------------------

func test_the_view_rect_follows_the_camera():
	camera.position = Vector2(1000, 1000)
	await wait_process_frames(2)
	var view := ViewRect.of(renderer)
	assert_true(view.has_point(Vector2(1000, 1000)), "the camera centre is in view")
	assert_false(view.has_point(Vector2(9000, 9000)))


func test_zoom_widens_the_view_rect():
	camera.zoom = Vector2(1, 1)
	await wait_process_frames(2)
	var wide := ViewRect.of(renderer).size
	camera.zoom = Vector2(4, 4)
	await wait_process_frames(2)
	var narrow := ViewRect.of(renderer).size
	assert_lt(narrow.x, wide.x, "zooming in shows less world")


# --- helpers ---------------------------------------------------------------

## The queue the ground pass would draw this frame, in draw order.
func _queue() -> Array:
	return renderer.entities.queue.build(state, data, ViewRect.of(renderer))


func _draw_order() -> Array:
	var order: Array = []
	for item in _queue():
		order.append(item["kind"])
	return order


func test_a_status_effect_tints_the_local_player():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	assert_eq(_queue()[0]["modulate"], StatusTint.CLEAR, "untouched to begin with")

	state.apply_packet("PlayerStatePacket", {
		"playerId": 1, "health": 100, "mana": 10,
		"effectIds": [StatusTint.POISONED], "effectTimes": [], "effectStacks": []})
	assert_eq(_queue()[0]["modulate"], StatusTint.of([StatusTint.POISONED]))


func test_a_status_effect_tints_a_remote_player():
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(2, "you", Vector2.ZERO)]})
	state.apply_packet("PlayerStatePacket", {
		"playerId": 2, "health": 100, "mana": 10,
		"effectIds": [StatusTint.CURSED], "effectTimes": [], "effectStacks": []})
	assert_eq(_queue()[0]["modulate"], StatusTint.of([StatusTint.CURSED]))


func test_one_player_s_effect_does_not_tint_another():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [
		WireHelper.player(1, "me", Vector2.ZERO), WireHelper.player(2, "you", Vector2(40, 0))]})
	state.apply_packet("PlayerStatePacket", {
		"playerId": 1, "health": 100, "mana": 10,
		"effectIds": [StatusTint.BERSERK], "effectTimes": [], "effectStacks": []})
	var tinted := 0
	for item in _queue():
		if item["modulate"] != StatusTint.CLEAR:
			tinted += 1
	assert_eq(tinted, 1, "the effect belongs to one of them")


# --- seam feathering --------------------------------------------------------

func _terrain_pair(a: int, b: int) -> void:
	# Two columns of different base tiles, so the shared edge is a seam.
	var tiles: Array = []
	for y in range(0, 3):
		tiles.append(WireHelper.tile(a, 0, 0, y))
		tiles.append(WireHelper.tile(b, 0, 1, y))
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": tiles})


func test_a_seam_between_two_terrains_is_feathered():
	_terrain_pair(1, 3)
	await _render()
	assert_gt(renderer.draw_stats["feathers"], 0, "the shared edge gets a fringe from each side")


func test_one_terrain_has_no_seams():
	_terrain_pair(1, 1)
	await _render()
	assert_eq(renderer.draw_stats["feathers"], 0, "nothing to blend against itself")


func test_a_wall_edge_is_never_feathered():
	# Walls are architectural boundaries; softening them reads as mush, so
	# both reference clients skip blending on and into a wall cell.
	_terrain_pair(1, 3)
	var walls: Array = []
	for y in range(0, 3):
		walls.append(WireHelper.tile(6, GameConstants.COLLISION_LAYER, 1, y))
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": walls})
	await _render()
	assert_eq(renderer.draw_stats["feathers"], 0, "the wall column blocks the seam")


func test_near_identical_neighbours_are_left_alone():
	# Blending two tiles of the same material gains nothing and only muddies
	# them, so the colour gate holds them apart.
	_terrain_pair(1, 8)
	await _render()
	assert_eq(renderer.draw_stats["feathers"], 0)


func test_a_tile_that_opts_out_is_never_feathered():
	_terrain_pair(1, 7)
	await _render()
	assert_eq(renderer.draw_stats["feathers"], 0, "noBlend, like carpet")


func test_an_island_is_feathered_on_all_four_sides():
	var tiles: Array = []
	for x in range(0, 3):
		for y in range(0, 3):
			tiles.append(WireHelper.tile(1, 0, x, y))
	tiles.append(WireHelper.tile(3, 0, 1, 1))
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": tiles})
	await _render()
	assert_gte(renderer.draw_stats["feathers"], 8,
		"four fringes onto the island and four back off it")


func test_terrain_with_no_base_layer_feathers_nothing():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(6, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["feathers"], 0)


func test_a_horde_is_outlined_whole():
	# The silhouette is drawn by the bullet shader in the same instanced draw as
	# the body, so it costs nothing per shot and no budget stops it.
	var wanted := BulletRenderer.OUTLINE_BUDGET + 20
	for i in wanted:
		state.projectiles.bullets[i] = Projectile.from_wire({
			"id": i, "projectileId": 10, "size": 8, "pos": {"x": 0.0, "y": 0.0},
			"angle": 0.0, "magnitude": 0.0, "range": 500.0, "flags": []}, now)
	await _render()
	assert_eq(renderer.draw_stats["bullets"], wanted, "every projectile is drawn")
	assert_eq(renderer.bullets.outlined, wanted, "every one has its silhouette")


# --- tall wall depth --------------------------------------------------------

func test_a_tall_wall_has_its_top_face_stamped_over_the_entities():
	# Wall art is 8x16: the tile pass draws the whole sprite below the
	# entities, and the top square is repeated above them so a character
	# standing behind the wall is covered by it.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(6, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["wall_tops"], 1)


func test_a_short_wall_is_not_stamped_again():
	# Nothing spills south from a square tile, so nothing needs covering.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(2, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["wall_tops"], 0)


func test_the_top_face_is_the_upper_square_of_the_tall_cell():
	# Row stride stays the full 16px cell; the region is the 8px square at its
	# top. Taking the whole cell here would paint the front face over the
	# entity standing in front of it.
	var face := data.tile_top_face(6)
	assert_not_null(face)
	assert_eq(face.region, Rect2(0, 16, 8, 8))


func test_terrain_alone_stamps_nothing():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(1, 0, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["wall_tops"], 0)


# --- ground shadows ---------------------------------------------------------

func test_everything_on_the_ground_stands_on_a_shadow():
	state.local.id = 1
	state.apply_packet("LoadPacket", {
		"players": [WireHelper.player(1, "me", Vector2.ZERO)],
		"enemies": [WireHelper.enemy(3, 1, Vector2(16, 16))],
	})
	await _render()
	assert_eq(renderer.draw_stats["shadows"], 2, "one per entity in the queue")


func test_a_prop_casts_a_shadow():
	# A collision tile that is not a wall: an anvil, a table, a torch.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(9, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["object_shadows"], 1)


func test_a_wall_casts_none():
	# Architecture, not something resting on the floor. Both references skip
	# walls here, and a tall one already carries its own front face.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(6, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["object_shadows"], 0)


func test_decoration_casts_none():
	# No collision at all: it lies flat on the ground rather than standing on it.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["object_shadows"], 0)


func test_nothing_casts_a_shadow_onto_a_liquid():
	# A shadow on the surface of water reads as a hole in it.
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(3, 0, 0, 0),
		WireHelper.tile(9, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["object_shadows"], 0)


func test_the_same_prop_on_dry_ground_does():
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [
		WireHelper.tile(1, 0, 0, 0),
		WireHelper.tile(9, GameConstants.COLLISION_LAYER, 0, 0)]})
	await _render()
	assert_eq(renderer.draw_stats["object_shadows"], 1)


func test_a_sizeless_entity_draws_no_shadow():
	# Size arrives on the wire, so nothing stops the server sending a zero.
	# An ellipse of no width is a stray draw command, not a shadow.
	var enemy := WireHelper.enemy(3, 1, Vector2.ZERO)
	enemy["size"] = 0
	state.apply_packet("LoadPacket", {"enemies": [enemy]})
	await _render()
	assert_eq(renderer.draw_stats["enemies"], 1, "the body is still drawn")
	assert_eq(renderer.draw_stats["shadows"], 0, "queued, but nothing stamped")


# --- attack animation -------------------------------------------------------

func test_a_shooting_player_plays_its_attack_clip():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.attack.begin(Vector2.RIGHT)
	var item: Dictionary = _queue()[0]
	assert_eq(item["texture"], data.classes_art.frame(
		state.local.class_id, "attack", "side", 0))


func test_a_swing_overrides_the_walk_clip():
	# Both references let the attack win: a player who shoots while running
	# swings rather than keeping their legs on screen.
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.moving = true
	state.local.face_toward(Vector2.DOWN)
	var walking: Dictionary = _queue()[0]

	state.local.attack.begin(Vector2.RIGHT)
	var swinging: Dictionary = _queue()[0]
	assert_ne(swinging["texture"], walking["texture"])


func test_a_swing_faces_the_shot_not_the_feet():
	# A stationary shooter has no movement direction to face, and one running
	# away while shooting backwards must still swing backwards.
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.face_toward(Vector2.RIGHT)
	assert_false(state.local.facing_left)

	state.local.attack.begin(Vector2.LEFT)
	assert_true(_queue()[0]["flip"], "the swing mirrors, though the feet do not")


func test_the_pose_expires_back_to_idle():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.attack.begin(Vector2.RIGHT)
	state.local.attack.tick(AttackPose.DURATION + 0.01)
	assert_eq(_queue()[0]["texture"], data.classes_art.frame(
		state.local.class_id, "idle", state.local.facing, 0))


# --- projectile spin --------------------------------------------------------

func test_an_additive_spin_turns_on_top_of_the_heading():
	# The fan of a volley survives: each bullet keeps its own heading and the
	# spin is added to all of them equally.
	var still := BulletRenderer.rotation_for(0.5, 0.25, 0.0, true)
	assert_almost_eq(BulletRenderer.rotation_for(0.5, 0.25, 1.0, true),
		still + 1.0, 0.0001)


func test_a_continuous_spin_replaces_the_heading():
	# A shuriken does not point where it is going, so two bullets on opposite
	# headings must draw at the same angle.
	assert_almost_eq(BulletRenderer.rotation_for(0.5, 0.25, 1.0, false), 1.0, 0.0001)
	assert_almost_eq(BulletRenderer.rotation_for(-2.0, 0.9, 1.0, false), 1.0, 0.0001)


func test_no_spin_leaves_the_heading_alone():
	# The existing rule: -angle + PI/2 + angleOffset.
	assert_almost_eq(BulletRenderer.rotation_for(0.5, 0.25, 0.0, true),
		-0.5 + PI * 0.5 + 0.25, 0.0001)


func test_a_spinning_bullet_draws_through_the_spin_path():
	# Group 20 carries an additive spin, so this exercises the lookup and the
	# clock as well as the maths above.
	renderer.bullets.clock = func() -> int: return 1000
	state.projectiles.bullets[9] = Projectile.from_wire({
		"id": 9, "projectileId": 20, "size": 8, "pos": {"x": 8.0, "y": 8.0},
		"angle": 0.0, "magnitude": 5.0, "range": 100.0, "flags": []}, now)
	await _render()
	assert_eq(renderer.draw_stats["bullets"], 1)
	assert_false(data.projectiles_art.spin(20).is_empty(), "and really does spin")


# --- overhanging attack frames ----------------------------------------------

func test_a_square_frame_draws_at_the_body_size():
	var square := data.classes_art.frame(0, "walk", "side", 0)
	assert_eq(EntityQueue.frame_size(square, 8, 32.0), Vector2(32.0, 32.0))


func test_a_double_width_frame_draws_twice_as_wide():
	# The second attack_side frame is 16 wide on an 8 cell: the weapon
	# overhangs the body. Squashing it back into the cell is what made a
	# sideways swing look compressed.
	var wide := data.classes_art.frame(0, "attack", "side", 1)
	assert_eq(wide.region.size, Vector2(16, 8), "the fixture really is wide")
	assert_eq(EntityQueue.frame_size(wide, 8, 32.0), Vector2(64.0, 32.0))


func test_a_missing_frame_falls_back_to_the_body():
	assert_eq(EntityQueue.frame_size(null, 8, 32.0), Vector2(32.0, 32.0))
	assert_eq(EntityQueue.frame_size(data.classes_art.frame(0, "walk", "side", 0), 0, 32.0),
		Vector2(32.0, 32.0), "and so does a class with no cell size")


func test_the_queue_carries_the_overhang():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	state.local.attack.begin(Vector2.RIGHT)
	state.local.attack.tick(AttackPose.FRAME_SECONDS * 1.5)
	var item: Dictionary = _queue()[0]
	assert_gt(item["draw"].x, float(item["size"]), "the swing is wider than the body cell")
	assert_eq(item["draw"].y, float(item["size"]), "but no taller")


func test_an_idle_player_does_not_overhang():
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	var item: Dictionary = _queue()[0]
	assert_eq(item["draw"], Vector2.ONE * float(item["size"]))


func test_an_unmirrored_overhang_extends_right_from_the_cell():
	# Body cell at x=100 spanning 32; a 64-wide frame keeps its left edge on
	# the cell and hangs off to the right.
	var rect := EntityRenderer.frame_rect(Vector2(100.0, 50.0), 32.0, Vector2(64.0, 32.0), false)
	assert_eq(rect.position.x, 100.0)
	assert_eq(rect.end.x, 164.0)


func test_a_mirrored_overhang_extends_left_from_the_cell():
	# The same frame flipped keeps its *right* edge on the cell instead, so
	# the weapon reaches out in front of the character rather than behind it.
	var rect := EntityRenderer.frame_rect(Vector2(100.0, 50.0), 32.0, Vector2(64.0, 32.0), true)
	assert_eq(rect.end.x, 132.0, "the cell's right edge")
	assert_eq(rect.position.x, 68.0)


func test_a_taller_frame_grows_upward_from_the_feet():
	# Anchored by the bottom of the cell: the feet stay put and the extra
	# height goes over the character's head.
	var rect := EntityRenderer.frame_rect(Vector2(100.0, 50.0), 32.0, Vector2(32.0, 64.0), false)
	assert_eq(rect.end.y, 82.0, "the cell's bottom edge, unmoved")
	assert_eq(rect.position.y, 18.0)


func test_a_plain_frame_fills_its_cell():
	for flip in [false, true]:
		assert_eq(EntityRenderer.frame_rect(Vector2(100.0, 50.0), 32.0, Vector2(32.0, 32.0), flip),
			Rect2(100.0, 50.0, 32.0, 32.0), "flip=%s" % flip)


# --- portals ---------------------------------------------------------------

func test_a_portal_draws_its_own_art_a_tile_wide():
	state.apply_packet("LoadPacket", {
		"portals": [WireHelper.portal(6, 1, Vector2(12, 12))]})
	var item: Dictionary = _queue()[0]
	assert_eq(item["kind"], "portals")
	assert_eq(item["size"], GameConstants.TILE_SIZE, "both references give it a full tile")
	assert_eq(item["draw"], Vector2.ONE * float(GameConstants.TILE_SIZE))
	# Asserted before the region is read: a null texture would otherwise throw
	# inside the assertion, and GUT counts a test that errored as passing.
	assert_not_null(item["texture"], "a defined portal draws its art, not a block")
	if item["texture"] != null:
		assert_eq(item["texture"].region, Rect2(16, 24, 8, 8), "portal 1's cell in portals.json")


func test_a_portal_the_content_does_not_define_falls_back_to_a_block():
	state.apply_packet("LoadPacket", {
		"portals": [WireHelper.portal(6, 404, Vector2(12, 12))]})
	assert_null(_queue()[0]["texture"],
		"a missing definition shows as a block, not an invisible doorway")


func test_the_far_portal_is_culled():
	state.apply_packet("LoadPacket", {"portals": [
		WireHelper.portal(6, 1, Vector2(12, 12), "Deep Beach", 2),
		WireHelper.portal(7, 1, Vector2(9000, 9000), "Far Beach", 1),
	]})
	await _render()
	assert_eq(renderer.draw_stats["portals"], 1, "only the near one is drawn at all")


func test_a_portal_with_no_realm_behind_it_is_still_drawn():
	state.apply_packet("LoadPacket", {
		"portals": [WireHelper.portal(6, 1, Vector2(12, 12))]})
	await _render()
	assert_eq(renderer.draw_stats["portals"], 1)


# --- wading ----------------------------------------------------------------

func test_a_player_standing_in_a_liquid_still_draws():
	# Through the real draw path, which is the only place the clipped body and
	# its clipped outline are actually issued -- the queue decides, the canvas
	# is what carries it out.
	var wet: Array = []
	for x in range(-2, 3):
		for y in range(-2, 3):
			wet.append({"tileId": 10, "layer": 0, "xIndex": y, "yIndex": x})
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 2, "tiles": wet})
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "me", Vector2.ZERO)]})
	await _render()
	assert_eq(renderer.draw_stats["players"], 1)

	var item: Dictionary = _queue()[0]
	assert_true(item["wading"], "and it is the clipped path that drew it")
	assert_lt(EntityRenderer.body_draw(item)["rect"].size.y, float(item["size"]))
