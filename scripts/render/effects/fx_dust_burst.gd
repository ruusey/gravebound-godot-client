class_name FxDustBurst
extends RefCounted

## DUST_BURST (72): sand and grit kicked up off the ground. Fourteen tan
## puffs billow outward to just past the radius on an ease-out, a low dust
## ring rolls ahead of them, and grit flecks spray out and drop. Everything
## thins as it spreads.

const SAND := Color("c8a46a")
const DUST := Color("e0c890")
const SHADOW := Color("7a6040")
const PUFFS := 14


static func spread(progress: float) -> float:
	return 1.0 - pow(1.0 - progress, 3.0)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	var alpha := 1.0 - progress
	var out := spread(progress)
	Fx.ring(canvas, at, radius * (0.3 + 0.85 * out), 8.0 * alpha + 1.0, Color(SHADOW, alpha * 0.5))
	for i in PUFFS:
		var angle := i * TAU / PUFFS + sin(i * 1.7) * 0.3 + elapsed_ms * 0.0005
		var centre := Fx.polar(at, angle, radius * (0.15 + 0.8 * out) * (0.8 + 0.2 * sin(i * 3.1)))
		var size := radius * (0.22 + 0.25 * out)
		CircleStamp.disc(canvas, centre, size, Color(SAND, alpha * 0.35))
		CircleStamp.disc(canvas, centre, size * 0.6, Color(DUST, alpha * 0.4))
	var rng := Fx.rng_for(fx, 0)
	for i in 18:
		var angle := rng.randf() * TAU
		var reach := radius * (0.2 + out * rng.randf_range(0.8, 1.3))
		var drop := progress * progress * 18.0 * Fx.S
		Fx.dot(canvas, Fx.polar(at, angle, reach) + Vector2(0.0, drop), 2.0, Color(SHADOW, alpha * 0.9))
