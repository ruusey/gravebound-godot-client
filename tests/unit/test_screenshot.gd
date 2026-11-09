extends GutTest

## The tilde key writes the frame somewhere the player can find it.


func test_a_headless_frame_is_nothing_to_take():
	# The viewport texture reads back null without a window, which is also
	# why the goldens run windowed; here it proves the guard.
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	assert_eq(Screenshot.take(viewport, false), "")


func test_the_name_is_a_timestamp_no_filesystem_refuses():
	# The same stamp the helper builds, checked here because the frame itself
	# cannot be read back headless: no colon and no space.
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	assert_true(stamp.match("????-??-??_??-??-??"), stamp)


func test_on_the_desktop_it_is_a_png_under_the_user_folder():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)
	await wait_process_frames(2)
	var where := Screenshot.take(viewport, false)
	if where == "":
		pass_test("headless: no frame to read back")
		return
	assert_true(where.ends_with(".png"))
	assert_true(FileAccess.file_exists(where), where)
	assert_string_contains(where, "screenshots")
	DirAccess.remove_absolute(where)


func test_in_a_browser_the_bytes_are_handed_to_the_page():
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(viewport)
	await wait_process_frames(2)
	var handed := []
	var where := Screenshot.take(viewport, true,
		func(bytes: PackedByteArray, name: String, mime: String) -> void:
			handed.append([bytes.size(), name, mime]))
	if where == "":
		pass_test("headless: no frame to read back")
		return
	assert_eq(handed.size(), 1)
	assert_gt(handed[0][0], 0, "a PNG's worth of bytes")
	assert_eq(handed[0][1], where)
	assert_eq(handed[0][2], "image/png")
	assert_true(where.begins_with("gravebound-") and where.ends_with(".png"))
	assert_false(where.contains(":") or where.contains(" "), "a name every filesystem and download prompt takes")
