class_name FxCircleWarning
extends RefCounted

## CIRCLE_WARNING (74): an enemy's ground telegraph -- the circle a slam is
## about to land in. A see-through disc of `radius` that flashes like
## BEAM_WARNING, with a second disc filling it from the centre so the edge
## closes as the strike lands. It holds until it expires rather than fading,
## and stays light enough that the boss and bullets inside it still read.
## Red, or green and blue at the boss tiers 11 and 12.

const SEGMENTS := 48


## How far the inner fill has spread, 0..1 of the radius.
static func filled(progress: float) -> float:
	return clampf(progress, 0.0, 1.0)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = fx["radius"]
	if radius <= 0.0:
		return
	var tones: Array = FxGeneric.BOSS.get(int(fx.get("tier", 0)), FxGeneric.BOSS_RED)
	var pulse := FxBeamWarning.pulse(elapsed_ms)
	CircleStamp.disc(canvas, at, radius, Color(tones[0], 0.1 + 0.12 * pulse))
	var inner := radius * filled(progress)
	if inner > 2.0:
		CircleStamp.disc(canvas, at, inner, Color(tones[0], 0.22))
		Fx.ring(canvas, at, inner, 2.0, Color(tones[2], 0.9), SEGMENTS)
	Fx.ring(canvas, at, radius, 3.0, Color(tones[1], pulse), SEGMENTS)
