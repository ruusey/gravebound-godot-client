class_name FxKnightShieldBash
extends RefCounted

## KNIGHT_SHIELD_BASH (99): the Knight's shield driven into a foe. A crested
## heater shield punches in from the caster's side, swelling down onto the
## strike, and bounces back off it with a white flash and a glint across its
## face. Three chevron shockwaves are shoved forward in the bash's direction,
## dust skids out ahead of them and steel chips fly; then three dazed stars
## wheel over the struck spot while it all fades.

const STEEL := Color("c3ccd8")
const STEEL_DARK := Color("6c7888")
const GOLD := Color("f2c14e")
const INK := Color("181a22")
const IVORY := Color("fff6e0")
const DUST := Color("9a8e7c")
const SHIELD := [Vector2(-0.5, -0.55), Vector2(0.5, -0.55), Vector2(0.5, -0.05), Vector2(0.3, 0.35),
	Vector2(0.0, 0.6), Vector2(-0.3, 0.35), Vector2(-0.5, -0.05)]
const SHIELD_SHADE := [Vector2(0.0, -0.55), Vector2(0.5, -0.55), Vector2(0.5, -0.05), Vector2(0.3, 0.35),
	Vector2(0.0, 0.6)]
const IMPACT := 0.12


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 24.0)
	var dir := Fx.facing(fx)
	_dust(canvas, at, radius, dir, progress, FxKit.seed_of(fx))
	_flash(canvas, at, radius, progress)
	_shock(canvas, at, radius, dir, progress)
	FxKit.sparks(canvas, at, dir, 1.9, 9, radius * 1.15, FxKit.phase(progress, IMPACT, 0.7), 16.0, 3.0,
		STEEL, 1.0, FxKit.seed_of(fx) + 1)
	_slam(canvas, at, radius, dir, progress)
	_dazed(canvas, at + Vector2(0.0, -radius * 0.85), radius * 0.45, progress, elapsed_ms)


## A heater shield `size` across, point down, turned by `tilt`: a dark rim,
## a steel face shaded down its right half, a gold border and a gold cross.
static func shield(canvas: CanvasItem, at: Vector2, size: float, tilt: float, alpha: float) -> void:
	if alpha <= 0.001:
		return
	Fx.polygon(canvas, _shape(SHIELD, at, size * 1.16, tilt), Color(INK, alpha * 0.9))
	Fx.polygon(canvas, _shape(SHIELD, at, size, tilt), Color(STEEL, alpha))
	Fx.polygon(canvas, _shape(SHIELD_SHADE, at, size, tilt), Color(STEEL_DARK, alpha * 0.6))
	FxBladeShapes.outline(canvas, _shape(SHIELD, at, size * 0.84, tilt), maxf(2.0, size * 0.07), Color(GOLD, alpha))
	var up := Vector2.UP.rotated(tilt)
	var side := Vector2.RIGHT.rotated(tilt)
	Fx.line(canvas, at - up * size * 0.36, at + up * size * 0.4, maxf(2.0, size * 0.09), Color(GOLD, alpha))
	Fx.line(canvas, at + up * size * 0.16 - side * size * 0.26, at + up * size * 0.16 + side * size * 0.26,
		maxf(2.0, size * 0.09), Color(GOLD, alpha))


static func _shape(unit: Array, at: Vector2, size: float, tilt: float) -> Array:
	var points: Array = []
	for corner: Vector2 in unit:
		points.append(at + (corner * size).rotated(tilt))
	return points


## The shield comes in big from behind the strike, lands, rebounds a touch
## and fades from 55%; a glint flares across its face on the hit.
static func _slam(canvas: CanvasItem, at: Vector2, radius: float, dir: Vector2, progress: float) -> void:
	var t_in := FxKit.phase(progress, 0.0, IMPACT)
	var land := FxKit.ease_in(t_in)
	var rebound := sin(FxKit.phase(progress, IMPACT, 0.35) * PI) * 0.1
	var centre := at - dir * radius * (0.12 + 0.55 * (1.0 - land) + rebound)
	var size := radius * 0.62 * lerpf(1.6, 1.0, land)
	var alpha := (0.35 + 0.65 * t_in) * (1.0 - FxKit.phase(progress, 0.55, 0.85))
	var tilt := dir.x * 0.22
	shield(canvas, centre, size, tilt, alpha)
	var hit := FxKit.pulse(progress, IMPACT - 0.02, IMPACT + 0.03, 0.4)
	FxKit.glint(canvas, centre + Vector2(-size * 0.2, -size * 0.25).rotated(tilt), size * 0.9 * hit, 0.3, IVORY, hit)


## The hit: a white core and a wider gold bloom, gone by 35%.
static func _flash(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var hit := FxKit.pulse(progress, IMPACT - 0.02, IMPACT + 0.02, 0.35)
	if hit <= 0.0:
		return
	CircleStamp.disc(canvas, at, radius * 0.75 * hit, Color(GOLD, hit * 0.35))
	CircleStamp.disc(canvas, at, radius * 0.4 * hit, Color(Color.WHITE, hit * 0.8))


## Three chevron arcs shoved out along the bash, each a wide steel band with
## a white edge, thinning and opening as they travel.
static func _shock(canvas: CanvasItem, at: Vector2, radius: float, dir: Vector2, progress: float) -> void:
	var origin := at - dir * radius * 0.25
	for i in 3:
		var t := FxKit.phase(progress, IMPACT + i * 0.07, 0.62 + i * 0.07)
		if t <= 0.0 or t >= 1.0:
			continue
		var reach := radius * (0.35 + 0.95 * FxKit.ease_out(t))
		var sweep := 1.5 - 0.5 * t
		var fade := 1.0 - t
		FxBladeShapes.arc(canvas, origin, dir.angle(), sweep, reach, 10, 20.0 * fade + 4.0, Color(STEEL, fade * 0.5))
		FxBladeShapes.arc(canvas, origin, dir.angle(), sweep * 0.9, reach, 10, 6.0, Color(Color.WHITE, fade * 0.95))


## Dust kicked forward on the impact, puffs swelling as they skid out.
static func _dust(canvas: CanvasItem, at: Vector2, radius: float, dir: Vector2, progress: float, seed: int) -> void:
	var t := FxKit.phase(progress, IMPACT, 0.9)
	if t <= 0.0 or t >= 1.0:
		return
	var rng := FxKit.rng_seeded(seed)
	for i in 7:
		var heading := dir.rotated(rng.randf_range(-1.3, 1.3))
		var reach := radius * rng.randf_range(0.5, 1.0) * FxKit.ease_out(t)
		var size := radius * (0.12 + 0.18 * t) * rng.randf_range(0.7, 1.2)
		CircleStamp.disc(canvas, at + heading * reach, size, Color(DUST, (1.0 - t) * 0.4))


## Three gold stars wheeling in a flat ellipse over the struck spot.
static func _dazed(canvas: CanvasItem, at: Vector2, width: float, progress: float, elapsed_ms: int) -> void:
	var alpha := FxKit.phase(progress, 0.25, 0.4) * (1.0 - FxKit.phase(progress, 0.8, 1.0))
	if alpha <= 0.0:
		return
	for i in 3:
		var angle := elapsed_ms * 0.009 + TAU * i / 3.0
		var spot := at + Vector2(cos(angle) * width, sin(angle) * width * 0.35)
		var size := maxf(5.0, width * 0.4) * (0.8 + 0.2 * sin(angle))
		Fx.polygon(canvas, _star5(spot, size * 1.3, angle), Color(INK, alpha * 0.6))
		Fx.polygon(canvas, _star5(spot, size, angle), Color(GOLD, alpha))
		CircleStamp.disc(canvas, spot, size * 0.25, Color(Color.WHITE, alpha))


static func _star5(at: Vector2, size: float, turn: float) -> Array:
	var points: Array = []
	for k in 10:
		points.append(Fx.polar(at, turn + k * PI / 5.0 - PI * 0.5, size * (1.0 if k % 2 == 0 else 0.45)))
	return points
