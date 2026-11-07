class_name Projectile
extends RefCounted

## One bullet's simulation state, from the wire or from a local prediction.
## Motion lives in ProjectileMotion, flags in ProjectileKind and angle handling
## in ProjectileAngle.
##
## Typed fields rather than a Dictionary: every frame reads each bullet a few
## dozen times, and a member read is a fraction of a keyed one.

const DEFAULT_ORBIT_RADIUS := 64.0

var id := 0
## NetBullet.projectileId carries the projectile *group* id, which is what the
## sprite and the group definition are keyed by.
var group_id := 0
var pos := Vector2.ZERO
var size := 8
var angle := 0.0
## Cached unit heading (sin(angle), cos(angle)) for a straight shot, so advance()
## skips the per-frame trig while the angle is constant. heading_angle holds the
## angle it was built for; INF forces a recompute on first use and after a turn.
var heading := Vector2.ZERO
var heading_angle := INF
var magnitude := 0.0
var range := 0.0
var traveled := 0.0
var damage := 0
var flags: Array = []
## The flags as a bitmask, so a flag test is a bit test.
var flag_bits := 0
var invert := false
var time_step := 0.0
var amplitude := 0.0
var frequency := 0.0
var orbit_centre := Vector2.ZERO
var orbit_radius := 0.0
var orbit_phase := 0.0
var length := 0.0
var lifetime_ticks := 0
var src_entity_id := 0
var target_entity_id := 0
var anchor_offset := Vector2.ZERO
## Whether anchor_offset has been captured against a known source yet. Stays false
## while the source entity is absent (e.g. a wall reloaded before its boss has), so
## anchoring can't snap the wall to the source's corner with a zero offset.
var anchor_captured := false
var created_ms := 0
var predicted := false
var server_id := 0
## ProjectileKind.traits, worked out on first sight; -1 until then.
var traits := -1
var consumed := false
var consumed_at := 0
## ProjectileSpeed's curve normalisers, set on the first step that needs them.
var curve_ready := false
var curve_end := 0.0
var curve_den := 0.0
## ParticleField's trail accumulator, whether the bullet was out of sight, and
## whether its group has any particles at all (-1 until ParticleField looks).
var fx_acc := 0.0
var fx_hidden := false
var fx_kind := -1


## Simulation state for a bullet the server told us about.
static func from_wire(wire: Dictionary, now_ms: int) -> Projectile:
	var bullet := Projectile.new()
	var at: Dictionary = wire.get("pos", {})
	# Wire flags arrive as floats, and `in` is type-strict (24.0 is not 24), so
	# they are made ints here, once.
	for flag in wire.get("flags", []):
		var flag_id := int(flag)
		bullet.flags.append(flag_id)
		bullet.flag_bits |= 1 << flag_id
	bullet.id = int(wire.get("id", 0))
	bullet.group_id = int(wire.get("projectileId", 0))
	bullet.pos = Vector2(at.get("x", 0.0), at.get("y", 0.0))
	bullet.size = int(wire.get("size", 8))
	bullet.angle = float(wire.get("angle", 0.0))
	bullet.magnitude = float(wire.get("magnitude", 0.0))
	bullet.range = float(wire.get("range", 0.0))
	bullet.damage = int(wire.get("damage", 0))
	bullet.invert = bool(wire.get("invert", false))
	bullet.time_step = float(wire.get("timeStep", 0))
	bullet.amplitude = float(wire.get("amplitude", 0))
	bullet.frequency = float(wire.get("frequency", 0))
	bullet.orbit_centre = Vector2(wire.get("orbitCenterX", 0.0), wire.get("orbitCenterY", 0.0))
	bullet.orbit_radius = float(wire.get("orbitRadius", 0.0))
	bullet.orbit_phase = float(wire.get("orbitPhase", 0.0))
	# The optional groups ride behind a mask byte, so a straight bullet carries
	# none of these and they stay at their defaults.
	bullet.length = float(wire.get("length", 0))
	bullet.lifetime_ticks = int(wire.get("lifetimeTicks", 0))
	bullet.src_entity_id = int(wire.get("srcEntityId", 0))
	bullet.target_entity_id = int(wire.get("targetEntityId", 0))
	bullet.created_ms = now_ms
	bullet._initialise_orbit()
	return bullet


## A locally predicted bullet, spawned the instant the player clicks so firing
## feels immediate. Negative ids keep predictions out of the server id space.
static func predicted_shot(local_id: int, group_id: int, position: Vector2, angle: float,
		definition: Dictionary, now_ms: int, range_multiplier := 1.0,
		extra_flags: Array = []) -> Projectile:
	var bullet := Projectile.new()
	# Content flags parse as floats too.
	for flag in definition.get("flags", []):
		var flag_id := int(flag)
		bullet.flags.append(flag_id)
		bullet.flag_bits |= 1 << flag_id
	for flag in extra_flags:
		if not flag in bullet.flags:
			bullet.flags.append(flag)
			bullet.flag_bits |= 1 << int(flag)
	bullet.id = local_id
	bullet.group_id = group_id
	bullet.pos = position
	bullet.size = int(definition.get("size", 8))
	bullet.angle = angle
	bullet.magnitude = float(definition.get("magnitude", 0.0))
	bullet.range = float(definition.get("range", 0.0)) * range_multiplier
	bullet.damage = int(definition.get("damage", 0))
	bullet.invert = (bullet.flag_bits & (1 << ProjectileKind.INVERTED_PARAMETRIC)) != 0
	bullet.amplitude = float(definition.get("amplitude", 0))
	bullet.frequency = float(definition.get("frequency", 0))
	bullet.orbit_phase = angle
	bullet.length = float(definition.get("length", 0))
	bullet.lifetime_ticks = int(definition.get("lifetimeTicks", 0))
	bullet.created_ms = now_ms
	bullet.predicted = true
	bullet._initialise_orbit()
	return bullet


## A bullet built from named fields, the way tests and tools describe one; the
## flag bitmask follows its flags.
static func from_fields(fields: Dictionary) -> Projectile:
	var bullet := Projectile.new()
	for key in fields:
		bullet.set(key, fields[key])
	if not fields.has("flag_bits"):
		var flag_ids: Array = []
		for flag in bullet.flags:
			flag_ids.append(int(flag))
			bullet.flag_bits |= 1 << int(flag)
		bullet.flags = flag_ids
	return bullet


static func centre(bullet: Projectile) -> Vector2:
	var half := bullet.size * 0.5
	return bullet.pos + Vector2(half, half)


func _initialise_orbit() -> void:
	if not flag_bits & (1 << ProjectileKind.ORBITAL):
		return
	if orbit_radius <= 0.0:
		orbit_radius = amplitude if amplitude != 0.0 else DEFAULT_ORBIT_RADIUS
	if orbit_centre == Vector2.ZERO:
		# Derive the centre this bullet must be orbiting from where it spawned.
		orbit_centre = pos - Vector2(cos(orbit_phase), sin(orbit_phase)) * orbit_radius
