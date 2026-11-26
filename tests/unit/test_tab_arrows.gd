extends GutTest

## A clipped tab bar's arrows land on the next tab in one click.


func test_an_arrow_right_steps_to_the_next_tab():
	assert_eq(TabArrows.step_target(0, 0, 0, 1, 2), 1)


func test_an_arrow_left_steps_back():
	assert_eq(TabArrows.step_target(1, 1, 1, 0, 2), 0)


func test_a_tab_picked_directly_is_left_alone():
	assert_eq(TabArrows.step_target(0, 0, 1, 1, 2), -1, "the click chose the tab itself")


func test_a_click_that_did_not_scroll_is_not_an_arrow():
	assert_eq(TabArrows.step_target(0, 0, 0, 0, 2), -1)


func test_the_step_stays_on_the_bar():
	assert_eq(TabArrows.step_target(1, 0, 1, 1, 2), 1, "already on the last tab")
