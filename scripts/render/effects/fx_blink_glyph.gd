class_name FxBlinkGlyph
extends RefCounted

## BLINK_GLYPH (20): a violet teleport glyph flashing where a blink leaves
## or lands. A white-violet flash bursts from the centre in the first
## fifth while the glyph opens over the first half of its life: a dark
## portal inside a thick glowing violet rim, a six-pointed star in an inner
## rune ring turning one way and six diamond runes turning the other. A
## column of light shoots up out of the middle and thins away, with violet
## motes streaming up it.

const VIOLET := Color("9040ff")
const BRIGHT := Color("c880ff")
const VOID := Color("1a0a30")
const RUNES := 6
const FLASH_END := 0.2


## The ring opens from 40% to 110% of the radius by halfway, then holds.
static func ring_radius(radius: float, progress: float) -> float:
	return radius * (0.4 + minf(progress * 2.0, 1.0) * 0.7)


## The light column's height over the glyph's radius: shooting up to 1.8
## of it by 15%, then holding.
static func column_height(ring: float, progress: float) -> float:
	return ring * 1.8 * sqrt(minf(progress / 0.15, 1.0))


## The column's strength: full while it shoots up, thinning out by 70%.
static func column_strength(progress: float) -> float:
	return clampf(1.0 - (progress - 0.15) / 0.55, 0.0, 1.0)


## A six-pointed star as two closed triangles, `reach` to each point.
static func hexagram(at: Vector2, reach: float, turn: float) -> Array:
	var up := PackedVector2Array()
	var down := PackedVector2Array()
	for k in 4:
		up.append(Fx.polar(at, turn + k * TAU / 3.0, reach))
		down.append(Fx.polar(at, turn + PI + k * TAU / 3.0, reach))
	return [up, down]


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var alpha := 1.0 - progress
	if alpha <= 0.001:
		return
	var ring := ring_radius(maxf(fx["radius"], 16.0), progress)
	CircleStamp.disc(canvas, at, ring * 1.12, Color(VIOLET, alpha * 0.18))
	CircleStamp.disc(canvas, at, ring, Color(VOID, alpha * 0.7))
	Fx.ring(canvas, at, ring, 10.0, Color(VIOLET, alpha * 0.55))
	Fx.ring(canvas, at, ring, 4.0, Color(BRIGHT, alpha))
	Fx.ring(canvas, at, ring, 1.5, Color(Color.WHITE, alpha * 0.8))
	var inner := ring * 0.7
	Fx.ring(canvas, at, inner, 3.0, Color(VIOLET, alpha * 0.9))
	for triangle in hexagram(at, inner, elapsed_ms * 0.0025):
		Fx.polyline(canvas, triangle, 5.0, Color(VIOLET, alpha * 0.8))
		Fx.polyline(canvas, triangle, 2.0, Color(BRIGHT, alpha))
	var rune_size := maxf(3.0, ring * 0.09)
	for i in RUNES:
		var angle := float(i) / RUNES * TAU - elapsed_ms * 0.003
		var rune := Fx.polar(at, angle, ring * 0.86)
		_quad(canvas, FxBladeShapes.lens(rune, angle, rune_size, rune_size * 0.55), Color(BRIGHT, alpha))
		Fx.dot(canvas, rune, 2.0, Color(Color.WHITE, alpha))
	_column(canvas, fx, at, ring, progress, elapsed_ms)
	if progress < FLASH_END:
		var flash := 1.0 - progress / FLASH_END
		CircleStamp.disc(canvas, at, ring * (0.5 + 0.6 * (1.0 - flash)), Color(BRIGHT, flash * 0.6))
		CircleStamp.disc(canvas, at, ring * 0.35, Color(Color.WHITE, flash * 0.9))


## The column of light standing up out of the glyph: a violet glow round
## a white core, both narrowing to the top, and motes rising up it.
static func _column(canvas: CanvasItem, fx: Dictionary, at: Vector2, ring: float, progress: float,
		elapsed_ms: int) -> void:
	var strength := column_strength(progress) * (1.0 - progress)
	if strength <= 0.001:
		return
	var height := column_height(ring, progress)
	var top := at - Vector2(0.0, height)
	var width := ring * 0.3 * (0.5 + 0.5 * strength)
	Fx.polygon(canvas, [at + Vector2(-width, 0.0), top + Vector2(-width * 0.4, 0.0),
		top + Vector2(width * 0.4, 0.0), at + Vector2(width, 0.0)], Color(VIOLET, strength * 0.45))
	Fx.polygon(canvas, [at + Vector2(-width * 0.35, 0.0), top + Vector2(-width * 0.1, 0.0),
		top + Vector2(width * 0.1, 0.0), at + Vector2(width * 0.35, 0.0)], Color(Color.WHITE, strength * 0.85))
	Fx.dot(canvas, at, ring * 0.5 / Fx.S, Color(BRIGHT, strength * 0.35))
	var rng := Fx.rng_for(fx, 0)
	for k in 8:
		var drift := rng.randf_range(-1.0, 1.0) * width * 1.6
		var rise := fmod(rng.randf() + elapsed_ms * 0.0012, 1.0)
		Fx.dot(canvas, at + Vector2(drift * (1.0 - rise * 0.5), -height * rise), 2.5,
			Color(BRIGHT, strength * (1.0 - rise)))


## A rune's diamond filled as a quad: small enough that the polygon path's
## triangulator rejects it far from the world origin, and a convex quad
## needs no triangulating.
static func _quad(canvas: CanvasItem, points: Array, colour: Color) -> void:
	if colour.a > 0.001:
		canvas.draw_primitive(PackedVector2Array(points), PackedColorArray([colour, colour, colour, colour]),
			PackedVector2Array())
