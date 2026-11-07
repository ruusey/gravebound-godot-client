class_name ProjectileTracking
extends RefCounted

## The two v0.9.0 motion types that depend on another entity.
##
## HOMING steers its heading toward a target each tick; ANCHORED snaps back to
## its source entity, so a wall summoned by an enemy travels with it. Both
## live here rather than in ProjectileMotion because they need to look
## entities up, and the integrator deliberately knows nothing about the world.
##
## When the entity has gone -- unloaded, or killed -- the server leaves the
## bullet where it is until its lifetime runs out, and so do we.


## Records where the bullet sits relative to its source, so it can be snapped
## back every tick afterwards. Mirrors Bullet.setupAnchor.
##
## Captured against the source's RAW latest-snapshot position, not its
## interpolated render position: the server anchored the wall to the entity's
## live server position, and anchored walls ride a bullets-only load delta that
## carries no fresh enemy snapshot, so subtracting the ~100ms-delayed render
## position baked that lag into the offset -- which deformed a boss's wall-box
## (each side captured a tick apart as it entered view, with a different lag).
static func capture_anchor(bullet: Projectile, entities: EntityRegistry,
		player: LocalPlayer) -> void:
	var source: Variant = _raw_position_of(bullet.src_entity_id, entities, player)
	if source == null:
		return
	bullet.anchor_offset = bullet.pos - (source as Vector2)
	bullet.anchor_captured = true


static func anchor(bullet: Projectile, entities: EntityRegistry, player: LocalPlayer) -> void:
	# A wall reloaded before its source entity has (anchored walls ride a bullets-only
	# load delta that carries no enemy) arrives with no captured offset. Capturing here
	# the first frame the source is known -- from the server-sent pos it still holds --
	# keeps the offset correct, where a zero default would snap a whole wall-box onto the
	# source's top-left corner. Until then the wall stays put at its server position.
	if not bullet.anchor_captured:
		capture_anchor(bullet, entities, player)
		return
	var source: Variant = _position_of(bullet.src_entity_id, entities, player)
	if source == null:
		return
	bullet.pos = (source as Vector2) + bullet.anchor_offset


## Rotates the heading toward the target by at most `frequency` degrees this
## tick. Velocity is (sin a, cos a), so the angle pointing at the target is
## atan2(dx, dy) -- not the usual atan2(dy, dx). Mirrors Bullet.steerToward.
static func steer(bullet: Projectile, entities: EntityRegistry, player: LocalPlayer,
		bullet_scale: float) -> void:
	var target_id := bullet.target_entity_id
	var target: Variant = _position_of(target_id, entities, player)
	if target == null:
		return

	var centre: Vector2 = (target as Vector2) \
		+ Vector2.ONE * _size_of(target_id, entities, player) * 0.5
	var origin: Vector2 = Projectile.centre(bullet)
	var desired := atan2(centre.x - origin.x, centre.y - origin.y)
	var difference := wrapf(desired - bullet.angle, -PI, PI)
	var max_turn := deg_to_rad(bullet.frequency * bullet_scale)
	bullet.angle += clampf(difference, -max_turn, max_turn)


## The local player is tracked by prediction, not by the entity roster, so its
## predicted position is the one the server is steering at.
static func _position_of(id: int, entities: EntityRegistry, player: LocalPlayer) -> Variant:
	if id == 0:
		return null
	if player != null and id == player.id:
		return player.position
	var entity := entities.find_any(id)
	if entity.is_empty():
		return null
	return entities.render_position(entity)


## The source's newest raw server position (the snapshot target), for anchoring --
## as opposed to _position_of's interpolated render position. Falls back to the
## render position when there are no snapshots yet (a cold single-load, where the
## two coincide anyway).
static func _raw_position_of(id: int, entities: EntityRegistry, player: LocalPlayer) -> Variant:
	if id == 0:
		return null
	if player != null and id == player.id:
		return player.position
	var entity := entities.find_any(id)
	if entity.is_empty():
		return null
	var snaps: Array = entity.get("snaps", [])
	if snaps.is_empty():
		return entities.render_position(entity)
	return snaps[-1]["pos"]


static func _size_of(id: int, entities: EntityRegistry, player: LocalPlayer) -> float:
	if player != null and id == player.id:
		return float(GameConstants.PLAYER_SIZE)
	return float(entities.find_any(id).get("size", 16))
