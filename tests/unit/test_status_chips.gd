extends GutTest

## The chips over a character's head, and the table they come from.


func test_the_labels_are_the_web_clients():
	# The native client's comment says its labels MUST match the web's, so a
	# teammate reads the same word on every client.
	assert_eq(StatusChips.label_for(6), "Invuln")
	assert_eq(StatusChips.label_for(21), "Slow")
	assert_eq(StatusChips.label_for(17), "Pois")
	assert_eq(StatusChips.label_for(22), "Armr-")
	assert_eq(StatusChips.label_for(0), "Hide")
	assert_eq(StatusChips.label_for(41), "DEATH")
	assert_eq(StatusChips.label_for(44), "Sick")
	assert_eq(StatusChips.label_for(99), "", "an id the table does not know")
	assert_eq(StatusChips.DEFS.size(), 37)


func test_chips_come_in_table_order_not_wire_order():
	var chips := StatusChips.active([17, 6], [])
	assert_eq(chips.size(), 2)
	assert_eq(chips[0][0], "Invuln", "INVINCIBLE is listed before POISONED")
	assert_eq(chips[1][0], "Pois")
	assert_eq(chips[0][1], Color("44aaff"))


func test_a_stacked_effect_carries_its_count():
	assert_eq(StatusChips.active([17], [3])[0][0], "Pois x3")
	assert_eq(StatusChips.active([17], [1])[0][0], "Pois", "a single stack says nothing")
	assert_eq(StatusChips.active([17], [])[0][0], "Pois", "and so does a missing stack list")


func test_empty_slots_unknown_ids_and_floats():
	assert_eq(StatusChips.active([-1, 99], []), [], "-1 is an empty wire slot")
	assert_eq(StatusChips.active([], []), [])
	assert_eq(StatusChips.active([6.0], [])[0][0], "Invuln", "an id that arrived as a float still matches")


func test_a_bar_with_no_known_maximum_reads_full():
	assert_eq(EntityTag.fraction(50, 0), 1.0)
	assert_eq(EntityTag.fraction(50, 100), 0.5)
	assert_eq(EntityTag.fraction(150, 100), 1.0, "clamped")
	assert_eq(EntityTag.fraction(-5, 100), 0.0)
