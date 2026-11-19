extends GutTest

## The frame clock steps in whole display refreshes while frames are presented on
## the beat, however much the measured start of each frame wanders.

const PERIOD := 1000.0 / 60.0

var pacer: FramePacer
var wall := 1000.0


func before_each():
	pacer = FramePacer.new()
	pacer.use_refresh_rate(60.0)
	wall = 1000.0
	_frame(PERIOD)


func _frame(raw_ms: float, synced := true) -> float:
	wall += raw_ms
	return pacer.tick(wall, raw_ms, synced) * 1000.0


func test_a_wandering_frame_start_still_steps_one_refresh():
	for raw in [14.2, 19.1, 15.0, 18.3, 16.1, 17.4, 13.9, 19.4]:
		var step := _frame(raw)
		assert_almost_eq(step, pacer.period_ms, 0.01, "measured %.1f ms, shown one refresh later" % raw)
		assert_almost_eq(step, PERIOD, 0.5, "the period estimate barely moves")
	assert_true(pacer.pacing)


func test_a_missed_refresh_steps_two():
	for i in 10:
		_frame(PERIOD)
	assert_almost_eq(_frame(PERIOD * 2.0), pacer.period_ms * 2.0, 0.01)
	assert_almost_eq(_frame(PERIOD), pacer.period_ms, 0.01, "and back to one")


func test_the_paced_clock_keeps_to_the_wall_clock():
	var start := pacer.now_ms
	var raws := [14.0, 19.0, 33.0, 16.0, 17.5, 15.5, 50.0, 16.7]
	for i in 120:
		_frame(raws[i % raws.size()])
	assert_almost_eq(pacer.now_ms - start, wall - 1000.0 - PERIOD, PERIOD * FramePacer.MAX_DEBT_PERIODS,
		"never more than a couple of refreshes from the wall clock")


func test_off_the_beat_the_measured_time_passes_straight_through():
	assert_almost_eq(_frame(7.3, false), 7.3, 0.001)
	assert_false(pacer.pacing)
	assert_eq(pacer.now_ms, wall, "the wall clock itself")


func test_a_stall_rejoins_the_wall_clock():
	_frame(PERIOD)
	assert_almost_eq(_frame(FramePacer.RESYNC_MS + 50.0), FramePacer.RESYNC_MS + 50.0, 0.001)
	assert_eq(pacer.now_ms, wall)


func test_a_faster_display_is_learned_from_the_intervals():
	var fast := 1000.0 / 144.0
	for i in FramePacer.PERIOD_WINDOW * 2:
		_frame(fast)
	assert_almost_eq(pacer.period_ms, fast, 0.2)
	assert_almost_eq(_frame(fast + 1.5), pacer.period_ms, 0.01)
