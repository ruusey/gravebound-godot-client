class_name FxEnrageBurst
extends RefCounted

## ENRAGE_BURST (69): an enemy entering its enrage or next phase. A white-hot
## core flash for the first quarter, two red-orange shock rings snapping out
## past the radius one after the other, sixteen flame streaks bursting
## outward, and embers flung off the rim. Radial, centred on the enemy.

const RED := Color("ff3020")
const ORANGE := Color("ff8a1a")
const HOT := Color("fff0b0")
const STREAKS := 16
const FLASH_END := 0.25


static func ring_radius(radius: float, wave: float) -> float:
	return radius * 1.2 * sqrt(wave)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 24.0)
	var alpha := 1.0 - progress
	if progress < FLASH_END:
		var flash := 1.0 - progress / FLASH_END
		CircleStamp.disc(canvas, at, radius * (0.35 + 0.25 * progress), Color(ORANGE, flash * 0.55))
		CircleStamp.disc(canvas, at, radius * (0.2 + 0.2 * progress), Color(HOT, flash * 0.9))
	for delay in [0.0, 0.15]:
		var wave := Fx.wave(progress, delay)
		if wave < 0.0:
			continue
		Fx.ring(canvas, at, ring_radius(radius, wave), 10.0 * (1.0 - wave) + 2.0, Color(RED, (1.0 - wave) * 0.9))
		Fx.ring(canvas, at, ring_radius(radius, wave) * 0.94, 3.0, Color(ORANGE, (1.0 - wave) * 0.8))
	var reach := radius * (0.45 + 0.75 * sqrt(progress))
	for i in STREAKS:
		var angle := i * TAU / STREAKS + elapsed_ms * 0.0004
		var length := reach * (0.75 + 0.25 * sin(i * 2.3))
		var along := Vector2(cos(angle), sin(angle))
		var across := along.orthogonal() * 6.0 * Fx.S
		var root := at + along * radius * 0.25
		var tip := at + along * length
		Fx.polygon(canvas, [root + across, tip, root - across], Color(ORANGE if i % 2 == 0 else RED, alpha * 0.85))
	var rng := Fx.rng_for(fx, 0)
	for i in 12:
		var angle := rng.randf() * TAU
		var spark := Fx.polar(at, angle, radius * (0.3 + progress * rng.randf_range(0.9, 1.4)))
		Fx.dot(canvas, spark, 2.5, Color(HOT, alpha))
