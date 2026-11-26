class_name FxCaltrops
extends RefCounted

## CALTROPS (37): a scatter of iron caltrops tossed over the ground. Each
## is a three-legged star of steel spikes on a dark shadow, with a bright
## upturned spike at its heart, flung out from the centre to its own place
## in the first fifth with a little hop and a spin, then lying still on a
## dark dusting of grit inside a steel rim. A wider field gets more of
## them, the same spread every frame.

const STEEL := Color("c4ccd4")
const EDGE := Color("1c2228")
const GRIT := Color("30363c")
## The golden angle, so the caltrops spread evenly without lining up.
const GOLDEN := 2.39996
const TOSS_END := 0.2


## How many caltrops: one per 5 units of radius, 8 to 18.
static func count(radius: float) -> int:
	return clampi(int(radius / 5.0), 8, 18)


## A caltrop's reach from its heart to a spike tip, 6 to 12 units.
static func size(radius: float) -> float:
	return clampf(radius * 0.15, 6.0, 12.0)


## Where caltrop `i` of `total` lies from the centre: spread over the disc
## on a golden-angle spiral out to 88% of the radius, so they never clump.
static func offset(radius: float, i: int, total: int) -> Vector2:
	var distance := radius * 0.88 * sqrt((i + 0.5) / total)
	return Fx.polar(Vector2.ZERO, i * GOLDEN + 0.5, distance)


## How far through its throw caltrop `i` is, 0..1: the outer ones land a
## touch later.
static func toss(progress: float, i: int, total: int) -> float:
	return clampf(progress / (TOSS_END * (0.6 + 0.4 * float(i) / total)), 0.0, 1.0)


## A three-legged star: three spikes `reach` out, pinched to a quarter of
## it between them.
static func star(at: Vector2, angle: float, reach: float) -> Array:
	var points: Array = []
	for k in 6:
		points.append(Fx.polar(at, angle + k * PI / 3.0, reach * (1.0 if k % 2 == 0 else 0.26)))
	return points


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 12.0)
	var alpha := clampf((1.0 - progress) / 0.3, 0.0, 1.0)
	if alpha <= 0.001:
		return
	var spread := clampf(progress / TOSS_END, 0.0, 1.0)
	CircleStamp.disc(canvas, at, radius * spread, Color(GRIT, alpha * 0.30))
	Fx.ring(canvas, at, radius * spread, 3.0, Color(STEEL, alpha * 0.45))
	var total := count(radius)
	var reach := size(radius)
	for i in total:
		var t := toss(progress, i, total)
		var hop := Vector2(0.0, -sin(t * PI) * radius * 0.22)
		var c := at + offset(radius, i, total) * (1.0 - pow(1.0 - t, 2.0)) + hop
		var angle := i * 1.7 + (1.0 - t) * 6.0
		CircleStamp.disc(canvas, c + Vector2(0.5, 1.0), reach * 0.75, Color(Color.BLACK, alpha * 0.45))
		Fx.polygon(canvas, star(c, angle, reach + 2.0), Color(EDGE, alpha))
		Fx.polygon(canvas, star(c, angle, reach), Color(STEEL, alpha))
		Fx.dot(canvas, c, 4.5, Color(EDGE, alpha))
		Fx.dot(canvas, c - Vector2(0.0, 0.5), 2.5, Color(Color.WHITE, alpha))
