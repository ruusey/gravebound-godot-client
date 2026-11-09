class_name ProjectileMotion
extends RefCounted

## The deterministic integrator -- the bandwidth trick the protocol is built on.
##
## Bullet positions are never streamed. NetBullet carries the full spawn
## parameter set once and both sides then run this same integration, so a
## bullet costs one packet instead of one packet per tick. That only holds if
## this matches com.gravebound.game.entity.Bullet exactly.
##
## Every step scales by `bullet_scale = dt * 64`, normalising motion to the
## server's fixed 64Hz tick regardless of client frame rate.

const TICK_RATE := 64.0
## Legacy wall-clock ceiling: no bullet outlives 10 seconds.
const MAX_LIFETIME_MS := 10_000
## Cap on how far a freshly received bullet is fast-forwarded to cover latency.
const MAX_CATCHUP_SECONDS := 0.25
## Motion that carries accumulated phase or a target id, so a plain fast-forward
## would land it wrong -- left to arrive a touch late instead. Speed-curve is NOT
## here: it is fast-forwarded with the curve (see catch_up).
const NOT_CATCHABLE := ProjectileKind.TRAIT_ORBITAL | ProjectileKind.TRAIT_PARAMETRIC \
	| ProjectileKind.TRAIT_SPINS | ProjectileKind.TRAIT_HOMING


static func step(bullet: Projectile, bullet_scale: float, now_ms := -1) -> void:
	var traits := ProjectileKind.traits(bullet)
	if traits & ProjectileKind.TRAIT_ORBITAL:
		_orbital(bullet, bullet_scale)
	elif traits & ProjectileKind.TRAIT_PARAMETRIC:
		_parametric(bullet, bullet_scale)
	else:
		# A LINE_SEGMENT wall with a frequency sweeps around its anchor: the
		# facing angle advances first, then it moves along the new heading.
		if traits & ProjectileKind.TRAIT_SPINS:
			bullet.angle += deg_to_rad(bullet.frequency * bullet_scale)
		straight(bullet, bullet_scale, now_ms)


static func straight(bullet: Projectile, bullet_scale: float, now_ms := -1) -> void:
	var speed := bullet.magnitude
	if ProjectileKind.traits(bullet) & ProjectileKind.TRAIT_SPEED_CURVE:
		speed *= ProjectileSpeed.multiplier(bullet,
			now_ms if now_ms >= 0 else Time.get_ticks_msec())
	var step_size := speed * bullet_scale
	var angle := bullet.angle
	bullet.pos += Vector2(sin(angle), cos(angle)) * step_size
	# |(sin, cos)| == 1, so distance travelled is exactly the step size.
	bullet.traveled += absf(step_size)


## Straight travel plus a sinusoidal offset perpendicular to it. The wave is a
## position offset, so each tick applies the *change* in offset, not a velocity.
static func _parametric(bullet: Projectile, bullet_scale: float) -> void:
	var amplitude := bullet.amplitude
	var previous := amplitude * sin(deg_to_rad(bullet.time_step))
	bullet.time_step = fmod(bullet.time_step + bullet.frequency * bullet_scale, 360.0)
	var current := amplitude * sin(deg_to_rad(bullet.time_step))
	var offset_delta := (current - previous) * (-1.0 if bullet.invert else 1.0)

	var angle := bullet.angle
	var forward := Vector2(sin(angle), cos(angle)) * bullet.magnitude * bullet_scale
	bullet.pos += forward + Vector2(cos(angle), -sin(angle)) * offset_delta
	# Range is spent on forward motion only, never on the oscillation.
	bullet.traveled += bullet.magnitude * bullet_scale


static func _orbital(bullet: Projectile, bullet_scale: float) -> void:
	var delta := deg_to_rad(bullet.frequency * bullet_scale)
	bullet.orbit_phase += delta
	bullet.pos = bullet.orbit_centre + Vector2(
		cos(bullet.orbit_phase), sin(bullet.orbit_phase)) * bullet.orbit_radius
	# Range is spent as arc length.
	bullet.traveled += bullet.orbit_radius * absf(delta)


static func is_expired(bullet: Projectile, now_ms: int) -> bool:
	if bullet.traveled > bullet.range:
		return true
	return (now_ms - bullet.created_ms) > MAX_LIFETIME_MS


## Advances a newly received bullet to roughly where the server has it by now.
## Orbital, parametric, spinning and homing motion can't be guessed forward
## (accumulated phase / a target), so they arrive a touch late. A straight bullet
## -- including a SPEED_CURVE one -- is fast-forwarded by the one-way latency.
##
## A speed curve is wall-clock driven off created_ms, which the client stamps at
## RECEIPT -- ~latency after the server spawned the shot. Left as-is the bullet runs
## its whole ramp/decay a step behind and drifts from where the server (which owns
## the hit) has it, so the shot visibly passes through enemies or damages ones it is
## nowhere near. Rewind created_ms to the spawn instant, then replay the latency
## tick by tick with the curve so BOTH position and phase land where the server is.
static func catch_up(bullet: Projectile, one_way_latency_ms: float, now_ms := -1) -> void:
	if bullet.magnitude <= 0.0 or ProjectileKind.traits(bullet) & NOT_CATCHABLE:
		return
	var latency := minf(one_way_latency_ms, MAX_CATCHUP_SECONDS * 1000.0)
	if latency <= 8.0:
		return
	if ProjectileKind.traits(bullet) & ProjectileKind.TRAIT_SPEED_CURVE:
		var clock := float(now_ms if now_ms >= 0 else int(Time.get_ticks_msec()))
		bullet.created_ms = int(clock - latency)
		var t := float(bullet.created_ms)
		while t < clock:
			var dt_ms := minf(clock - t, 1000.0 / TICK_RATE)
			straight(bullet, dt_ms / 1000.0 * TICK_RATE, int(t))
			t += dt_ms
		return
	straight(bullet, latency / 1000.0 * TICK_RATE)
	bullet.created_ms -= int(latency)
