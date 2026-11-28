class_name FxKnightParry
extends RefCounted

## KNIGHT_PARRY (101): the Knight locks into a phalanx, following them as
## they move. Six curved steel plates fly in from wide and askew, turning
## as they come, and slam together into one unbroken ring of armour; the
## closing rings out as a white clang with a glint at every seam and a
## shock ring thrown off. The wall holds, a sheen sweeping round it, then
## the plates lift outward and fade.

const STEEL := Color("c3ccd8")
const STEEL_DARK := Color("5d6878")
const GOLD := Color("f2c14e")
const INK := Color("181a22")
const IVORY := Color("fff6e0")
const PLATES := 6
const CLOSE := 0.36


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	var close := FxKit.ease_out(FxKit.phase(progress, 0.0, CLOSE))
	var lift := FxKit.ease_in(FxKit.phase(progress, 0.75, 1.0))
	var alpha := FxKit.phase(progress, 0.0, 0.1) * (1.0 - lift)
	var thick := clampf(radius * 0.22, 6.0, 16.0)
	var reach := radius * (1.0 + 0.8 * (1.0 - close) + 0.35 * lift)
	var gap := lerpf(0.45, 0.025, close) + 0.2 * lift
	var twist := (1.0 - close) * 0.9
	var sheen := fmod(elapsed_ms * 0.004, TAU)
	for i in PLATES:
		var centre := TAU * i / PLATES - PI * 0.5 + twist * (1.0 if i % 2 == 0 else -1.0)
		_plate(canvas, at, reach, thick, centre, TAU / PLATES - gap, sheen, alpha)
	_clang(canvas, at, radius, thick, progress)


## One curved plate: a dark backing, a steel face, a pale inner edge, a gold
## outer rim and a rivet, lit brighter where the sheen passes.
static func _plate(canvas: CanvasItem, at: Vector2, reach: float, thick: float, centre: float, span: float,
		sheen: float, alpha: float) -> void:
	if alpha <= 0.001:
		return
	var inner := reach - thick * 0.5
	var outer := reach + thick * 0.5
	var points: Array = []
	var steps := 6
	for k in steps + 1:
		points.append(Fx.polar(at, centre - span * 0.5 + span * k / steps, outer + 1.5))
	for k in steps + 1:
		points.append(Fx.polar(at, centre + span * 0.5 - span * k / steps, inner - 1.5))
	Fx.polygon(canvas, points, Color(INK, alpha * 0.9))
	points.clear()
	for k in steps + 1:
		points.append(Fx.polar(at, centre - span * 0.5 + span * k / steps, outer))
	for k in steps + 1:
		points.append(Fx.polar(at, centre + span * 0.5 - span * k / steps, inner))
	var lit := maxf(0.0, cos(angle_difference(centre, sheen)))
	Fx.polygon(canvas, points, Color(STEEL_DARK.lerp(STEEL, 0.55 + 0.45 * lit), alpha))
	Fx.arc(canvas, at, centre - span * 0.5, centre + span * 0.5, inner + 1.5, steps, 3.0, Color(IVORY, alpha * 0.7))
	Fx.arc(canvas, at, centre - span * 0.5, centre + span * 0.5, outer - 1.0, steps, 3.0, Color(GOLD, alpha))
	CircleStamp.disc(canvas, Fx.polar(at, centre, reach), thick * 0.18, Color(GOLD, alpha))


## The plates meeting: a white ring over the wall, a glint at each seam and
## a shock ring thrown outward.
static func _clang(canvas: CanvasItem, at: Vector2, radius: float, thick: float, progress: float) -> void:
	var hit := FxKit.pulse(progress, CLOSE - 0.04, CLOSE, 0.62)
	if hit <= 0.0:
		return
	Fx.ring(canvas, at, radius, thick * 2.0 * hit, Color(Color.WHITE, hit * 0.55))
	var shock := FxKit.phase(progress, CLOSE, 0.7)
	Fx.ring(canvas, at, radius * (1.1 + 0.6 * FxKit.ease_out(shock)), 6.0 * (1.0 - shock) + 1.0,
		Color(IVORY, (1.0 - shock) * 0.8))
	for i in PLATES:
		var seam := TAU * (i + 0.5) / PLATES - PI * 0.5
		FxKit.glint(canvas, Fx.polar(at, seam, radius), thick * 2.2 * hit, seam, IVORY, hit)
