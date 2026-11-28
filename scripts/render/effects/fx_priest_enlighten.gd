class_name FxPriestEnlighten
extends RefCounted

## PRIEST_ENLIGHTEN (98): revelation. Shafts of light fan out from the
## Priest and turn slowly, a white wash sweeps out to the range blowing the
## dark specks it meets out past the edge, and a halo lifts from the ground
## to hang over the Priest's head as the light settles.

const WHITE := Color("ffffff")
const LIGHT := Color("fff3c4")
const GOLD := Color("f2d27a")
const SPECK := Color("2a2433")
const SHAFTS := 12
const SPECKS := 24
const WASH_END := 0.45
const SQUASH := 0.38


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 40.0)
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	var wash := radius * FxKit.ease_out(FxKit.phase(progress, 0.0, WASH_END))
	_shafts(canvas, at, radius, progress, fade, elapsed_ms)
	_wash(canvas, at, wash, progress)
	_specks(canvas, fx, at, radius, wash, progress)
	_halo(canvas, at, radius, progress, fade)


## Wedges of light from the centre, bright at the root and fading to
## nothing at the tip, of uneven reach, turning slowly and shimmering.
static func _shafts(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float,
		elapsed_ms: int) -> void:
	var grow := FxKit.ease_out(FxKit.phase(progress, 0.05, 0.4)) * fade
	if grow <= 0.0:
		return
	var turn := elapsed_ms * 0.0005
	for i in SHAFTS:
		var angle := turn + TAU * i / SHAFTS
		var half := 0.1 if i % 2 == 0 else 0.06
		var reach := radius * (1.0 - 0.35 * ((i * 7) % 5) / 4.0) * grow
		var shimmer := 0.7 + 0.3 * sin(elapsed_ms * 0.006 + i * 1.7)
		var points := PackedVector2Array([at, Fx.polar(at, angle - half, reach), Fx.polar(at, angle + half, reach)])
		var root := Color(LIGHT, 0.45 * shimmer * grow)
		var tip := Color(LIGHT, 0.0)
		canvas.draw_polygon(points, PackedColorArray([root, tip, tip]))
	Fx.dot(canvas, at, radius * 0.5 * grow, Color(LIGHT, 0.3 * grow))


## The wash: a white disc spreading to the range with a bright leading
## edge, gone soon after it arrives.
static func _wash(canvas: CanvasItem, at: Vector2, wash: float, progress: float) -> void:
	var alive := 1.0 - FxKit.phase(progress, WASH_END - 0.1, WASH_END + 0.2)
	if alive <= 0.0 or wash < 1.0:
		return
	Fx.dot(canvas, at, wash * 2.0, Color(WHITE, 0.16 * alive))
	Fx.ring(canvas, at, wash, 10.0, Color(LIGHT, 0.4 * alive))
	Fx.ring(canvas, at, wash, 2.5, Color(WHITE, 0.95 * alive))


## Dark specks of shadow sitting in the area until the wash reaches them,
## then flung outward past the range, thinning to nothing.
static func _specks(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, wash: float,
		progress: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in SPECKS:
		var angle := rng.randf() * TAU
		var dist := radius * rng.randf_range(0.2, 0.9)
		var size := rng.randf_range(4.5, 7.5)
		var hit_at := WASH_END * (1.0 - sqrt(1.0 - dist / radius))
		var t := FxKit.phase(progress, hit_at, hit_at + 0.35)
		if t >= 1.0:
			continue
		var out := Vector2(cos(angle), sin(angle))
		var flung := dist + radius * 0.6 * FxKit.ease_out(t)
		var spot := at + out * flung
		var appear := FxKit.phase(progress, 0.0, 0.08)
		if t > 0.0:
			Fx.line(canvas, spot - out * 14.0 * (1.0 - t), spot, size * 1.2, Color(SPECK, 0.45 * (1.0 - t)))
		Fx.dot(canvas, spot, size * 1.6 * (1.0 - 0.6 * t), Color(LIGHT, 0.2 * appear * (1.0 - t)))
		Fx.dot(canvas, spot, size * (1.0 - 0.6 * t), Color(SPECK, 0.95 * appear * (1.0 - t)))


## A halo rising from the Priest's feet to hang over their head, flattened
## as if seen from the side, brightening as it settles.
static func _halo(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var rise := FxKit.ease_out(FxKit.phase(progress, 0.15, 0.6))
	if rise <= 0.0:
		return
	var size := radius * 0.14
	var spot := at + Vector2(0.0, 6.0 - rise * 24.0)
	var alpha := rise * fade
	var points := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		points.append(spot + Vector2(cos(a) * size, sin(a) * size * SQUASH))
	Fx.dot(canvas, spot, size * 3.0, Color(LIGHT, 0.25 * alpha))
	Fx.polyline(canvas, points, 6.0, Color(GOLD, 0.5 * alpha))
	Fx.polyline(canvas, points, 2.0, Color(WHITE, alpha))
	var settle := FxKit.pulse(progress, 0.5, 0.6, 0.8)
	FxKit.glint(canvas, spot, size * 2.5 * settle, 0.0, LIGHT, settle * fade)
