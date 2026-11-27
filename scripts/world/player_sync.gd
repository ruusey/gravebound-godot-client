class_name PlayerSync
extends RefCounted

## Keeps the local player and its roster entry agreeing.
##
## The local player is drawn from the roster like everyone else, and the
## roster is what the overlay reads for bars and chips, so what the server
## says about us has to land in both places. Split from RealmState so the
## router stays a router.


## The roster is authoritative for our own class, which otherwise only
## arrives once in the login response.
static func local_class(state: RealmState) -> void:
	var own: Dictionary = state.entities.players.get(state.local.id, {})
	if not own.is_empty():
		state.local.class_id = int(own.get("class_id", state.local.class_id))
		# /size resizes the body; the new size rides the LoadPacket rebroadcast.
		state.local.size = float(own.get("size", state.local.size))


## The heavy update reaches every player in view -- the server strips the
## backpack, not the numbers -- so a remote's bars learn their maxima here.
static func update(state: RealmState, data: Dictionary) -> void:
	state.local.apply_update(data)
	state.abilities.apply_update(data, state.local.id)
	var id := int(data.get("playerId", 0))
	var entity := state.entities.find(GameConstants.ENTITY_PLAYER, id)
	if entity.is_empty():
		# The server sends enemy HP as this same stripped update keyed by the enemy
		# id, so a non-player id is an enemy -- apply its health here, otherwise the
		# bar only moves on the ~2s full-snapshot reload.
		_update_enemy(state, id, data)
		return
	var stats: Dictionary = data.get("stats", {})
	entity["max_health"] = int(stats.get("hp", 0))
	entity["max_mana"] = int(stats.get("mp", 0))
	entity["health"] = int(data.get("health", 0))
	entity["mana"] = int(data.get("mana", 0))
	# The nearby list's tooltip works the level out from this.
	entity["experience"] = int(data.get("experience", 0))
	# A dye drunk mid-session arrives here, for us and for everyone watching.
	entity["dye_id"] = int(data.get("dyeId", 0))
	# The account's quest score, under the name for everyone watching.
	entity["stars"] = int(data.get("stars", 0))
	# The player's guild ("" for none), as a tag under the name.
	entity["guild"] = String(data.get("guildName", ""))
	# The server strips the backpack but keeps the equipped slots (0-4) on a remote's
	# update, so the nearby-player inspect card can show what they're wearing.
	entity["equipment"] = data.get("inventory", [])


## An enemy's current HP (and max) ride the stripped update keyed by its id; only
## max comes with the full stats, so keep a sensible denominator when it's absent.
static func _update_enemy(state: RealmState, id: int, data: Dictionary) -> void:
	var enemy := state.entities.find(GameConstants.ENTITY_ENEMY, id)
	if enemy.is_empty():
		return
	var max_health := int(data.get("stats", {}).get("hp", 0))
	if max_health > 0:
		enemy["max_health"] = max_health
	enemy["health"] = int(data.get("health", enemy.get("health", 0)))


## HP/MP and statuses apply to the local player and the roster entry alike.
static func player_state(state: RealmState, data: Dictionary) -> void:
	var health_before := state.local.health
	state.local.apply_player_state(data)
	if int(data.get("playerId", 0)) == state.local.id and state.local.health < health_before:
		Sfx.event("player_hurt")
	var id := int(data.get("playerId", 0))
	var entity := state.entities.find(GameConstants.ENTITY_PLAYER, id)
	if entity.is_empty():
		# Enemy HP/effect deltas arrive here too, keyed by the enemy id -- this is the
		# frequent update that keeps an enemy's health bar live between reloads.
		entity = state.entities.find(GameConstants.ENTITY_ENEMY, id)
		if entity.is_empty():
			return
		entity["health"] = int(data.get("health", entity.get("health", 0)))
		entity["effects"] = data.get("effectIds", [])
		entity["effect_stacks"] = data.get("effectStacks", [])
		entity["immune_effects"] = data.get("immuneEffectIds", [])
		return
	entity["health"] = int(data.get("health", 0))
	entity["mana"] = int(data.get("mana", 0))
	entity["effects"] = data.get("effectIds", [])
	entity["effect_stacks"] = data.get("effectStacks", [])
