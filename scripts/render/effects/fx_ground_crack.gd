class_name FxGroundCrack
extends RefCounted

## GROUND_CRACK (68): a fissure tearing along the ground from `pos` to
## `target`. The crack races out over the first 30% -- grit thrown off its
## tip -- as a dark jagged seam with a molten glow down the middle and short
## side branches, holds, and from 60% closes and fades. The jag is seeded
## from the effect, so one crack keeps its shape for its whole life.

const SEGMENTS := 14
const OPEN_END := 0.3
const FADE_START := 0.6
const SEAM := Color("1a1008")
const GLOW := Color("ff9a3c")
const HOT := Color("fff0b0")
const GRIT := Color("b89060")


## The crack's points, from start to far end, jagged across the line and
## pinched to it at both ends.
static func path(fx: Dictionary) -> PackedVector2Array:
	var from: Vector2 = fx["pos"]
	var along: Vector2 = fx["target"] - from
	var side := along.orthogonal().normalized()
	var jag := maxf(8.0, along.length() * 0.07)
	var rng := Fx.rng_for(fx, 0)
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		points.append(from + along * t + side * rng.randf_range(-1.0, 1.0) * jag * sin(t * PI))
	return points


static func opened(progress: float) -> float:
	return clampf(progress / OPEN_END, 0.0, 1.0)


static func alpha_at(progress: float) -> float:
	return 1.0 - clampf((progress - FADE_START) / (1.0 - FADE_START), 0.0, 1.0)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	if (fx["target"] - fx["pos"]).length() < 2.0:
		return
	var points := path(fx)
	var shown := points.slice(0, maxi(2, ceili(opened(progress) * SEGMENTS) + 1))
	var alpha := alpha_at(progress)
	var flicker := 0.75 + 0.25 * sin(elapsed_ms * 0.02)
	Fx.polyline(canvas, shown, 26.0, Color(GRIT, alpha * 0.25))
	Fx.polyline(canvas, shown, 16.0, Color(SEAM, alpha * 0.9))
	Fx.polyline(canvas, shown, 8.0, Color(GLOW, alpha * flicker))
	Fx.polyline(canvas, shown, 3.0, Color(HOT, alpha * 0.9))
	var side := (points[-1] - points[0]).orthogonal().normalized()
	for i in range(2, shown.size() - 1, 3):
		var branch := side * (1.0 if i % 2 == 0 else -1.0) * 18.0
		var reach := shown[i] + branch + (shown[i + 1] - shown[i]) * 0.4
		Fx.line(canvas, shown[i], reach, 8.0, Color(SEAM, alpha * 0.85))
		Fx.line(canvas, shown[i], shown[i] + (reach - shown[i]) * 0.7, 3.0, Color(GLOW, alpha * 0.8))
	if progress < OPEN_END + 0.15:
		var tip := shown[-1]
		var rng := Fx.rng_for(fx, elapsed_ms)
		for i in 8:
			var fly := (progress * 60.0 + i * 3.0) * Fx.S
			var spark := tip + side * rng.randf_range(-1.0, 1.0) * fly - Vector2(0.0, rng.randf() * fly)
			Fx.dot(canvas, spark, 4.0, Color(GRIT, alpha * 0.9))
