class_name ShotPredictor
extends RefCounted

## Builds the locally predicted bullets for a shot, and recognises the server's
## copies of them when they arrive.
##
## The fan has to match the server's exactly -- count, spread, range and
## piercing all come from the weapon archetype. Get any of them wrong and the
## predicted bullets never line up with the authoritative ones, so the player
## sees ghosts flying alongside the real shots.

## Fan spread for weapons whose archetype does not specify one.
const DEFAULT_SPREAD_RAD := 0.12
## A prediction and an incoming bullet are the same shot within this angle. Wide
## enough to cover a multishot fan's outer arms (a 7-shot fan spans ~0.3 rad
## either side of centre) so those bullets claim their prediction instead of
## double-drawing a ghost beside the real one.
const ANGLE_TOLERANCE := 0.40


## Returns the predicted bullets for one shot, keyed by their local (negative)
## id. `extra_projectiles` is the count a socketed gem adds on top of the
## archetype's (a Multishot Gem is +1) -- it MUST match the server's total or
## the extra server bullet arrives late and the fan looks staggered.
static func build(shot_number: int, group_id: int, definitions: Array, base_angle: float,
		origin: Vector2, archetype: Dictionary, now_ms: int, extra_projectiles := 0) -> Dictionary:
	var count := maxi(int(archetype.get("projectileCount", 1)), 1) + maxi(extra_projectiles, 0)
	var spread := float(archetype.get("spreadRad", 0.0))
	if spread <= 0.0:
		spread = DEFAULT_SPREAD_RAD
	var range_multiplier := float(archetype.get("rangeMul", 1.0))
	if range_multiplier <= 0.0:
		range_multiplier = 1.0

	var extra_flags: Array = []
	if bool(archetype.get("piercing", false)):
		extra_flags.append(ProjectileKind.PASS_THROUGH_ENEMIES)

	var built := {}
	var index := 0
	for definition in definitions:
		var definition_angle: float = base_angle + float(definition.get("angle", 0.0))
		var spawn := origin + ProjectileAngle.spawn_offset(definition, base_angle)
		for i in count:
			var offset := (float(i) - float(count - 1) * 0.5) * spread
			# Negative ids keep predictions out of the server id space.
			var local_id := -(shot_number * 100 + index)
			index += 1
			built[local_id] = Projectile.predicted_shot(local_id, group_id, spawn,
				definition_angle + offset, definition, now_ms, range_multiplier, extra_flags)
	return built


## Finds the prediction matching an incoming server bullet and adopts its id, or
## returns false. `owner_id` is the local player: only a bullet the server says
## WE fired can be one of our predictions. Matching any other bullet (a nearby
## enemy shot at a similar angle) would drop the server's real, damaging bullet
## so it never draws -- an invisible projectile that still kills. So an enemy
## bullet is never claimed here; it always falls through to be spawned and drawn.
static func claim(bullets: Dictionary, wire: Dictionary, server_id: int, owner_id: int) -> bool:
	if int(wire.get("srcEntityId", 0)) != owner_id:
		return false
	# A Codex ally bolt passes the owner gate (owner-attributed for credit) but is the
	# server's own bullet, not one of our predictions -- never let it claim one, or the
	# real bolt is dropped and never drawn. Wire flags arrive as floats, so compare as int.
	for flag in wire.get("flags", []):
		if int(flag) == ProjectileKind.ALLY_PROJECTILE:
			return false
	var incoming_angle := float(wire.get("angle", 0.0))
	# A server bullet may only claim a prediction from the SAME projectile group.
	# Without this, any own shot (a melee burst bolt, another weapon's fan) would
	# adopt a nearby-angle prediction left by an ABILITY or a different weapon,
	# so the real bolt never drew -- the shot lost ~half its projectiles whenever
	# predictions from something else were on screen. The wire carries the group
	# id as projectileId; predictions store it as group_id.
	var incoming_group := int(wire.get("projectileId", 0))
	# Within the matching group, claim the NEAREST-angle unclaimed prediction, not
	# the first within tolerance: a volley fires many at once and rapid shots
	# overlap, so first-match grabbed the wrong one and orphaned the real match.
	var best_id := 0
	var best_diff := ANGLE_TOLERANCE
	var found := false
	for local_id in bullets:
		var prediction: Projectile = bullets[local_id]
		# ONLY an actual local prediction can be claimed. The id sign is NOT a valid
		# test: server bullet ids are random longs and are frequently NEGATIVE, so the
		# old `local_id >= 0` skip treated a previous same-group shot's live bullets as
		# predictions -- a new volley then "claimed" them and its own bolts never drew
		# (the missing-projectile bug, worst on rapid fire of a many-bullet weapon).
		if not prediction.predicted:
			continue
		if prediction.group_id != incoming_group:
			continue
		var claimed := prediction.server_id
		# Already adopted this exact server bullet -- the 2s full-snapshot reconcile
		# re-sends it, so without this the server copy gets added alongside the
		# prediction and the shot draws twice (the "duplicated projectile").
		if claimed == server_id:
			return true
		if claimed != 0:
			continue
		var diff := absf(angle_difference(prediction.angle, incoming_angle))
		if diff <= best_diff:
			best_diff = diff
			best_id = local_id
			found = true
	if found:
		var prediction := bullets[best_id] as Projectile
		prediction.server_id = server_id
		# A homing shot locks its target server-side at fire time (the nearest enemy
		# to the cursor); the prediction can't know it, so it was flying straight.
		# Adopt the authoritative target (and steer rate) now, or the claimed bullet
		# keeps going past the enemy instead of homing. Wire flags arrive as floats.
		for flag in wire.get("flags", []):
			if int(flag) == ProjectileKind.HOMING:
				prediction.target_entity_id = int(wire.get("targetEntityId", 0))
				prediction.frequency = float(wire.get("frequency", prediction.frequency))
				break
		return true
	return false
