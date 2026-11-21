extends GutTest


func _entity(velocity := Vector2.ZERO) -> Dictionary:
	return {"snaps": [{"t": 0.0, "pos": Vector2.ZERO, "vel": velocity}]}


func test_a_body_at_rest_faces_the_way_its_art_is_drawn():
	assert_eq(MotionHeading.advance(_entity(), Vector2.ZERO, 0.0), 0.0)


func test_a_body_first_seen_moving_faces_its_velocity():
	var heading := MotionHeading.advance(_entity(Vector2(0, 2)), Vector2.ZERO, 0.0)
	assert_almost_eq(heading, PI * 0.5, 0.0001, "moving down the screen faces down")


func test_the_heading_swings_toward_the_drawn_travel():
	var entity := _entity()
	MotionHeading.advance(entity, Vector2.ZERO, 0.0)
	var first := MotionHeading.advance(entity, Vector2(0, 4), 0.016)
	assert_between(first, 0.0, PI * 0.5, "turning, not snapped")
	var heading := first
	for frame in 60:
		heading = MotionHeading.advance(entity, Vector2(0, 8 + frame * 4), 0.032 + frame * 0.016)
	assert_almost_eq(heading, PI * 0.5, 0.01, "settles along its travel")


func test_standing_still_keeps_the_last_heading():
	var entity := _entity()
	MotionHeading.advance(entity, Vector2.ZERO, 0.0)
	for frame in 60:
		MotionHeading.advance(entity, Vector2(-(frame + 1) * 4, 0), (frame + 1) * 0.016)
	var moving: float = entity["heading"]
	var still := MotionHeading.advance(entity, Vector2(-240, 0), 2.0)
	assert_eq(still, moving, "no travel, no turn")
	assert_almost_eq(absf(still), PI, 0.01, "still facing left")


func test_it_turns_the_short_way_round():
	var entity := _entity(Vector2(0, -1))
	MotionHeading.advance(entity, Vector2.ZERO, 0.0)
	var heading := MotionHeading.advance(entity, Vector2(-0.5, -4), 0.016)
	assert_lt(heading, -PI * 0.5, "from up toward up-left, never back through right")
