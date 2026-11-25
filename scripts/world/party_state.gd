class_name PartyState
extends RefCounted

## The party you are in.
##
## PartyUpdatePacket is the whole roster every time -- at most four, sent
## about twice a second and on every change -- with the leader's id; a
## partyId of 0 is the server saying you are in no party now, which is how
## leaving, a kick and a disband all arrive. An invite waiting on us lives
## in InteractionState, not here. A teammate's cooldown ends are epoch milliseconds, the server's clock, so they are
## read against the wall clock and not the tick clock the rest of the
## state runs on.

const MAX_SIZE := 4

var party_id := 0
var leader_id := 0
var members: Array = []
## Bumped on every roster change, so a panel can rebuild only then.
var version := 0

## The server's epoch milliseconds are read against this; a scripted render pins it.
var wall_clock: Callable


func _init(wall: Callable = func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)) -> void:
	wall_clock = wall


func clear() -> void:
	party_id = 0
	leader_id = 0
	members = []
	version += 1


func apply_update(data: Dictionary) -> void:
	party_id = int(data.get("partyId", 0))
	leader_id = int(data.get("leaderId", 0)) if party_id != 0 else 0
	members = data.get("members", []) if party_id != 0 else []
	version += 1


## The frequent HP/MP/effects/cooldown refresh (PartyVitalsPacket), merged by
## playerId into the roster apply_update already holds. The roster itself carries
## identity/stats/equipment and now arrives only on a static change, so this is
## what keeps teammates' bars and cooldowns live between those. A vitals row for
## someone not in the roster yet is ignored; the next roster adds them.
func apply_vitals(data: Dictionary) -> void:
	if party_id == 0 or int(data.get("partyId", 0)) != party_id:
		return
	var by_id := {}
	for row in data.get("members", []):
		by_id[int(row.get("playerId", 0))] = row
	var changed := false
	for member in members:
		var row: Variant = by_id.get(int(member.get("playerId", 0)))
		if row == null:
			continue
		member["health"] = int(row.get("health", member.get("health", 0)))
		member["maxHealth"] = int(row.get("maxHealth", member.get("maxHealth", 0)))
		member["mana"] = int(row.get("mana", member.get("mana", 0)))
		member["maxMana"] = int(row.get("maxMana", member.get("maxMana", 0)))
		member["effectIds"] = row.get("effectIds", member.get("effectIds", []))
		member["abilityCooldownEnds"] = row.get("abilityCooldownEnds", member.get("abilityCooldownEnds", []))
		changed = true
	if changed:
		version += 1


func in_party() -> bool:
	return party_id != 0 and not members.is_empty()


func is_leader(player_id: int) -> bool:
	return in_party() and leader_id == player_id


## Everyone but the given player, in the server's order.
func others(player_id: int) -> Array:
	return members.filter(func(m: Dictionary) -> bool: return int(m.get("playerId", 0)) != player_id)


func member_ids() -> Array:
	return members.map(func(m: Dictionary) -> int: return int(m.get("playerId", 0)))


## What is left of a teammate's cooldown in a hotbar slot, 1 at its start
## and 0 once it has run, against a cooldown of `total_ms`: the web
## client's overlay height, from the server's epoch-millisecond end.
func cooldown_fraction(member: Dictionary, slot: int, total_ms: int) -> float:
	var ends: Array = member.get("abilityCooldownEnds", [])
	if total_ms <= 0 or slot < 0 or slot >= ends.size():
		return 0.0
	var remaining := int(ends[slot]) - int(wall_clock.call())
	return clampf(float(remaining) / float(total_ms), 0.0, 1.0)
