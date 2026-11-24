class_name AbilityState
extends RefCounted

## Skill points, cooldowns, and what is being cast or has just landed.
##
## Points and levels arrive on UpdatePacket; a cast in progress on
## AbilityCastStartPacket; an effect that has resolved on CreateEffectPacket.
## The cooldowns are the client's own, kept so that a spammed key does not
## burn mana on sends the server would silently refuse -- it answers a
## refused cast with nothing at all, which is why the web client gates on
## its overlay before sending.

const SLOTS := 4
## The two persistent-refresh effects (blade orbit, blade blender): the
## server re-sends one every ~250ms while it runs, and only the newest of
## each may draw, or they stack at different phases and jitter.
const PERSISTENT_TYPES := [EffectType.BLADE_ORBIT, EffectType.BLADE_BLENDER]
## How long the cast-range ring lingers; the web client's showCastRing.
const RING_MS := 700
## Hard ceiling on concurrent landed effects. A crowd of companions can otherwise
## pile these up faster than they expire; past the cap the oldest is dropped so the
## per-frame draw + expire stays bounded.
const MAX_EFFECTS := 96

var available_points := 0
var invested: Array = [0, 0, 0, 0]
## Bumped when the points or levels change, so the bar redraws only then.
var version := 0
var cooldown_until: Array = [0, 0, 0, 0]
var cooldown_total: Array = [0, 0, 0, 0]
var global_until := 0
## playerId -> the cast in progress.
var casts := {}
var effects: Array = []
var rings: Array = []

var _clock: Callable


func _init(clock: Callable = func() -> int: return Time.get_ticks_msec()) -> void:
	_clock = clock


func now() -> int:
	return _clock.call()


func clear() -> void:
	available_points = 0
	invested = [0, 0, 0, 0]
	cooldown_until = [0, 0, 0, 0]
	cooldown_total = [0, 0, 0, 0]
	global_until = 0
	casts.clear()
	effects.clear()
	rings.clear()
	version += 1


## The skill-point half of an UpdatePacket, ours only.
func apply_update(data: Dictionary, local_id: int) -> void:
	if int(data.get("playerId", 0)) != local_id:
		return
	available_points = int(data.get("availableSkillPoints", 0))
	for slot in SLOTS:
		invested[slot] = int(data.get("investedSlot%d" % slot, 0))
	version += 1


## Someone began a timed cast. The local caster already posed when it sent
## the packet; a remote one gets its swing from here, aimed at the target,
## the way the web client drives remotes off this packet.
func apply_cast_start(data: Dictionary, entities: EntityRegistry, local_id: int) -> void:
	var duration := int(data.get("durationMs", 0))
	if duration <= 0:
		return
	var id := int(data.get("playerId", 0))
	var target := Vector2(data.get("worldTargetX", 0.0), data.get("worldTargetY", 0.0))
	casts[id] = {"ability_id": int(data.get("abilityId", 0)), "slot": int(data.get("slot", 0)),
		"started": now(), "duration_ms": duration, "target": target}
	var caster: Dictionary = entities.players.get(id, {})
	if id != local_id and not caster.is_empty():
		var centre := entities.render_position(caster) + Vector2.ONE * float(caster.get("size", 0)) * 0.5
		caster["attack"].begin(target - centre)


## The AoE melee visuals land at the strike point and carry no direction on
## the wire, so the caster's centre is stamped here, once, as `origin` --
## that is the axis a thrust or a sweep leans on. Snapshotted at landing
## rather than read each frame so the strike holds its heading as the
## caster moves on.
func apply_effect(data: Dictionary, entities: EntityRegistry = null, local: LocalPlayer = null) -> void:
	var kind := int(data.get("effectType", 0))
	if kind in PERSISTENT_TYPES:
		effects = effects.filter(func(fx: Dictionary) -> bool: return fx["type"] != kind)
	var owner := int(data.get("ownerId", 0))
	var fx := {"type": kind, "pos": Vector2(data.get("posX", 0.0), data.get("posY", 0.0)),
		"radius": float(data.get("radius", 0.0)), "duration_ms": int(data.get("duration", 0)),
		"target": Vector2(data.get("targetPosX", 0.0), data.get("targetPosY", 0.0)),
		"tier": int(data.get("tier", 0)), "owner": owner, "started": now()}
	var origin := _caster_centre(owner, entities, local)
	if origin != Vector2.INF:
		fx["origin"] = origin
	effects.append(fx)
	if effects.size() > MAX_EFFECTS:
		effects.remove_at(0)   # drop the oldest to stay bounded under crowd load


## Where the caster stands right now, or INF when we cannot place them.
func _caster_centre(owner: int, entities: EntityRegistry, local: LocalPlayer) -> Vector2:
	if local != null and owner == local.id:
		return local.render_centre()
	if entities != null and entities.players.has(owner):
		var caster: Dictionary = entities.players[owner]
		return entities.render_position(caster) + Vector2.ONE * float(caster.get("size", 0)) * 0.5
	return Vector2.INF


## Drops what has run its course. Compacts in place (iterate from the back and
## remove_at) so a frame where nothing expired — the common case — allocates no new
## array, unlike the old per-frame filter().
func expire() -> void:
	var at := now()
	var i := effects.size() - 1
	while i >= 0:
		var fx: Dictionary = effects[i]
		if at - fx["started"] >= fx["duration_ms"]:
			effects.remove_at(i)
		i -= 1
	var r := rings.size() - 1
	while r >= 0:
		if at - rings[r]["started"] >= RING_MS:
			rings.remove_at(r)
		r -= 1
	for id in casts.keys():
		if at - casts[id]["started"] >= casts[id]["duration_ms"]:
			casts.erase(id)


## How far along a player's cast is, or -1 for a player not casting.
func cast_progress(player_id: int) -> float:
	if not casts.has(player_id):
		return -1.0
	var cast: Dictionary = casts[player_id]
	return clampf(float(now() - cast["started"]) / float(cast["duration_ms"]), 0.0, 1.0)


func start_cooldown(slot: int, duration_ms: int) -> void:
	cooldown_until[slot] = now() + duration_ms
	cooldown_total[slot] = duration_ms


func on_cooldown(slot: int) -> bool:
	return now() < cooldown_until[slot]


## What is left of a cooldown, 1 at the start and 0 once it has run.
func cooldown_fraction(slot: int) -> float:
	if cooldown_total[slot] <= 0:
		return 0.0
	return clampf(float(cooldown_until[slot] - now()) / float(cooldown_total[slot]), 0.0, 1.0)


func show_ring(centre: Vector2, radius: float) -> void:
	rings.append({"pos": centre, "radius": radius, "started": now()})
