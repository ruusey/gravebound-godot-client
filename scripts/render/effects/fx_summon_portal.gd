class_name FxSummonPortal
extends RefCounted

## SUMMON_PORTAL (70): an enemy tearing open a rift to call in minions. The
## portal irises open over the first quarter, swirls -- a void disc, a
## violet rim, three spiral arms and motes drawn inward, eight runes turning
## outside it -- and from 80% collapses to a point with a last flash.

const VOID := Color("120818")
const VIOLET := Color("9a4dff")
const PALE := Color("e0c8ff")
const OPEN_END := 0.25
const CLOSE_START := 0.8
const ARMS := 3
const ARM_POINTS := 12


## How open the rift is, 0..1: an eased open, a hold, a quick close.
static func openness(progress: float) -> float:
	if progress < OPEN_END:
		return ease(progress / OPEN_END, 0.4)
	if progress > CLOSE_START:
		return 1.0 - ease((progress - CLOSE_START) / (1.0 - CLOSE_START), 2.5)
	return 1.0


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var size: float = maxf(fx["radius"], 20.0) * openness(progress)
	if size < 1.0:
		return
	var spin := elapsed_ms * 0.004
	CircleStamp.disc(canvas, at, size * 1.15, Color(VIOLET, 0.18))
	CircleStamp.disc(canvas, at, size, Color(VOID, 0.92))
	for arm in ARMS:
		var points := PackedVector2Array()
		for i in ARM_POINTS:
			var t := float(i) / (ARM_POINTS - 1)
			points.append(Fx.polar(at, spin + arm * TAU / ARMS + t * 2.6, size * (1.0 - t * 0.9)))
		Fx.polyline(canvas, points, 3.0, Color(VIOLET, 0.85))
	Fx.ring(canvas, at, size, 5.0, Color(VIOLET, 0.95))
	Fx.ring(canvas, at, size * 0.97, 2.0, Color(PALE, 0.8))
	for i in 10:
		var phase := fmod(elapsed_ms * 0.0012 + i * 0.1, 1.0)
		var mote := Fx.polar(at, i * 2.4 - spin * 1.5, size * 1.4 * (1.0 - phase))
		Fx.dot(canvas, mote, 2.5, Color(PALE, phase * 0.9))
	for i in 8:
		var rune := Fx.polar(at, i * TAU / 8.0 - spin * 0.5, size * 1.3)
		var r := 3.5 * Fx.S
		Fx.polygon(canvas, [rune + Vector2(0, -r * 1.6), rune + Vector2(r, 0), rune + Vector2(0, r * 1.6),
			rune + Vector2(-r, 0)], Color(PALE, 0.75))
	if progress > CLOSE_START + 0.1:
		var flash := 1.0 - (progress - CLOSE_START - 0.1) / (1.0 - CLOSE_START - 0.1)
		CircleStamp.disc(canvas, at, maxf(fx["radius"], 20.0) * 0.5, Color(PALE, flash * 0.6))
