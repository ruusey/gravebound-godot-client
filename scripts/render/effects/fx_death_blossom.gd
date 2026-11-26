class_name FxDeathBlossom
extends RefCounted

## DEATH_BLOSSOM (30): the ninja's ultimate, a blossom of blades bursting
## open round the caster. Eight curved steel petal-blades unfurl from the
## centre out past the radius in the first third, wheeling a quarter turn
## over the effect's life, each a white blade edged dark; eight crimson
## petals open behind them, between; a bright slash arc trails each
## blade's tip, and a red heart glows at the centre. It holds to 60%, then
## fades.

const SLASHES := 8
const SWEEP := 0.5
const SEGMENTS := 6
const PETAL_STEPS := 5
## How far a blade curls round from its root to its tip, radians.
const CURL := 0.45
const STEEL := Color("eef0ff")
const EDGE := Color("1e1824")
const CRIMSON := Color("d01838")


static func reach(radius: float) -> float:
	return radius * 1.1


## Where slash `i` is centred: an eighth of a turn apart, and a quarter
## turn further round by the end.
static func slash_angle(i: int, progress: float) -> float:
	return float(i) / SLASHES * TAU + progress * PI * 0.5


## How far open the blossom is, 0..1: bursting out over the first 35%,
## fast at first.
static func bloom(progress: float) -> float:
	return 1.0 - pow(1.0 - clampf(progress / 0.35, 0.0, 1.0), 3.0)


static func strength(progress: float) -> float:
	return clampf((1.0 - progress) / 0.4, 0.0, 1.0)


## A petal from `inner` to `outer` along `angle`, `width` across at its
## widest and pointed at both ends, curling `curl` radians round by its tip.
static func petal(at: Vector2, angle: float, inner: float, outer: float, width: float, curl: float) -> Array:
	var left: Array = []
	var right: Array = []
	for k in PETAL_STEPS + 1:
		var u := float(k) / PETAL_STEPS
		var a := angle + curl * u * u
		var along := Vector2(cos(a), sin(a))
		var spine := at + along * lerpf(inner, outer, u)
		var half := width * sin(PI * pow(u, 0.75))
		left.append(spine + along.orthogonal() * half)
		right.append(spine - along.orthogonal() * half)
	right.reverse()
	return left + right.slice(1, right.size() - 1)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	var alpha := strength(progress)
	if alpha <= 0.001:
		return
	var open := bloom(progress)
	var r := reach(radius) * open
	if r < 6.0:
		return
	var width := minf(maxf(3.0, radius * 0.13), r * 0.22)
	CircleStamp.disc(canvas, at, r * 0.8, Color(CRIMSON, alpha * 0.12))
	for i in SLASHES:
		var angle := slash_angle(i, progress) + PI / SLASHES
		Fx.polygon(canvas, petal(at, angle, r * 0.07, r * 0.72, width * 1.25, CURL * 0.6),
			Color(CRIMSON, alpha * 0.8))
	for i in SLASHES:
		var angle := slash_angle(i, progress)
		Fx.polygon(canvas, petal(at, angle, r * 0.09, r + 1.5, width + 1.5, CURL), Color(EDGE, alpha * 0.9))
		Fx.polygon(canvas, petal(at, angle, r * 0.11, r, width, CURL), Color(STEEL, alpha))
		Fx.arc(canvas, at, angle + CURL - SWEEP, angle + CURL, r * 1.04, SEGMENTS, 3.0,
			Color(Color.WHITE, alpha * 0.8))
	Fx.dot(canvas, at, 10.0, Color(EDGE, alpha * 0.8))
	Fx.dot(canvas, at, 7.0, Color("ff4060", alpha))
