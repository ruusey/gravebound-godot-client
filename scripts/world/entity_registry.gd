class_name EntityRegistry
extends RefCounted

## The visible world minus bullets: players, enemies, loot and portals.
##
## Bullets are deliberately absent. The server never streams their positions,
## so they are re-simulated by ProjectileSystem instead of interpolated here.

const VELOCITY_SCALE := 128.0
const FLAG_ATTACKING := 0x01

var players := {}
var enemies := {}
var containers := {}
var portals := {}
## The enemy the lock-on ring is under (AutoAim), or -1.
var lock_on := -1
## Rare-drop bags already chimed for on this map, so one drifting back into view stays quiet.
var rare_loot_seen := {}

var _short_ids := {}   # shortId -> entity id
var _id_to_short := {}   # entity id -> shortId, the reverse of _short_ids for O(1) release
var _clock: Callable
## Snaps packet arrivals onto the server's send grid; null leaves them raw (tests
## that script exact arrival times).
var packet_clock: PacketClock
## The local player's centre, for the viewport gate on extrapolation; INF
## when there is no local player to gate on. RealmState wires it.
var viewer: Callable = func() -> Vector2: return Vector2.INF


func _init(clock: Callable = func() -> int: return Time.get_ticks_msec()) -> void:
	_clock = clock


func clear() -> void:
	players.clear()
	enemies.clear()
	containers.clear()
	portals.clear()
	_short_ids.clear()
	_id_to_short.clear()
	lock_on = -1
	rare_loot_seen.clear()


## Everything except one player, which is what a realm change leaves behind.
##
## The player crossing is the one entity that exists on both sides, and it is
## drawn from this roster rather than from LocalPlayer -- clear it outright
## and the screen goes black until the next realm streams in, with not even a
## character on it. Both references keep exactly this one: the web client's
## wipe is commented "local player persists across realms", the native's is
## `removeIf(key != localId)`.
func clear_but(keep_id: int) -> void:
	var kept: Dictionary = players.get(keep_id, {})
	clear()
	if not kept.is_empty():
		players[keep_id] = kept


## Where to draw an entity now. The sprite, its tag and the hit test all ask
## within a frame, so the answer is kept for that clock reading; a new snapshot
## (EntitySnapshots.push) drops it.
func render_position(entity: Dictionary) -> Vector2:
	var now := float(_clock.call())
	if entity.get("drawn_at", -1.0) == now:
		return entity["drawn"]
	var at := EntitySnapshots.render_position(entity, now, viewer.call())
	entity["drawn_at"] = now
	entity["drawn"] = at
	return at


## Where the server's rewind lands for this entity: the interpolated/extrapolated
## position WITHOUT the anti-jitter render offset. The hit predictor tests against this
## (not the drawn sprite position) so a consumed bullet lines up with a server-credited
## hit instead of the smoothed offset the server never tests against.
func sampled_position(entity: Dictionary) -> Vector2:
	return EntitySnapshots.sampled(entity, float(_clock.call()), viewer.call())


## When the packet being applied was sent, as near as can be told.
func _arrival() -> float:
	var now := float(_clock.call())
	return packet_clock.stamp(now) if packet_clock != null else now


## Applies a LoadPacket's entity tables. The wire mapping itself lives in
## EntityLoader; this keeps the registry to storage, lookup and movement.
func apply_load(data: Dictionary) -> int:
	return EntityLoader.apply(self, data, _arrival())


func apply_unload(data: Dictionary) -> void:
	for id in data.get("players", []):
		_release_short_id(players.get(int(id), {}))
		players.erase(int(id))
	for id in data.get("enemies", []):
		_release_short_id(enemies.get(int(id), {}))
		enemies.erase(int(id))
	for id in data.get("containers", []):
		containers.erase(int(id))
	for id in data.get("portals", []):
		portals.erase(int(id))


func apply_object_move(data: Dictionary) -> void:
	var now := _arrival()
	# The viewer centre can't change within one packet, so it is resolved once here
	# rather than through the Callable for every entity in the move list.
	var view_centre: Vector2 = viewer.call()
	for movement in data.get("movements", []):
		var entity := find(int(movement.get("entityType", 0)), int(movement.get("entityId", 0)))
		if entity.is_empty():
			continue
		EntitySnapshots.push(entity,
			Vector2(movement.get("posX", 0.0), movement.get("posY", 0.0)),
			Vector2(movement.get("velX", 0.0), movement.get("velY", 0.0)), now, view_centre)
		entity["attacking"] = (int(movement.get("flags", 0)) & FLAG_ATTACKING) != 0


func apply_compact_move(data: Dictionary) -> void:
	var now := _arrival()
	var view_centre: Vector2 = viewer.call()
	for movement in data.get("movements", []):
		var short_id := int(movement.get("shortEntityId", 0))
		if not _short_ids.has(short_id):
			continue
		var entity := find_any(_short_ids[short_id])
		if entity.is_empty():
			continue
		EntitySnapshots.push(entity,
			Vector2(movement.get("posX", 0.0), movement.get("posY", 0.0)),
			Vector2(float(movement.get("velXFixed", 0)) / VELOCITY_SCALE,
				float(movement.get("velYFixed", 0)) / VELOCITY_SCALE), now, view_centre)
		entity["attacking"] = (int(movement.get("flags", 0)) & FLAG_ATTACKING) != 0


func find(entity_type: int, id: int) -> Dictionary:
	match entity_type:
		GameConstants.ENTITY_PLAYER: return players.get(id, {})
		GameConstants.ENTITY_ENEMY: return enemies.get(id, {})
	return {}


## Only players and enemies are given short ids (LoadPacket.from assigns them
## through ShortIdAllocator), so those are the only tables worth searching.
func find_any(id: int) -> Dictionary:
	if players.has(id):
		return players[id]
	return enemies.get(id, {})


func upsert(table: Dictionary, id: int, kind: int) -> Dictionary:
	if not table.has(id):
		table[id] = {"id": id, "kind": kind, "snaps": [], "attacking": false,
			"walk": WalkCycle.new(), "attack": AttackPose.new(),
			"facing": "front", "facing_left": false}
	return table[id]


func snapshot_from_wire(entity: Dictionary, wire: Dictionary, now: float) -> void:
	var pos: Dictionary = wire.get("pos", {})
	EntitySnapshots.push(entity, Vector2(pos.get("x", 0.0), pos.get("y", 0.0)),
		Vector2(wire.get("dX", 0.0), wire.get("dY", 0.0)), now, viewer.call())


## shortId 0 means "none assigned"; mapping it would alias entities together.
func register_short_id(value: Variant, id: int) -> void:
	var short_id := int(value)
	if short_id != 0:
		_short_ids[short_id] = id
		_id_to_short[id] = short_id


func _release_short_id(entity: Dictionary) -> void:
	if entity.is_empty():
		return
	var id: int = entity.get("id", -1)
	if _id_to_short.has(id):
		_short_ids.erase(_id_to_short[id])
		_id_to_short.erase(id)
