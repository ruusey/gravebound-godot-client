class_name FxWizardFrostSpike
extends RefCounted

## WIZARD_FROST_SPIKE (82): a glacial lance driven down into the target.
## A long ice lance falls from above and spears the centre; on impact a
## crown of jagged ice spikes erupts round it in two rings (the inner tall,
## the outer short), rime frost creeps out across the ground in a branching
## pattern, and at the end the spikes shatter into tumbling shards and a
## puff of snow.

const ICE := Color("a8e4ff")
const DEEP := Color("3a78c0")
const RIME := Color("dff6ff")
const WHITE := Color(1.0, 1.0, 1.0)
const INNER := 6
const OUTER := 9
const IMPACT := 0.18
const SHATTER := 0.7


static func draw(canvas: CanvasItem, fx: Dictionary, progress: float, _colour: Color, _elapsed_ms: int) -> void:
	var at: Vector2 = fx["pos"]
	var radius: float = maxf(fx["radius"], 32.0)
	var seed := FxKit.seed_of(fx)
	_rime(canvas, at, radius, progress, seed)
	_lance(canvas, at, radius, progress)
	if progress >= IMPACT:
		_crown(canvas, at, radius, progress, seed)
		var flash := 1.0 - FxKit.phase(progress, IMPACT, IMPACT + 0.12)
		Fx.dot(canvas, at, radius * 0.9 * flash, Color(RIME, 0.5 * flash))
		Fx.ring(canvas, at, radius * (0.2 + 0.9 * (1.0 - flash)), 4.0, Color(WHITE, flash))
	_shards(canvas, at, radius, progress, seed)


## The lance falling from high above and spearing the centre, then
## standing until the shatter.
static func _lance(canvas: CanvasItem, at: Vector2, radius: float, progress: float) -> void:
	if progress >= SHATTER:
		return
	var fall := FxKit.ease_in(FxKit.phase(progress, 0.0, IMPACT))
	var length := radius * 0.9
	var tip := at + Vector2(0.0, -radius * 1.3 * (1.0 - fall))
	var butt := tip + Vector2(0.0, -length)
	var half := Vector2(radius * 0.08, 0.0)
	if fall < 1.0:
		Fx.line(canvas, butt + Vector2(0.0, -radius * 0.5), butt, 3.0, Color(RIME, 0.5))
	Fx.polygon(canvas, [tip, butt.lerp(tip, 0.3) + half, butt, butt.lerp(tip, 0.3) - half], Color(DEEP, 0.95))
	Fx.polygon(canvas, [tip, butt.lerp(tip, 0.3) + half * 0.5, butt], Color(ICE, 1.0))
	Fx.line(canvas, butt, tip, 1.5, Color(WHITE, 0.9))


## Rime frost creeping out across the ground in branching fronds.
static func _rime(canvas: CanvasItem, at: Vector2, radius: float, progress: float, seed: int) -> void:
	var grow := FxKit.ease_out(FxKit.phase(progress, IMPACT, 0.55))
	if grow <= 0.0:
		return
	var fade := 1.0 - FxKit.phase(progress, 0.75, 1.0)
	Fx.dot(canvas, at, radius * 1.6 * grow, Color(ICE, 0.12 * fade))
	var rng := FxKit.rng_seeded(seed + 3)
	for i in 10:
		var angle := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
		var length := radius * rng.randf_range(0.75, 1.05) * grow
		var end := Fx.polar(at, angle, length)
		Fx.line(canvas, at, end, 2.0, Color(RIME, 0.55 * fade))
		for b in 3:
			var f := 0.35 + 0.2 * b
			var root := at.lerp(end, f)
			for s: float in [-1.0, 1.0]:
				Fx.line(canvas, root, Fx.polar(root, angle + s * 0.7, length * 0.18 * (1.0 - f * 0.5)), 1.5,
					Color(RIME, 0.45 * fade))


## The crown: two rings of jagged spikes erupting round the impact, each
## a faceted shard (dark side, lit side, white edge) rising out of the
## ground, staggered outward.
static func _crown(canvas: CanvasItem, at: Vector2, radius: float, progress: float, seed: int) -> void:
	if progress >= SHATTER:
		return
	var rng := FxKit.rng_seeded(seed)
	var spikes: Array = []
	for ring in 2:
		var count := INNER if ring == 0 else OUTER
		for i in count:
			var angle := TAU * (i + 0.5 * ring) / count + rng.randf_range(-0.15, 0.15)
			var dist := radius * (0.3 if ring == 0 else 0.62) * rng.randf_range(0.85, 1.1)
			var height := radius * (0.7 if ring == 0 else 0.4) * rng.randf_range(0.7, 1.15)
			var delay := IMPACT + 0.04 * ring + rng.randf_range(0.0, 0.04)
			spikes.append([angle, dist, height, delay])
	spikes.sort_custom(func(a: Array, b: Array) -> bool: return sin(a[0]) < sin(b[0]))
	for spike: Array in spikes:
		var angle: float = spike[0]
		var height: float = spike[2]
		var delay: float = spike[3]
		var rise := FxKit.ease_out(FxKit.phase(progress, delay, delay + 0.1))
		if rise * height < 2.0:
			continue
		var base := at + (Fx.polar(at, angle, spike[1]) - at) * Vector2(1.0, 0.65)
		var lean := Vector2(cos(angle), 0.0) * height * 0.35
		var tip := base + Vector2(0.0, -height * rise) + lean * rise
		var half := height * 0.2
		var left := base - Vector2(half, 0.0)
		var right := base + Vector2(half, 0.0)
		Fx.polygon(canvas, [left, tip, base + Vector2(0.0, 2.0)], Color(DEEP, 0.95))
		Fx.polygon(canvas, [base + Vector2(0.0, 2.0), tip, right], Color(ICE, 0.95))
		Fx.line(canvas, base, tip, 1.5, Color(WHITE, 0.85))


## The shatter: shards flung out and falling, plus a snow puff.
static func _shards(canvas: CanvasItem, at: Vector2, radius: float, progress: float, seed: int) -> void:
	var t := FxKit.phase(progress, SHATTER, 1.0)
	if t <= 0.0 or t >= 1.0:
		return
	Fx.dot(canvas, at, radius * (0.6 + 0.8 * t), Color(RIME, 0.35 * (1.0 - t)))
	var rng := FxKit.rng_seeded(seed + 9)
	for i in 22:
		var angle := rng.randf_range(0.0, TAU)
		var speed := radius * rng.randf_range(0.4, 1.0)
		var up := radius * rng.randf_range(0.2, 0.6)
		var pos := Fx.polar(at, angle, speed * FxKit.ease_out(t)) + Vector2(0.0, -up * 4.0 * t * (1.0 - t) + 10.0 * t)
		var spin := rng.randf_range(-6.0, 6.0) * t
		var size := rng.randf_range(5.0, 9.0)
		var along := Vector2(cos(spin), sin(spin)) * size
		Fx.polygon(canvas, [pos + along, pos + along.orthogonal() * 0.4, pos - along],
			Color(ICE if i % 2 == 0 else RIME, 1.0 - t))
