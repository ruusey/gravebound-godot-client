class_name FramePacer
extends RefCounted

## One clock for the whole frame, stepped in whole display refreshes.
##
## A vsynced display shows frames on an even beat, but the time a frame STARTS
## wanders by milliseconds with whatever the CPU did last frame -- more in a
## fight. Motion advanced by that measured time lands on the even beat uneven:
## the enemy, bullet or ground steps a little long one frame and short the next,
## a judder no frame-rate counter shows. So on a synced display the clock moves
## by whole refresh periods (two on a frame that missed one), and the wall time
## not yet handed out is carried as debt, which keeps it within a couple of
## refreshes of the wall clock. Off the beat (vsync off) it passes the measured
## time straight through.

## A gap this long is a stall, a hidden tab or a breakpoint: rejoin the wall clock.
const RESYNC_MS := 250.0
## Debt past this many periods means the beat estimate is wrong; hand it all back.
const MAX_DEBT_PERIODS := 2.0
## How fast the period follows the measured frame interval.
const PERIOD_FOLLOW := 0.02
## Frames per re-check of the period against the median, to catch a refresh change.
const PERIOD_WINDOW := 30
## How far an interval may sit from the period and still count as one refresh.
const PERIOD_TOLERANCE := 0.25
## How fast the estimate of the frame start's lag behind the beat follows the debt.
const OFFSET_FOLLOW := 0.05

var enabled := true
## Whether the last frame was paced; off the beat the clock is the wall clock.
var pacing := false
## The paced time in ms, and the last frame's paced step in seconds.
var now_ms := 0.0
var delta := 0.0
## The display's refresh period in ms, refined from the measured intervals.
var period_ms := 1000.0 / 60.0

var _last_wall_ms := -1.0
var _debt_ms := 0.0
## A frame starts a roughly fixed time after the refresh it follows, so the debt
## settles around that lag rather than zero; whole periods are counted around it,
## or a lag near half a period would flip every frame between one step and two.
var _offset_ms := 0.0
var _recent := PackedFloat32Array()


func started() -> bool:
	return _last_wall_ms >= 0.0


## Seeds the period from a refresh rate the platform reports, when it reports one.
func use_refresh_rate(hz: float) -> void:
	if hz > 1.0:
		period_ms = 1000.0 / hz


## Advances one frame: `wall_ms` is the wall clock now, `raw_ms` the measured time
## since the last frame (the engine's delta), and `synced` whether frames are
## presented on the display's beat. Returns the paced step in seconds.
func tick(wall_ms: float, raw_ms: float, synced: bool) -> float:
	var first := not started()
	_last_wall_ms = wall_ms
	var raw := raw_ms
	pacing = synced and not first and raw > 0.0 and raw <= RESYNC_MS
	if not pacing:
		_debt_ms = 0.0
		_offset_ms = 0.0
		now_ms = wall_ms
		delta = maxf(raw, 0.0) / 1000.0
		return delta
	_follow_period(raw)
	_debt_ms += raw
	var step := maxi(1, roundi((_debt_ms - _offset_ms) / period_ms)) * period_ms
	_debt_ms -= step
	_offset_ms += (_debt_ms - _offset_ms) * OFFSET_FOLLOW
	if absf(_debt_ms - _offset_ms) > period_ms * MAX_DEBT_PERIODS:
		step += _debt_ms - _offset_ms
		_debt_ms = _offset_ms
	now_ms += step
	delta = step / 1000.0
	return delta


func _follow_period(raw: float) -> void:
	if absf(raw - period_ms) < period_ms * PERIOD_TOLERANCE:
		period_ms += (raw - period_ms) * PERIOD_FOLLOW
	_recent.append(raw)
	if _recent.size() < PERIOD_WINDOW:
		return
	# Most frames land on one refresh, so the median is the beat even with misses mixed in;
	# a median far off the period is a different display (a 144Hz window, a browser tab).
	_recent.sort()
	var median := _recent[_recent.size() / 2]
	_recent.clear()
	if absf(median - period_ms) > period_ms * PERIOD_TOLERANCE:
		period_ms = median
