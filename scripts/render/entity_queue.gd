class_name EntityQueue
extends RefCounted

## Works out what the ground pass draws this frame, and in what order.
##
## Everything standing on the ground goes into one queue, sorted on its feet
## (`pos.y + size`) so an entity lower on the screen draws in front -- wire
## positions are top-left anchored, and sorting on those would order a tall
## sprite wrongly against a short one. Both reference clients sort the same
## value. Remote entities are queued at their interpolated position; the local
## player at its predicted one, always, so the camera can never lose you.
##
## Culling happens here, so what comes back is already the visible set. Each
## entry carries everything EntityRenderer needs to draw it and nothing about
## how to draw it.

const PLAYER_RENDER_SIZE := GameConstants.PLAYER_RENDER_SIZE
const SIMPLE_SIZE := 16
## Keeps a feet key positive for bodies standing just off the top of the map.
const FEET_BIAS := 1 << 24
const NO_EFFECTS: Array = []


## Everything the ground pass would draw this frame, in draw order.
func build(state: RealmState, content: GameData, view: Rect2) -> Array:
	var queue: Array = []
	_queue_players(queue, state, content, view)
	_queue_enemies(queue, state, content, view)
	_queue_containers(queue, state, content, view)
	_queue_portals(queue, state, content, view)

	return by_feet(queue)


## The queue in feet order. Sorted as packed integers -- feet depth to a
## sixteenth of a pixel over the entry's index -- because a scripted comparator
## is one script call per comparison, the bulk of this pass in a crowd.
static func by_feet(queue: Array) -> Array:
	var count := queue.size()
	if count < 2:
		return queue
	var keys := PackedInt64Array()
	keys.resize(count)
	for i in count:
		var item: Dictionary = queue[i]
		var feet: float = item["pos"].y + float(item["size"])
		keys[i] = ((int(roundf(feet * 16.0)) + FEET_BIAS) << 16) | i
	keys.sort()
	var sorted := []
	sorted.resize(count)
	for i in count:
		sorted[i] = queue[keys[i] & 0xFFFF]
	return sorted


## Most bodies carry no effect, and those skip the call into StatusTint.
static func _tint(effects: Array) -> Color:
	return StatusTint.CLEAR if effects.is_empty() else StatusTint.of(effects)


## How big to draw a frame, in world pixels.
##
## Usually the body cell, but an attack frame can be wider or taller than the
## cell it was sliced from -- the weapon overhangs it. Squashing that back
## into the cell is what makes a sideways swing look compressed, so the rect
## takes the frame's own ratio, exactly as both references do.
static func frame_size(texture: Texture2D, cell: int, body: float) -> Vector2:
	if texture == null or cell <= 0:
		return Vector2.ONE * body
	return texture.get_size() / float(cell) * body


func _queue_players(queue: Array, state: RealmState, content: GameData,
		view: Rect2) -> void:
	var show_others := state.settings.is_on("show_other_players")
	for id in state.entities.players:
		var player: Dictionary = state.entities.players[id]
		var is_local: bool = id == state.local.id
		if not is_local and not show_others:
			continue
		var position: Vector2 = state.local.render_position() if is_local \
			else state.entities.render_position(player)
		if not is_local and not view.has_point(position):
			continue

		var class_id: int = state.local.class_id if is_local else player.get("class_id", 0)
		var facing: String = state.local.facing if is_local else player["facing"]
		var action := "walk" if _is_moving(state, player, is_local) else "idle"
		var frame: int = (state.local.walk if is_local else player["walk"]).frame
		var mirrored: bool = state.local.facing_left if is_local else player["facing_left"]

		# A swing overrides all three: it names its own clip, it counts its own
		# frames, and it faces where the shot went rather than where the feet
		# are pointed -- which is what makes a stationary shooter turn.
		var pose: AttackPose = state.local.attack if is_local else player["attack"]
		if pose.is_active():
			action = "attack"
			facing = pose.facing
			frame = pose.frame
			mirrored = pose.facing_left
		var texture := content.classes_art.frame(class_id, action, facing, frame, int(player.get("dye_id", 0)))
		# Scale the sprite by the body size so /size visibly resizes the player;
		# default size renders at the usual PLAYER_RENDER_SIZE.
		var body_size: float = state.local.size if is_local else float(player.get("size", GameConstants.PLAYER_SIZE))
		var render_size := PLAYER_RENDER_SIZE * (body_size / float(GameConstants.PLAYER_SIZE))
		var effects: Array = state.local.effects if is_local else player.get("effects", NO_EFFECTS)
		queue.append({
			"kind": "players",
			"pos": position,
			"size": render_size,
			"draw": frame_size(texture, content.classes_art.cell_size(class_id),
				render_size),
			"texture": texture,
			"tint": Color(0.4, 1.0, 0.5) if is_local else Color(0.3, 0.6, 1.0),
			"modulate": _tint(effects),
			# A downed companion is drawn on its side (fallen), facing up.
			"downed": StatusTint.DOWNED in effects,
			# The sheet only has a right-facing side clip, so leftward
			# movement is that clip mirrored.
			"flip": facing == "side" and mirrored,
			# Only the player we are wades, as in the web client.
			"wading": is_local and state.tiles.wades(position, PLAYER_RENDER_SIZE),
			# Remote players draw at their interpolated sub-pixel position rather than
			# snapped to a whole screen pixel. Snapping a body that creeps <1px/frame
			# (low SPD or a slow effect) holds it on one pixel for several frames then
			# jumps -- the uneven stepping that reads as jitter. The local player is
			# immune (the camera lands it on a pixel; slowed, the ground scrolls smooth),
			# so only remote bodies need this. Their name/bars skip the snap too
			# (entity_overlay) so the two still glide together.
			"smooth": not is_local,
		})


func _queue_enemies(queue: Array, state: RealmState, content: GameData, view: Rect2) -> void:
	for id in state.entities.enemies:
		var enemy: Dictionary = state.entities.enemies[id]
		var position := state.entities.render_position(enemy)
		var size := int(enemy.get("size", SIMPLE_SIZE))
		if not view.has_point(position) or Blind.hides(state, position, size):
			continue
		var enemy_id: int = enemy.get("enemy_id", -1)
		var texture: Texture2D = null
		var flip := false
		var draw := Vector2.ONE * float(size)
		# Enemies with an animation set play idle/walk/attack frames and mirror on
		# horizontal movement, exactly like remote players. These sheets are side-only,
		# so always use the "side" clip and flip by travel direction. No animation set
		# (or a missing frame) falls back to the single static sprite.
		if content.library.animations.has(enemy_id):
			var pose: AttackPose = enemy["attack"]
			var action := "idle"
			var frame: int = enemy["walk"].frame
			if _enemy_moving(enemy):
				action = "walk"
			if pose.is_active():
				action = "attack"
				frame = pose.frame
			texture = content.classes_art.frame(enemy_id, action, "side", frame)
			if texture != null:
				flip = enemy["facing_left"]
				draw = frame_size(texture, content.classes_art.cell_size(enemy_id), size)
		if texture == null:
			texture = content.enemy_texture(enemy_id)
			flip = false
			draw = Vector2.ONE * float(size)
		queue.append({
			"kind": "enemies",
			"pos": position,
			"size": size,
			"draw": draw,
			"texture": texture,
			"tint": Color(0.8, 0.25, 0.25),
			"modulate": _tint(enemy.get("effects", NO_EFFECTS)),
			"flip": flip,
			"lock": id == state.entities.lock_on,
		})


func _enemy_moving(enemy: Dictionary) -> bool:
	var snapshots: Array = enemy.get("snaps", [])
	return not snapshots.is_empty() and snapshots[-1]["vel"].length_squared() > 0.0001


## A portal draws a tile wide, which is what both references give it, and its
## art comes from portalId -- nothing about how it looks is on the wire. A
## portal the content does not define falls back to the block, so a missing
## definition is visible rather than an invisible doorway.
func _queue_portals(queue: Array, state: RealmState, content: GameData,
		view: Rect2) -> void:
	for id in state.entities.portals:
		var portal: Dictionary = state.entities.portals[id]
		var position := state.entities.render_position(portal)
		if not view.has_point(position):
			continue
		queue.append({"kind": "portals", "pos": position,
			"size": GameConstants.TILE_SIZE,
			"draw": Vector2.ONE * float(GameConstants.TILE_SIZE),
			"texture": content.portals.texture(int(portal.get("portal_id", -1))),
			"tint": Color(0.5, 0.35, 0.9), "flip": false,
			"modulate": StatusTint.CLEAR})


## A loot bag or chest, in LootArt's rect: a chest fills its tile, a bag
## sits in the middle at half a tile. Its "pos" and "size" are that rect's,
## so it sorts on where the bag actually stands.
func _queue_containers(queue: Array, state: RealmState, content: GameData, view: Rect2) -> void:
	for id in state.entities.containers:
		var container: Dictionary = state.entities.containers[id]
		var position := state.entities.render_position(container)
		if not view.has_point(position):
			continue
		var tier := int(container.get("tier", 0))
		var chest := bool(container.get("is_chest", false))
		var at := LootArt.rect(content, position, tier, chest)
		queue.append({"kind": "containers", "pos": at.position, "size": at.size.x,
			"draw": at.size, "texture": LootArt.texture(content, tier, chest),
			"tint": Color(0.85, 0.7, 0.3), "flip": false, "modulate": StatusTint.CLEAR})


func _is_moving(state: RealmState, player: Dictionary, is_local: bool) -> bool:
	if is_local:
		return state.local.moving
	var snapshots: Array = player.get("snaps", [])
	return not snapshots.is_empty() and snapshots[-1]["vel"].length_squared() > 0.0001
