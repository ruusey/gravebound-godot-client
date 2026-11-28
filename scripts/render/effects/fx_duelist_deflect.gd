class_name FxDuelistDeflect
extends RefCounted

## DUELIST_DEFLECT (109): a shot turned aside by the Riposte guard, at the
## shot (`pos`), away from the Duelist (`target`). A hard white glint, a
## small gold ring and a spray of ricochet sparks thrown off the blade.

const GOLD := Color("f4d27a")
const IVORY := Color("fff6e0")


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var away: Vector2 = at - FxKit.line_end(fx, -16.0)
	var dir := away.normalized() if away.length() > 0.5 else Vector2.UP
	var size: float = clampf(fx["radius"], 10.0, 32.0)
	var flash := 1.0 - FxKit.ease_out(progress)
	FxKit.glint(canvas, at, size * (0.8 + 1.2 * flash), progress * 2.0, IVORY, flash)
	Fx.ring(canvas, at, size * (0.3 + 1.1 * FxKit.ease_out(progress)), 2.0, Color(GOLD, 1.0 - progress))
	FxKit.sparks(canvas, at, dir, 1.6, 6, size * 2.2, progress, 6.0, 1.5, GOLD, 1.0, FxKit.seed_of(fx))
