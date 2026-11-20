extends GutTest

## GameData resolves the ids that travel on the wire into sprites, using the
## same content JSON the server loads.

var data: GameData


func _fixture_root(name := "datadir") -> String:
	return ProjectSettings.globalize_path("res://tests/fixtures/%s" % name)


func before_each():
	data = GameData.new()


func test_loads_every_content_file():
	assert_true(await data.load_from(FileContentSource.new(_fixture_root())), "load reports success")
	assert_eq(data.errors, ["sprite sheet not found: does-not-exist.png"] as Array[String],
		"the one deliberately-broken fixture sheet, found at load rather than at first draw")
	assert_eq(data.tiles.size(), 13)
	assert_eq(data.enemies.size(), 2)
	assert_eq(data.library.classes.size(), 2)
	assert_eq(data.library.animations.size(), 3, "player and enemy entries are animation sets, nothing else")


func test_summary_reports_what_was_loaded():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_string_contains(data.summary(), "13 tiles")
	assert_string_contains(data.summary(), "2 enemies")


func test_missing_root_is_reported_not_fatal():
	assert_false(await data.load_from(FileContentSource.new("/no/such/directory")))
	assert_string_contains(data.errors[0], "data root not found", "said first; the shared crack sheet is still looked for")


func test_malformed_content_file_is_reported():
	assert_false(await data.load_from(FileContentSource.new(_fixture_root("baddir"))))
	assert_gt(data.errors.size(), 0)
	var joined := " ".join(data.errors)
	assert_string_contains(joined, "did not contain a JSON array")
	assert_string_contains(joined, "missing content file")


func test_tile_texture_uses_row_and_column_at_the_default_sprite_size():
	await data.load_from(FileContentSource.new(_fixture_root()))
	var texture := data.tile_texture(1)
	assert_not_null(texture)
	# Default sprite size is 8, so row 2 / col 3 is at (24, 16).
	assert_eq(texture.region, Rect2(24, 16, 8, 8))
	assert_eq(texture.atlas.get_size(), Vector2(64, 64))


func test_tile_texture_honours_an_explicit_sprite_size():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.tile_texture(2).region, Rect2(0, 0, 16, 16))


func test_tile_texture_is_cached():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_true(data.tile_texture(1) == data.tile_texture(1), "the same AtlasTexture instance is reused")


func test_unknown_tile_has_no_texture():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.tile_texture(9999))


func test_missing_sprite_sheet_is_recorded_once():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.tile_texture(4))
	assert_null(data.tile_texture(4))
	var misses := 0
	for error in data.errors:
		if error.contains("does-not-exist.png"):
			misses += 1
	assert_eq(misses, 1, "a missing sheet is reported once, not once per lookup")


func test_empty_sprite_key_has_no_texture():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.tile_texture(5))


func test_tile_flags_and_names():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_true(data.tile_is_wall(2))
	assert_false(data.tile_is_wall(1))
	assert_false(data.tile_is_wall(9999), "an unknown tile is not a wall")
	assert_eq(data.tile_name(1), "Grass")
	assert_eq(data.tile_name(9999), "Unknown_9999")


func test_enemy_texture_and_name():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.enemy_texture(1).region, Rect2(40, 32, 8, 8))
	assert_eq(data.enemy_texture(2).region, Rect2(0, 0, 16, 16))
	assert_null(data.enemy_texture(404))
	assert_eq(data.enemy_name(1), "Beach Crab")
	assert_eq(data.enemy_name(404), "Enemy_404")


func test_player_texture_selects_the_named_clip():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.classes_art.frame(0, "walk", "side", 0).region, Rect2(64, 48, 8, 8))
	assert_eq(data.classes_art.frame(0, "walk", "side", 1).region, Rect2(72, 48, 8, 8))


func test_player_texture_wraps_the_frame_index():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.classes_art.frame(0, "walk", "side", 2).region,
		data.classes_art.frame(0, "walk", "side", 0).region, "frame index wraps")


func test_player_texture_honours_a_wider_frame():
	# Attack frames can be double width; the region must not clip them.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.classes_art.frame(0, "attack", "side", 1).region, Rect2(96, 48, 16, 8))


func test_player_texture_falls_back_to_idle_front():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.classes_art.frame(0, "walk", "back", 0).region, Rect2(56, 56, 8, 8),
		"a missing clip falls back to idle_front rather than vanishing")


func test_player_texture_with_no_frames_is_null():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.classes_art.frame(9, "idle", "front", 0))


func test_player_texture_for_an_unknown_class_is_null():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.classes_art.frame(404, "idle", "front", 0))


func test_class_names():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.classes_art.display_name(2), "Wizard")
	assert_eq(data.classes_art.display_name(404), "Class_404")


func test_item_names():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.item_name(100), "Short Bow")
	assert_eq(data.item_name(9999), "Item_9999")


func test_projectile_angle_offset_resolves_the_group_template():
	# Most shipped groups carry PI/4 because the art points diagonally;
	# without it every shot renders 45 degrees off its heading.
	await data.load_from(FileContentSource.new(_fixture_root()))
	var offset := data.projectiles_art.angle_offset(11)
	assert_almost_eq(offset, PI / 4.0, 0.0001)
	assert_eq(data.projectiles_art.angle_offset(11), offset, "resolved once and cached")


func test_a_group_without_an_offset_is_unrotated():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.projectiles_art.angle_offset(10), 0.0)


func test_a_malformed_offset_degrades_rather_than_guessing():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.projectiles_art.angle_offset(12), 0.0)


func test_an_unknown_group_has_no_offset():
	assert_eq(data.projectiles_art.angle_offset(9999), 0.0)


func test_a_wall_tile_draws_two_cells_tall():
	# Wall art is 8x16 -- the upper square is the top face, the lower one the
	# front face. Drawing it one cell tall shows only the top.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_almost_eq(data.tile_render_height(6), 64.0, 0.001, "32px cell, 2:1 art")


func test_an_ordinary_tile_is_one_cell_tall():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_almost_eq(data.tile_render_height(1), 32.0, 0.001)
	assert_almost_eq(data.tile_render_height(9999), 32.0, 0.001, "unknown ids too")


func test_a_tall_tile_indexes_rows_by_its_own_height():
	# Row stride is spriteHeight, not spriteSize: a sheet of 8x16 cells steps
	# 16px per row. Both reference clients slice it that way.
	await data.load_from(FileContentSource.new(_fixture_root()))
	var wall := data.tile_texture(6)
	assert_not_null(wall)
	assert_eq(wall.region, Rect2(0, 16, 8, 16), "row 1 of 8x16 cells starts at y=16")


func test_a_square_tile_keeps_a_square_region():
	await data.load_from(FileContentSource.new(_fixture_root()))
	var grass := data.tile_texture(1)
	assert_not_null(grass)
	assert_eq(grass.region.size, Vector2(8, 8))


func test_a_zero_sprite_size_falls_back_to_the_default():
	# Both reference clients write `def.spriteSize || BASE_SPRITE_SIZE`, and 0
	# is falsy there, so a zero means "unset" rather than "no sprite".
	await data.load_from(FileContentSource.new(_fixture_root()))
	var region := data.sprites.atlas_for({
		"spriteKey": "atlas.png", "row": 0, "col": 0, "spriteSize": 0})
	assert_not_null(region, "a zero size is not a missing sprite")
	assert_eq(region.region.size, Vector2(SpriteCache.DEFAULT_SPRITE_SIZE,
		SpriteCache.DEFAULT_SPRITE_SIZE))


func test_a_tall_cell_from_a_missing_sheet_has_no_top_face():
	# The occlusion pass asks for a top face every frame per visible wall, so a
	# content gap must come back null and stay cached rather than re-reading a
	# file that is not there.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.sprites.top_face("does-not-exist.png", 0, 0, 8, 16))
	assert_null(data.sprites.top_face("does-not-exist.png", 0, 0, 8, 16))


func test_a_tile_with_no_definition_has_no_top_face():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.tile_top_face(9999))


func test_a_zero_sprite_size_falls_back_to_the_default_for_a_top_face():
	await data.load_from(FileContentSource.new(_fixture_root()))
	var face := data.sprites.top_face_for({
		"spriteKey": "atlas.png", "row": 1, "col": 0,
		"spriteSize": 0, "spriteHeight": 16})
	assert_not_null(face, "a zero size means unset, not no sprite")
	assert_eq(face.region, Rect2(0, 16, 8, 8))


func test_every_sheet_the_content_names_is_enumerated():
	# What SpriteCache preloads. A sheet missed here is one that cannot be
	# fetched later, because _draw has no way to await.
	await data.load_from(FileContentSource.new(_fixture_root()))
	var keys := data.library.sheet_keys()
	assert_true("atlas.png" in keys, "tiles and enemies name it")
	assert_true("does-not-exist.png" in keys, "including one that is not there")
	assert_eq(keys.size(), keys.duplicate().size(), "no duplicates")


func test_a_sheet_nobody_enumerated_is_reported_rather_than_fetched():
	# _draw cannot await, so there is no fetching one on demand. Saying so once
	# beats a silent blank sprite or an error per frame.
	await data.load_from(FileContentSource.new(_fixture_root()))
	var before := data.errors.size()
	assert_null(data.sprites.texture("never-mentioned.png"))
	assert_null(data.sprites.texture("never-mentioned.png"))
	assert_eq(data.errors.size(), before + 1, "recorded once, not once per lookup")
	assert_string_contains(data.errors[-1], "not preloaded")


func test_an_attack_clip_holds_its_last_frame():
	# It plays once. Wrapping would loop the swing inside its window, which
	# reads as a stutter -- both references clamp here.
	await data.load_from(FileContentSource.new(_fixture_root()))
	var last := data.classes_art.frame(0, "attack", "side", 1)
	assert_not_null(last)
	assert_eq(data.classes_art.frame(0, "attack", "side", 2).region, last.region)
	assert_eq(data.classes_art.frame(0, "attack", "side", 99).region, last.region,
		"however far past the end the pose has counted")


func test_a_walk_clip_still_wraps():
	# Only attacks hold; a gait that stopped looping would freeze mid-stride.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.classes_art.frame(0, "walk", "side", 2).region,
		data.classes_art.frame(0, "walk", "side", 0).region)


# --- projectile spin --------------------------------------------------------

func test_an_additive_spin_carries_its_rate_and_direction():
	await data.load_from(FileContentSource.new(_fixture_root()))
	var spin := data.projectiles_art.spin(20)
	assert_almost_eq(float(spin["rate"]), 5.76, 0.0001)
	assert_true(spin["additive"])
	assert_eq(data.projectiles_art.spin(20), spin, "resolved once and cached")


func test_a_continuous_spin_is_not_additive():
	# It replaces the flight angle rather than turning on top of it -- a
	# shuriken does not point where it is going.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_false(data.projectiles_art.spin(21)["additive"])


func test_counter_clockwise_is_a_negative_rate():
	# Screen space is y-down and Godot rotates clockwise-positive, as PIXI
	# does. The native client negates the other way only because LibGDX is
	# counter-clockwise-positive.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_lt(float(data.projectiles_art.spin(22)["rate"]), 0.0)


func test_a_spin_with_no_rate_falls_back():
	# `fx.rate || 6` in the web client, so a missing rate and a zero rate are
	# the same thing.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_almost_eq(absf(float(data.projectiles_art.spin(22)["rate"])),
		ProjectileArt.DEFAULT_SPIN_RATE, 0.0001)


func test_a_spin_is_found_behind_other_effects():
	# Group 22 lists a trail first; scanning only the first entry misses it.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_false(data.projectiles_art.spin(22).is_empty())


func test_a_group_without_fx_does_not_spin():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.projectiles_art.spin(10), {})
	assert_eq(data.projectiles_art.spin(9999), {}, "and neither does an unknown one")


func test_spin_advances_with_the_wall_clock():
	# Not with a bullet's age: both references key it to absolute time, so
	# every bullet in a group turns in phase.
	var spin := {"rate": 2.0, "additive": true}
	assert_almost_eq(ProjectileArt.spun(spin, 1000), 2.0, 0.0001)
	assert_almost_eq(ProjectileArt.spun(spin, 2000), 4.0, 0.0001)


func test_no_spin_is_no_rotation():
	assert_eq(ProjectileArt.spun({}, 99999), 0.0)


func test_effects_other_than_spin_do_not_make_a_group_spin():
	# Three shipped groups carry a trail and nothing else. Treating any fx
	# list as a spin would set them turning at the fallback rate.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_eq(data.projectiles_art.spin(23), {})


# --- portals and maps ------------------------------------------------------

func test_portal_art_comes_from_its_id():
	# Nothing about how a portal looks is on the wire, which is why copying a
	# NetPortal field-by-field leaves a blank one.
	await data.load_from(FileContentSource.new(_fixture_root()))
	var texture := data.portals.texture(1)
	assert_not_null(texture, "portal 1 is defined in the fixture content")
	if texture != null:
		assert_eq(texture.region, Rect2(16, 24, 8, 8), "row 3, col 2 at size 8")
	assert_eq(data.portals.name(1), "Beach_Portal")


func test_an_undefined_portal_has_no_art_and_a_stand_in_name():
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_null(data.portals.texture(404))
	assert_eq(data.portals.name(404), "Portal_404")


func test_the_nexus_and_the_vault_are_known_by_name():
	# By name rather than by id: the native client still calls them 1 and 29,
	# the content we run numbers them 30 and 31.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_true(data.maps.is_nexus(31))
	assert_false(data.maps.is_nexus(30))
	assert_true(data.maps.is_vault(30))
	assert_false(data.maps.is_vault(2))
	assert_eq(data.maps.name(2), "World_1_Beach")
	assert_eq(data.maps.name(404), "", "an unknown map is not the nexus or the vault")
	# Anchored at the start, not merely contained: a content rename like
	# Deep_Vault_Ruins is a realm you can die in, not the vault.
	assert_false(data.maps.is_vault(32), data.maps.name(32))
	assert_false(data.maps.is_nexus(33), data.maps.name(33))


func test_a_sheet_only_portals_refer_to_is_still_preloaded():
	# In the shipped content realm-tiles-2.png is named by portals and by
	# nothing else, and it carries the vault, exit and nexus portals. Leave
	# the portal table out of sheet_keys() and all three become invisible
	# doorways, with the unit suite and check-content.sh both green -- so the
	# fixture gives portals a sheet of their own too.
	await data.load_from(FileContentSource.new(_fixture_root()))
	assert_has(data.library.sheet_keys(), "portal-sheet.png")
	assert_not_null(data.sprites.texture("portal-sheet.png"))


func test_projectile_fx_resolves_the_trail_impact_and_afterimage():
	await data.load_from(FileContentSource.new(_fixture_root()))
	var spark := data.projectiles_art.fx(24)
	assert_eq(spark["trail"]["particle"], "spark")
	assert_eq(int(spark["trail"]["rate"]), 40)
	assert_eq(int(spark["impact"]["count"]), 18)
	assert_eq(spark["muzzle"], {})
	assert_eq(spark["afterimage"], Color.TRANSPARENT, "no trailColor on this one")
	var tar := data.projectiles_art.fx(25)
	assert_eq(tar["trail"], {})
	assert_eq(tar["afterimage"], Color.hex(0x8a1020ff))
	assert_eq(data.projectiles_art.fx(22)["trail"], {"type": "trail", "particle": "spark"}, "beside a spin")
	assert_eq(data.projectiles_art.fx(20)["trail"], {}, "a spin alone")
	assert_eq(data.projectiles_art.fx(9999), {"trail": {}, "impact": {}, "muzzle": {},
		"afterimage": Color.TRANSPARENT})
	assert_same(data.projectiles_art.fx(24), spark, "resolved once and cached")


func test_projectile_fx_colours_are_read_as_the_content_writes_them():
	assert_eq(ProjectileArt.colour("0x1c1c1c", Color.WHITE), Color.hex(0x1c1c1cff))
	assert_eq(ProjectileArt.colour("#8a1020", Color.WHITE), Color.hex(0x8a1020ff))
	assert_eq(ProjectileArt.colour(0xffcc44, Color.WHITE), Color.hex(0xffcc44ff))
	assert_eq(ProjectileArt.colour("purple", Color.WHITE), Color.WHITE, "anything unreadable is the fallback")
	assert_eq(ProjectileArt.colour(null, Color.BLACK), Color.BLACK)
	assert_eq(ProjectileArt.colour("0x12", Color.BLACK), Color.BLACK, "too short")
