class_name FxCultistEnchantWeapon
extends RefCounted

## CULTIST_ENCHANT_WEAPON (106): the Cultist binds a curse into their blade.
## Five runes, each a violet glyph in a crimson seal, wheel round the body,
## spinning faster as they spiral inward, each dragging a fading arc. They
## meet at the centre in a violet-crimson flash, and a blade of light
## stands up out of it, burning violet, shedding crimson motes upward
## before it fades.

const VIOLET := Color("a855f7")
const VIOLET_DARK := Color("3b0f5c")
const CRIMSON := Color("e0244a")
const PALE := Color("f3e8ff")
const RUNES := 5
const MEET := 0.62
const GLYPHS := [
	[Vector2(-0.5, -0.7), Vector2(0.5, -0.7), Vector2(-0.5, 0.7), Vector2(0.5, 0.7)],
	[Vector2(0.0, -0.8), Vector2(0.0, 0.8), Vector2(0.55, 0.2), Vector2(-0.3, -0.2)],
	[Vector2(-0.6, 0.6), Vector2(0.0, -0.7), Vector2(0.6, 0.6), Vector2(-0.4, 0.0)],
	[Vector2(-0.5, -0.7), Vector2(0.5, 0.0), Vector2(-0.5, 0.7), Vector2(-0.5, -0.7)],
	[Vector2(0.0, -0.8), Vector2(0.0, 0.8), Vector2(-0.55, 0.15), Vector2(0.55, -0.15)],
]


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 20.0)
	_runes(canvas, at, radius, progress)
	_flash(canvas, at, radius, progress)
	_blade(canvas, at, radius, progress, FxKit.seed_of(fx))


## The orbit: in fast at the start, then wheeling inward ever quicker until
## the five meet at the centre.
static func _runes(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	if progress >= MEET:
		return
	var t := FxKit.phase(progress, 0.0, MEET)
	var appear := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.12))
	var orbit := radius * 1.35 * (1.0 - FxKit.ease_in(t)) * (0.6 + 0.4 * appear)
	var turn := t * t * TAU * 1.6
	var size := clampf(radius * 0.26, 7.0, 16.0) * (1.0 - 0.4 * t)
	for i in RUNES:
		var angle := turn + TAU * i / RUNES - PI * 0.5
		var spot := Fx.polar(at, angle, orbit)
		Fx.arc(canvas, at, angle - 0.6 - t * 0.6, angle, orbit, 8, 4.0, Color(CRIMSON, 0.55 * appear))
		_rune(canvas, spot, size, GLYPHS[i], appear)


## One rune: a dark seal disc with a crimson rim and a violet glyph lit pale
## down its middle.
static func _rune(canvas: CanvasItem, at: Vector2, size: float, glyph: Array, alpha: float) -> void:
	CircleStamp.disc(canvas, at, size * 1.6, Color(VIOLET, alpha * 0.2))
	CircleStamp.disc(canvas, at, size, Color(VIOLET_DARK, alpha * 0.9))
	Fx.ring(canvas, at, size, 3.0, Color(CRIMSON, alpha), 16)
	var points := PackedVector2Array()
	for corner: Vector2 in glyph:
		points.append(at + corner * size * 0.7)
	Fx.polyline(canvas, points, 4.0, Color(VIOLET, alpha))
	Fx.polyline(canvas, points, 1.5, Color(PALE, alpha))


## The meeting: a crimson bloom round a violet core and a white heart, a
## ring thrown off.
static func _flash(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	var flash := FxKit.pulse(progress, MEET - 0.03, MEET + 0.02, 0.85)
	if flash <= 0.0:
		return
	var t := FxKit.phase(progress, MEET, 0.9)
	CircleStamp.disc(canvas, at, radius * 1.1 * flash, Color(CRIMSON, flash * 0.3))
	CircleStamp.disc(canvas, at, radius * 0.65 * flash, Color(VIOLET, flash * 0.55))
	CircleStamp.disc(canvas, at, radius * 0.3 * flash, Color(Color.WHITE, flash * 0.9))
	Fx.ring(canvas, at, radius * (0.4 + 1.0 * FxKit.ease_out(t)), 6.0 * (1.0 - t) + 1.0, Color(VIOLET, 1.0 - t))


## The blade of light rising out of the flash: a violet wedge with a pale
## core and a crimson guard, motes climbing off it as it burns out.
static func _blade(canvas: CanvasItem, at: Vector2, radius: float, progress: float, seed: int) -> void:
	var rise := FxKit.ease_out(FxKit.phase(progress, MEET, MEET + 0.12))
	if rise <= 0.0:
		return
	var alpha := 1.0 - FxKit.phase(progress, 0.8, 1.0)
	var length := clampf(radius * 1.3, 26.0, 72.0) * rise
	var width := clampf(radius * 0.22, 6.0, 14.0)
	var hilt := at + Vector2(0.0, width * 0.8)
	var tip := hilt + Vector2(0.0, -length)
	FxKit.taper(canvas, hilt, tip, width * 2.4, 0.0, Color(VIOLET, alpha * 0.3))
	FxKit.taper(canvas, hilt, tip, width, 0.0, Color(VIOLET, alpha * 0.95))
	FxKit.taper(canvas, hilt, tip, width * 0.35, 0.0, Color(PALE, alpha))
	Fx.line(canvas, hilt - Vector2(width * 1.2, 0.0), hilt + Vector2(width * 1.2, 0.0), width * 1.2, Color(CRIMSON, alpha))
	var rng := FxKit.rng_seeded(seed)
	for i in 8:
		var offset := rng.randf_range(0.0, 1.0)
		var climb := fmod(FxKit.phase(progress, MEET, 1.0) * 1.5 + offset, 1.0)
		var spot := hilt.lerp(tip, rng.randf_range(0.1, 0.9)) + Vector2(rng.randf_range(-1.0, 1.0) * width * 1.5,
			-climb * radius * 0.6)
		CircleStamp.disc(canvas, spot, 2.5, Color(CRIMSON if i % 2 == 0 else VIOLET, alpha * (1.0 - climb)))
