class_name FxNecromancerWither
extends RefCounted

## NECROMANCER_WITHER (92): a wave of decay rolling out over the ground. A
## blight front expands to the range with tendrils curling off its edge,
## the ground behind it splits in jagged branching cracks, flakes of ash
## lift from the dead earth, and a pentagram sigil turns slowly at the
## heart until it all crumbles away.

const ROT := Color("6b7a2a")
const BLIGHT := Color("c2d14e")
const ASH := Color("a49c8c")
const DARK := Color("1e1a12")
const SIGIL := Color("9a4fd0")
const CRACKS := 9
const CRACK_STEPS := 6
const TENDRILS := 14
const FLAKES := 28
const FRONT_END := 0.55


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 40.0)
	var front := radius * FxKit.ease_out(FxKit.phase(progress, 0.0, FRONT_END))
	var fade := 1.0 - FxKit.phase(progress, 0.7, 1.0)
	Fx.dot(canvas, at, front * 2.0, Color(DARK, 0.28 * fade))
	_cracks(canvas, fx, at, radius, front, fade)
	_ash(canvas, fx, at, front, progress, fade)
	_front(canvas, at, radius, front, progress, elapsed_ms)
	_sigil(canvas, at, radius * 0.22, progress, fade, elapsed_ms)


## The decay front: a dark band with a blighted edge, and tendrils curling
## outward off it, gone once the front stops.
static func _front(canvas: CanvasItem, at: Vector2, radius: float, front: float, progress: float,
		elapsed_ms: int) -> void:
	var alive := 1.0 - FxKit.phase(progress, FRONT_END - 0.1, FRONT_END + 0.15)
	if alive <= 0.0 or front < 2.0:
		return
	Fx.ring(canvas, at, front, 14.0, Color(ROT, 0.35 * alive))
	Fx.ring(canvas, at, front, 3.0, Color(BLIGHT, 0.85 * alive))
	Fx.ring(canvas, at, front * 0.93, 2.0, Color(DARK, 0.6 * alive))
	var sway := elapsed_ms * 0.004
	for i in TENDRILS:
		var angle := TAU * i / TENDRILS + 0.2 * sin(sway + i)
		var points := PackedVector2Array()
		var length := radius * 0.12
		var curl := 1.0 if i % 2 == 0 else -1.0
		for j in 7:
			var f := float(j) / 6.0
			var bend := angle + curl * f * f * 2.4
			points.append(Fx.polar(at, angle, front) + Vector2(cos(bend), sin(bend)) * length * f)
		Fx.polyline(canvas, points, 3.0, Color(ROT, 0.8 * alive))
		Fx.polyline(canvas, points, 1.2, Color(BLIGHT, alive))


## Jagged cracks from the centre, revealed as the front passes over them,
## each with one branch forking off partway.
static func _cracks(canvas: CanvasItem, fx: Dictionary, at: Vector2, radius: float, front: float,
		fade: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx))
	for i in CRACKS:
		var angle := TAU * i / CRACKS + rng.randf_range(-0.2, 0.2)
		var length := radius * rng.randf_range(0.6, 0.95)
		var points := PackedVector2Array([at + Vector2(cos(angle), sin(angle)) * radius * 0.12])
		var heading := angle
		for j in CRACK_STEPS:
			heading += rng.randf_range(-0.45, 0.45)
			var next := points[j] + Vector2(cos(heading), sin(heading)) * length / CRACK_STEPS
			if next.distance_to(at) > front:
				break
			points.append(next)
		var fork_at := rng.randi_range(2, CRACK_STEPS - 2)
		var fork_turn := rng.randf_range(0.5, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)
		Fx.polyline(canvas, points, 8.0, Color(ROT, 0.35 * fade))
		Fx.polyline(canvas, points, 4.5, Color(DARK, 0.9 * fade))
		Fx.polyline(canvas, points, 1.8, Color(BLIGHT, 0.7 * fade))
		if points.size() > fork_at + 1:
			var origin := points[fork_at]
			var fork_dir := (points[fork_at + 1] - origin).normalized().rotated(fork_turn)
			var tip := origin + fork_dir * length * 0.25
			if tip.distance_to(at) <= front:
				Fx.line(canvas, origin, tip, 3.5, Color(DARK, 0.9 * fade))
				Fx.line(canvas, origin, tip, 1.4, Color(BLIGHT, 0.55 * fade))


## Ash flakes lifting off ground the front has already crossed, swaying
## as they rise and thin out.
static func _ash(canvas: CanvasItem, fx: Dictionary, at: Vector2, front: float, progress: float,
		fade: float) -> void:
	var rng := FxKit.rng_seeded(FxKit.seed_of(fx) + 7)
	for i in FLAKES:
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * 0.95
		var born := dist * FRONT_END * 0.9 + rng.randf_range(0.0, 0.15)
		var t := FxKit.phase(progress, born, born + 0.45)
		var phase := rng.randf() * TAU
		if t <= 0.0 or t >= 1.0 or dist * front <= 0.0:
			continue
		var base := Fx.polar(at, angle, dist * front)
		var flake := base + Vector2(sin(t * 6.0 + phase) * 3.0, -t * 22.0)
		var size := 5.0 * (1.0 - t) + 2.0
		Fx.dot(canvas, flake, size, Color(ASH, 0.9 * (1.0 - t) * fade))


## A pentagram in a ring, drawn on in the first beat and turning slowly.
static func _sigil(canvas: CanvasItem, at: Vector2, size: float, progress: float, fade: float,
		elapsed_ms: int) -> void:
	var shown := FxKit.ease_out(FxKit.phase(progress, 0.0, 0.15)) * fade
	if shown <= 0.0:
		return
	var turn := elapsed_ms * 0.0008 - PI * 0.5
	var corners := PackedVector2Array()
	for k in 5:
		corners.append(Fx.polar(at, turn + TAU * k / 5.0, size))
	var star := PackedVector2Array()
	for k in 6:
		star.append(corners[(k * 2) % 5])
	var pentagon := corners.duplicate()
	pentagon.append(corners[0])
	Fx.dot(canvas, at, size * 2.6, Color(SIGIL, 0.15 * shown))
	Fx.ring(canvas, at, size * 1.15, 2.0, Color(SIGIL, 0.8 * shown))
	Fx.polyline(canvas, pentagon, 1.5, Color(SIGIL, 0.6 * shown))
	Fx.polyline(canvas, star, 4.0, Color(SIGIL, 0.35 * shown))
	Fx.polyline(canvas, star, 1.5, Color(BLIGHT, 0.9 * shown))
