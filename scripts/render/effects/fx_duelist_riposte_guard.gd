class_name FxDuelistRiposteGuard
extends RefCounted

## DUELIST_RIPOSTE_GUARD (108): the Duelist en garde while Riposte charges,
## following them as they shuffle. A shimmering parry ring hangs round the
## body with three blade glints racing along it, two crossed rapiers stand
## over the head, and in the last stretch the ring draws tight -- the
## coiled moment before the counter. It snaps in with a flash at the start.

const GOLD := Color("f4d27a")
const IVORY := Color("fff6e0")
const STEEL := Color("c9d3de")
const GLINTS := 3


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var snap := 1.0 - FxKit.phase(progress, 0.0, 0.12)
	var coil := FxKit.ease_in(FxKit.phase(progress, 0.75, 1.0))
	var ring := radius * (1.0 + 0.25 * snap - 0.3 * coil)
	var shimmer := 0.75 + 0.25 * sin(elapsed_ms * 0.025)
	Fx.dot(canvas, at, ring * 1.7, Color(GOLD, 0.06 + 0.1 * coil))
	Fx.ring(canvas, at, ring, 6.0, Color(GOLD, 0.25 * shimmer))
	Fx.ring(canvas, at, ring, 2.0, Color(IVORY, 0.7 * shimmer))
	Fx.ring(canvas, at, ring * (1.0 + 0.6 * (1.0 - snap)), 2.0, Color(Color.WHITE, snap * 0.8))
	var turn := elapsed_ms * 0.012
	for i in GLINTS:
		var angle := turn + TAU * i / GLINTS
		Fx.arc(canvas, at, angle - 0.5, angle, ring, 6, 3.0, Color(IVORY, 0.85))
		FxKit.glint(canvas, Fx.polar(at, angle, ring), 9.0, angle, IVORY, 0.9)
	_crossed_blades(canvas, at + Vector2(0.0, -radius - 10.0), 11.0 * (1.0 - 0.2 * coil), elapsed_ms)


## Two rapiers crossed point-up over the head, bobbing slightly, a glint
## where they cross.
static func _crossed_blades(canvas: CanvasItem, at: Vector2, size: float, elapsed_ms: int) -> void:
	var bob := at + Vector2(0.0, sin(elapsed_ms * 0.008) * 1.5)
	for s: float in [-1.0, 1.0]:
		var tip := bob + Vector2(size * 0.7 * s, -size)
		var pommel := bob + Vector2(-size * 0.6 * s, size * 0.8)
		Fx.line(canvas, pommel, tip, 2.5, Color(Color.BLACK, 0.5))
		Fx.line(canvas, pommel, tip, 1.5, Color(STEEL, 0.95))
		var guard := pommel.lerp(tip, 0.25)
		var across := (tip - pommel).normalized().orthogonal() * 3.0
		Fx.line(canvas, guard - across, guard + across, 2.0, Color(GOLD, 0.95))
	FxKit.glint(canvas, bob, 7.0, 0.0, IVORY, 0.8)
