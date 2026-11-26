class_name FxBeastClaws
extends RefCounted

## BEAST_CLAWS (28): a beast's claws raking through. Two rakes cross over
## the spot, the second a moment after the first and slanting the other
## way, each four parallel gouges torn across in one fast swipe -- a dark
## wound-red furrow under a tan claw mark with a white leading edge,
## swelling through the middle and tapering to a point at both ends, the
## middle claws longest -- with a white glint at each claw's tip as it
## tears. The marks linger, then fade from 55%. Turned to the strike's
## facing, so a player's rake follows their aim.

const RAKES := 2
const GOUGES := 4
const STEPS := 8
## When each rake starts and how long its swipe takes, as fractions of the effect.
const RAKE_GAP := 0.16
const SWIPE := 0.2
const WOUND := Color("4a1410")
const CLAW := Color("d8a868")


## How far rake `rake` has torn across, 0..1: fast out of the gate, easing
## as it finishes.
static func swipe(progress: float, rake: int) -> float:
	var t := clampf((progress - rake * RAKE_GAP) / SWIPE, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)


## The direction rake `rake` tears in: down-left across the facing, the
## second down-right.
static func rake_angle(facing: float, rake: int) -> float:
	return facing + (PI * 0.68 if rake == 0 else PI * 0.32)


## Gouge `g`'s length: the rake spans 1.9 of the radius, the outer claws
## a fifth shorter than the middle two.
static func gouge_length(radius: float, g: int) -> float:
	var off_centre := absf(g - (GOUGES - 1) * 0.5) / ((GOUGES - 1) * 0.5)
	return radius * 1.9 * (1.0 - 0.2 * off_centre)


static func strength(progress: float) -> float:
	return clampf((1.0 - progress) / 0.45, 0.0, 1.0)


## A gouge `length` long along `along`, `width` either side of its spine at
## the widest, bowed a little sideways, torn as far as `torn` of the way
## and coming to a point there, where the claw is.
static func gouge(centre: Vector2, along: Vector2, length: float, width: float, torn: float) -> Array:
	var across := along.orthogonal()
	var left: Array = []
	var right: Array = []
	for k in STEPS + 1:
		var u := torn * float(k) / STEPS
		var spine := centre + along * length * (u - 0.5) + across * sin(PI * u) * length * 0.07
		var half := width * pow(sin(PI * u), 0.6) if k < STEPS else 0.0
		left.append(spine + across * half)
		right.append(spine - across * half)
	right.reverse()
	return left + right.slice(1, right.size() - 1)


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 16.0)
	var alpha := strength(progress)
	if alpha <= 0.001:
		return
	var facing := Fx.facing(fx).angle()
	var spacing := radius * 0.24
	var width := maxf(2.5, radius * 0.075)
	for rake in RAKES:
		var torn := swipe(progress, rake)
		if torn < 0.15:
			continue
		var along := Vector2.from_angle(rake_angle(facing, rake))
		var across := along.orthogonal()
		for g in GOUGES:
			var centre := at + across * (g - (GOUGES - 1) * 0.5) * spacing
			var length := gouge_length(radius, g)
			Fx.polygon(canvas, gouge(centre, along, length, width + 2.0, torn), Color(WOUND, alpha * 0.9))
			var mark := gouge(centre, along, length, width, torn)
			Fx.polygon(canvas, mark, Color(CLAW, alpha))
			Fx.polyline(canvas, PackedVector2Array(mark.slice(1, STEPS)), 2.0, Color(Color.WHITE, alpha * 0.85))
			if torn < 1.0:
				Fx.dot(canvas, mark[STEPS], 5.0, Color(Color.WHITE, alpha))
