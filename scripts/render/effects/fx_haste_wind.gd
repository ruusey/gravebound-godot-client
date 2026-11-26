class_name FxHasteWind
extends RefCounted

## HASTE_WIND (39): a gust whipping round the caster. Four cyan wind
## streaks spiral round at their own distances and speeds, each a comet-
## tailed arc that thickens and brightens to a white head, flung a little
## wider as the gust builds; short speed lines whoosh past between them,
## over a faint cyan swirl of air. It gusts in fast and dies away over the
## last third, and ignores the tier colour.

const CYAN := Color("40dfff")
const PALE := Color("c8f6ff")
const STREAKS := 4
const GUSTS := 6
const SEGMENTS := 10
## How much of a turn a streak's tail trails behind its head.
const STREAK_SWEEP := PI * 0.8
## How fast the streaks wheel round, radians per ms.
const SPIN := 0.0065


## Up over the first 10%, held, and down over the last 35%.
static func strength(progress: float) -> float:
	return clampf(progress / 0.1, 0.0, 1.0) * clampf((1.0 - progress) / 0.35, 0.0, 1.0)


## How far out streak `i` circles: 45%, 65%, 85% and 105% of the radius,
## pushed out by a fifth more as the gust builds.
static func streak_orbit(radius: float, i: int, progress: float) -> float:
	return radius * (0.45 + 0.2 * i) * (0.9 + 0.2 * progress)


## Where streak `i`'s head is, in radians: a quarter turn apart, the outer
## ones wheeling a little faster.
static func streak_angle(i: int, elapsed_ms: int) -> float:
	return i * TAU / STREAKS + elapsed_ms * SPIN * (1.0 + 0.12 * i)


## How far gust line `j` has blown along its run, 0..1, wrapping.
static func gust_phase(j: int, progress: float) -> float:
	return fmod(progress * 2.5 + j * 0.37, 1.0)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	var a := strength(progress)
	if a <= 0.001:
		return
	CircleStamp.disc(canvas, at, radius * 1.1, Color(CYAN, a * 0.10))
	CircleStamp.disc(canvas, at, radius * 0.5, Color(PALE, a * 0.05))
	for i in STREAKS:
		_streak(canvas, at, streak_orbit(radius, i, progress), streak_angle(i, elapsed_ms), a)
	_gusts(canvas, at, radius, progress, elapsed_ms, a)


## A spiral arc from a faint tail curling in to a bright head, in three
## passes: a wide cyan glow, the cyan streak and a white core near the head.
static func _streak(canvas: CanvasItem, at: Vector2, orbit: float, head: float, a: float) -> void:
	var points := PackedVector2Array()
	var glow := PackedColorArray()
	var body := PackedColorArray()
	points.resize(SEGMENTS + 1)
	glow.resize(SEGMENTS + 1)
	body.resize(SEGMENTS + 1)
	for k in SEGMENTS + 1:
		var u := float(k) / SEGMENTS
		points[k] = Fx.polar(at, head - (1.0 - u) * STREAK_SWEEP, orbit * (0.78 + 0.22 * u))
		glow[k] = Color(CYAN, a * 0.35 * u)
		body[k] = Color(CYAN, a * u * u)
	canvas.draw_polyline_colors(points, glow, 12.0 * Fx.S)
	canvas.draw_polyline_colors(points, body, 5.0 * Fx.S)
	var core := points.slice(SEGMENTS / 2)
	Fx.polyline(canvas, core, 2.5, Color(PALE, a * 0.95))
	Fx.dot(canvas, points[SEGMENTS], 3.5, Color(Color.WHITE, a))


## Short straight speed lines blowing round tangentially between the
## streaks, all in one draw.
static func _gusts(canvas: CanvasItem, at: Vector2, radius: float, progress: float, elapsed_ms: int,
		a: float) -> void:
	var lines := PackedVector2Array()
	var length := radius * 0.45
	for j in GUSTS:
		var phase := gust_phase(j, progress)
		var angle := j * TAU / GUSTS + 0.4 + elapsed_ms * SPIN * 0.6
		var spot := Fx.polar(at, angle, radius * (0.35 + 0.12 * j))
		var tangent := Vector2(-sin(angle), cos(angle))
		var head := spot + tangent * length * (phase - 0.5)
		lines.append(head - tangent * length * 0.5 * sin(phase * PI))
		lines.append(head)
	if a > 0.001:
		canvas.draw_multiline(lines, Color(PALE, a * 0.6), 2.5 * Fx.S)
