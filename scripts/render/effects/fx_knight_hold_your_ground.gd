class_name FxKnightHoldYourGround
extends RefCounted

## KNIGHT_HOLD_YOUR_GROUND (100): the Knight plants a line no one crosses. A
## greatsword drops point-first into the centre and bites the ground with a
## flash, a pillar of gold light and a ring of dust. Then eight shields
## drop one after another round the edge, each landing with a puff, and an
## iron chain draws itself through them link by link to close the circle.
## The wall holds, the sword's light breathing, then everything fades.

const STEEL := Color("c3ccd8")
const STEEL_DARK := Color("5d6878")
const GOLD := Color("f2c14e")
const INK := Color("181a22")
const IRON := Color("7f8794")
const DUST := Color("9a8e7c")
const SHIELDS := 8
const LINKS := 32
const STAB := 0.14


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 32.0)
	var fade := 1.0 - FxKit.phase(progress, 0.8, 1.0)
	var ring := radius * 0.85
	_ground(canvas, at, radius, progress, fade)
	_chain(canvas, at, ring, progress, fade)
	_shields(canvas, at, ring, radius, progress, fade)
	_sword(canvas, at, radius, progress, fade, elapsed_ms)


## The bite: dust thrown out in a ring and a faint gold ward on the ground
## that holds while the wall stands.
static func _ground(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float) -> void:
	var t := FxKit.phase(progress, STAB, 0.6)
	if t <= 0.0:
		return
	if t < 1.0:
		Fx.ring(canvas, at, radius * (0.15 + 0.55 * FxKit.ease_out(t)), 22.0 * (1.0 - t), Color(DUST, (1.0 - t) * 0.6))
	var ward := FxKit.phase(progress, 0.45, 0.6) * fade
	Fx.ring(canvas, at, radius * 0.85, 22.0, Color(GOLD, ward * 0.12))


## The sword: it falls in the first 14%, sinks a third of its blade into
## the ground, and stands with a breathing gold glow and a light pillar.
static func _sword(canvas: CanvasItem, at: Vector2, radius: float, progress: float, fade: float,
		elapsed_ms: int) -> void:
	var drop := FxKit.ease_in(FxKit.phase(progress, 0.0, STAB))
	var length := clampf(radius * 0.55, 28.0, 70.0)
	var tip := at + Vector2(0.0, -radius * 0.9 * (1.0 - drop))
	var hilt := tip + Vector2(0.0, -length)
	var alpha := FxKit.phase(progress, 0.0, 0.05) * fade
	var hit := FxKit.pulse(progress, STAB - 0.02, STAB + 0.02, 0.4)
	var breathe := 0.75 + 0.25 * sin(elapsed_ms * 0.006)
	var pillar := maxf(hit, FxKit.phase(progress, STAB, 0.3) * 0.35 * breathe) * fade
	FxKit.taper(canvas, at + Vector2(0.0, 4.0), at + Vector2(0.0, -radius * 1.2), length * 0.5, length * 0.15,
		Color(GOLD, pillar * 0.3))
	CircleStamp.disc(canvas, at, radius * 0.5 * hit, Color(Color.WHITE, hit * 0.7))
	var width := maxf(4.0, length * 0.14)
	FxKit.taper(canvas, hilt, tip, width * 1.4, 0.0, Color(INK, alpha * 0.85))
	FxKit.taper(canvas, hilt, tip, width, 0.0, Color(STEEL, alpha))
	FxKit.taper(canvas, hilt, tip, width * 0.35, 0.0, Color(Color.WHITE, alpha * 0.9))
	var guard := hilt + Vector2(0.0, length * 0.02)
	Fx.line(canvas, guard - Vector2(width * 1.5, 0.0), guard + Vector2(width * 1.5, 0.0), width * 1.6, Color(INK, alpha))
	Fx.line(canvas, guard - Vector2(width * 1.3, 0.0), guard + Vector2(width * 1.3, 0.0), width * 1.0, Color(GOLD, alpha))
	Fx.line(canvas, guard, guard - Vector2(0.0, width * 1.6), width * 1.0, Color(STEEL_DARK, alpha))
	CircleStamp.disc(canvas, guard - Vector2(0.0, width * 1.9), width * 0.45, Color(GOLD, alpha))
	FxKit.glint(canvas, guard, width * 3.0 * maxf(hit, 0.4 * breathe * FxKit.phase(progress, STAB, 0.3)), 0.0,
		Color("fff6e0"), alpha)


## Eight shields dropping round the edge in turn, clockwise from the top.
static func _shields(canvas: CanvasItem, at: Vector2, ring: float, radius: float, progress: float,
		fade: float) -> void:
	var size := clampf(radius * 0.22, 10.0, 30.0)
	for i in SHIELDS:
		var start := STAB + 0.03 + i * 0.035
		var t := FxKit.phase(progress, start, start + 0.08)
		if t <= 0.0:
			continue
		var angle := -PI * 0.5 + TAU * i / SHIELDS
		var spot := Fx.polar(at, angle, ring)
		var fall := FxKit.ease_in(t)
		var centre := spot + Vector2(0.0, -size * 1.6 * (1.0 - fall))
		FxKnightShieldBash.shield(canvas, centre, size, 0.0, t * fade)
		var puff := FxKit.phase(progress, start + 0.08, start + 0.3)
		if puff > 0.0 and puff < 1.0:
			CircleStamp.disc(canvas, spot + Vector2(0.0, size * 0.55), size * (0.4 + 0.6 * puff),
				Color(DUST, (1.0 - puff) * 0.5))


## The chain round the ring, drawn link by link once the shields are down:
## alternating round and edge-on links in iron with a bright top.
static func _chain(canvas: CanvasItem, at: Vector2, ring: float, progress: float, fade: float) -> void:
	var drawn := FxKit.ease_in_out(FxKit.phase(progress, 0.4, 0.62))
	if drawn <= 0.0:
		return
	var start := -PI * 0.5
	var links := int(LINKS * drawn)
	var link := TAU * ring / LINKS * 0.5
	Fx.arc(canvas, at, start, start + TAU * drawn, ring, maxi(2, links), 3.0, Color(INK, 0.6 * fade))
	for i in links:
		var angle := start + TAU * (i + 0.5) / LINKS
		var spot := Fx.polar(at, angle, ring)
		if i % 2 == 0:
			Fx.ring(canvas, spot, link * 0.75, 3.0, Color(INK, 0.8 * fade), 10)
			Fx.ring(canvas, spot, link * 0.7, 2.0, Color(IRON, fade), 10)
		else:
			var along := Vector2(-sin(angle), cos(angle)) * link * 0.6
			Fx.line(canvas, spot - along, spot + along, 5.0, Color(INK, 0.8 * fade))
			Fx.line(canvas, spot - along, spot + along, 2.5, Color(STEEL, fade))
