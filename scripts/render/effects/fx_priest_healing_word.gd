class_name FxPriestHealingWord
extends RefCounted

## PRIEST_HEALING_WORD (96): a spoken word of healing carrying outward. Four
## dashed rings ripple from the Priest to the range in turn like sound, each
## band of dashes turning the opposite way to the one before, a soft white
## flash at the cast, and sky-blue sparkles rising inside.

const SKY := Color("8fd4ff")
const PALE := Color("e6f6ff")
const DEEP := Color("3a7fc0")
const RIPPLES := 4
const DASHES := 16
const SPARKLES := 14


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 32.0)
	var fade := 1.0 - FxKit.phase(progress, 0.7, 1.0)
	Fx.ring(canvas, at, radius, 2.0, Color(SKY, 0.45 * fade))
	for k in RIPPLES:
		_ripple(canvas, at, radius, progress, k)
	_sparkles(canvas, fx, at, radius, progress)
	var flash := 1.0 - FxKit.phase(progress, 0.0, 0.2)
	Fx.dot(canvas, at, radius * 0.6 * flash, Color(PALE, 0.7 * flash))
	FxKit.glint(canvas, at, radius * 0.5 * flash, 0.0, PALE, flash)


## One ripple: a ring of dashes widening from the centre to the range,
## dashes lengthening as it goes, fading as it arrives.
static func _ripple(canvas: CanvasItem, at: Vector2, radius: float, progress: float, k: int) -> void:
	var t := FxKit.phase(progress, k * 0.12, k * 0.12 + 0.5)
	if t <= 0.0 or t >= 1.0:
		return
	var r := radius * (0.15 + 0.85 * FxKit.ease_out(t))
	var alpha := sin(t * PI) * (1.0 - 0.15 * k)
	var spin := (1.0 if k % 2 == 0 else -1.0) * t * 0.6 + k * 0.2
	var fill := 0.35 + 0.3 * t
	Fx.ring(canvas, at, r, 14.0, Color(SKY, 0.12 * alpha))
	for i in DASHES:
		var a := spin + TAU * i / DASHES
		var end := a + TAU / DASHES * fill
		Fx.arc(canvas, at, a, end, r, 3, 9.0, Color(DEEP, 0.45 * alpha))
		Fx.arc(canvas, at, a, end, r, 3, 5.0, Color(SKY, 0.9 * alpha))
		Fx.arc(canvas, at, a, end, r, 3, 2.0, Color(PALE, alpha))


## Small four-point sparkles rising and twinkling.
static func _sparkles(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, progress: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in SPARKLES:
		var born := rng.randf_range(0.05, 0.5)
		var spot := Fx.polar(at, rng.randf() * TAU, sqrt(rng.randf()) * radius * 0.85)
		var rise := rng.randf_range(12.0, 28.0)
		var twinkle := rng.randf() * TAU
		var t := FxKit.phase(progress, born, born + 0.45)
		if t <= 0.0 or t >= 1.0:
			continue
		var alpha := sin(t * PI) * (0.6 + 0.4 * sin(t * 18.0 + twinkle))
		FxKit.glint(canvas, spot - Vector2(0.0, rise * t), 12.0, 0.0, SKY, alpha)
