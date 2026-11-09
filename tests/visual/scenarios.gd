class_name VisualScenarios
extends RefCounted

## Deterministic worlds for visual capture.
##
## Each scenario fills a RealmState through the ordinary packet router, using
## the same wire shapes the server sends, so what gets rendered is what a real
## session would produce -- no server required, and identical every run.
##
## Tiles are packed the way the server packs them: xIndex carries the row and
## yIndex the column.

## Real content ids: a plain ground tile, and a wall that actually carries
## hasCollision -- the collision scenario draws nothing at all if the wall id
## is not a colliding tile, and would pass while showing an empty overlay.
const FLOOR_TILE := 1
## The wall clock a scripted render pins a party's cooldown ends against.
const PARTY_WALL_MS := 1_700_000_000_000
const WALL_TILE := 61
## A collision tile that is NOT a wall, so nothing is stamped back over the
## entities standing on it.
const DEEP_WATER_TILE := 9
## Real groups that carry an fx spin, one of each mode.
const ADDITIVE_SPIN_GROUP := 1177
const CONTINUOUS_SPIN_GROUP := 1000
## A prop -- solid, but not architecture -- and a liquid you wade through.
const PROP_TILE := 120
const SHALLOW_WATER_TILE := 5
## A floor that burns: damaging, and (like every shipped lava tile) slowing too.
const LAVA_TILE := 25
const ROCK_TILE := 21
## A square wall -- 8x8, no front face of its own -- which is what the
## side-bands are for.
const SQUARE_WALL_TILE := 184


static func names() -> Array:
	return ["terrain", "entities", "ysort", "bullets", "collision", "overlap",
		"walk_left", "walk_right", "walk_up", "walk_down", "walls", "feather", "effects", "walldepth", "shadows", "attack_left", "attack_right", "attack_up", "spin", "portals", "transition", "transition_named", "damage", "damage_fading", "chat", "death", "wading", "inventory", "abilities", "potion_storage", "fame_store", "forge", "minimap", "trails", "login", "exchange_market", "wall_bands", "effects_cast", "effects_generic", "effects_holy", "effects_dark", "effects_arcane", "effects_knight", "effects_rogue", "effects_trapper", "effects_heavy", "trade", "player_hud", "party", "nearby", "item_card", "options", "options_controls", "masteries", "dev_overlay", "blind", "dyes", "quests", "quest_stars", "login_delete", "login_stats", "terms", "how_to", "leaderboard", "loot_preview", "minimap_hop", "billboards", "chunk_seams", "shores", "vault", "touch_phone", "quest_complete", "companions", "phone_play", "phone_bag", "phone_menu", "phone_chat", "phone_map", "phone_loot", "phone_loot_bag", "login_account", "wall_plus", "buy_fame", "buy_fame_waiting"]


## A second step, applied after the first rendered frame, for scenarios whose
## picture is of a transition between two states rather than of one state.
static func advance(name: String, state: RealmState) -> void:
	if name != "transition_named":
		return
	# The server's order: the tiles, then where we are standing, then what the
	# place is called.
	state.apply_packet("LoadMapPacket", {"realmId": 7, "mapId": 31,
		"mapWidth": 128, "mapHeight": 128, "tiles": []})
	state.apply_packet("ObjectMovePacket", {"movements": [{
		"entityType": GameConstants.ENTITY_PLAYER, "entityId": state.local.id,
		"posX": 0.0, "posY": 0.0, "velX": 0.0, "velY": 0.0, "flags": 0}]})
	state.apply_packet("TextPacket",
		{"from": "SYSTEM", "to": "Ruu", "message": "Sunken Shore (Nightmare)"})


static func apply(name: String, state: RealmState) -> void:
	match name:
		"terrain": _terrain(state)
		"overlap": _overlap(state)
		"entities": _entities(state)
		"ysort": _ysort(state)
		"bullets": _bullets(state)
		"collision": _collision(state)
		"walk_left": _walking(state, Vector2.LEFT)
		"walk_right": _walking(state, Vector2.RIGHT)
		"walk_up": _walking(state, Vector2.UP)
		"walk_down": _walking(state, Vector2.DOWN)
		"walls": _walls(state)
		"feather": _feather(state)
		"effects": _effects(state)
		"walldepth": _wall_depth(state)
		"wall_plus": _wall_plus(state)
		"shadows": _shadows(state)
		"attack_left": _attacking(state, Vector2.LEFT)
		"attack_right": _attacking(state, Vector2.RIGHT)
		"attack_up": _attacking(state, Vector2.UP)
		"spin": _spin(state)
		"portals": _portals(state)
		"transition": _transition(state)
		"transition_named": _transition_named(state)
		"damage": _damage(state)
		"damage_fading": _damage_fading(state)
		"chat": _chat(state)
		"chat_typing": _chat(state)
		"chat_bubbles": _chat_bubbles(state)
		"death": _entities(state)
		"wading": _wading(state)
		"inventory": _inventory(state)
		"abilities": _abilities(state)
		"potion_storage": _potion_storage(state)
		"fame_store": _fame_store(state)
		"forge": _forge(state)
		"exchange_market": _exchange_market(state)
		"wall_bands": _wall_bands(state)
		"effects_cast": _effects_cast(state)
		"effects_generic": _effects_generic(state)
		"effects_holy", "effects_dark", "effects_arcane", "effects_knight", "effects_rogue", "effects_trapper", "effects_heavy":
			_effects_group(state, EFFECT_GROUPS[name.trim_prefix("effects_")])
		"trade": _trade(state)
		"minimap": _minimap(state)
		"minimap_hop": _minimap_hop(state)
		"player_hud": _player_hud(state)
		"party": _party(state)
		"nearby": _nearby(state)
		"item_card": _item_card(state)
		"options", "options_controls", "dev_overlay": _entities(state)
		"masteries": _masteries(state)
		"blind": _blind(state)
		"dyes": _dyes(state)
		"quests", "quest_stars": _quests(state)
		"loot_preview": _loot_preview(state)
		"vault": _vault(state)
		"touch_phone": _inventory(state)
		"companions": _companions(state)
		"phone_play", "phone_bag", "phone_menu", "phone_chat": _phone_play(state)
		"phone_map": _minimap(state)
		"phone_loot", "phone_loot_bag": _phone_loot(state)
		"quest_complete": _quest_complete(state)
		"trails": _trails(state)
		"billboards": _billboards(state)
		"chunk_seams": _chunk_seams(state)
		"shores": _shores(state)
		"buy_fame", "buy_fame_waiting", "leaderboard": _entities(state)
		# The login screen: no realm at all, the capture raises the screen itself.
		"login", "login_account", "login_delete", "login_stats", "terms", "how_to": pass
		_: push_error("unknown scenario '%s'" % name)


## An account as the character picker lists it: three living, one fallen.
static func account() -> Array:
	return [
		{"characterUuid": "a1", "characterClass": 0, "stats": {"hp": 720, "spd": 50, "xp": 3250000}},
		{"characterUuid": "a2", "characterClass": 2, "stats": {"hp": 540, "spd": 45, "xp": 640000}},
		{"characterUuid": "a3", "characterClass": 1, "stats": {"hp": 610, "spd": 55, "xp": 42000}},
		{"characterUuid": "a4", "characterClass": 3, "stats": {"hp": 300, "spd": 20},
			"deleted": "2026-09-20T18:00:00Z"},
	]


## What the data service's /data/fame/packages answers, as Buy Fame lists it.
static func fame_packages() -> Dictionary:
	return {"enabled": true, "currency": "usd", "packages": [
		{"id": "fame_5k", "fame": 5000, "priceCents": 499, "label": "5,000 Fame"},
		{"id": "fame_15k", "fame": 15000, "priceCents": 999, "label": "15,000 Fame", "tag": "Popular"},
		{"id": "fame_40k", "fame": 40000, "priceCents": 2499, "label": "40,000 Fame"},
		{"id": "fame_100k", "fame": 100000, "priceCents": 4999, "label": "100,000 Fame", "tag": "Best value"}]}


## The game servers the sign-in's picker lists.
static func servers() -> Array:
	return [{"name": "US East", "route": "/ws/gravebound", "host": "us.grave-bound.com", "webSocketPort": 2223},
		{"name": "EU West", "route": "/ws/gravebound1", "host": "eu.grave-bound.com", "webSocketPort": 2223}]


## A played character's lifetime metrics, as the service reports them.
static func lifetime_report() -> Dictionary:
	return {"projectilesFired": 48210.0, "projectilesHit": 31077.0, "projectilesMissed": 17133.0,
		"damageDealtTotal": 2841530.0, "damageTakenTotal": 190422.0, "killsTotal": 3312.0,
		"bossKills": 41.0, "deaths": 2.0, "abilityCastsTotal": 1204.0, "abilityDamageDealt": 402113.0,
		"abilityEnemiesAffected": 5120.0, "abilityAlliesAffected": 88.0, "abilityBuffSecondsAlly": 640.0,
		"abilityDebuffSecondsEnemy": 3010.0, "itemsPickedUp": 912.0, "itemsEnchanted": 14.0,
		"hpPotionsDrank": 230.0, "mpPotionsDrank": 118.0, "xpEarned": 1840000.0,
		"skillPointsSpent": 19.0, "playTimeSeconds": 81240.0, "tradesCompleted": 6.0,
		"chatMessagesSent": 377.0, "pvpMatches": 12.0, "pvpWins": 7.0, "pvpLosses": 5.0,
		"dungeonCompletionsByDungeonId": {"1": 4.0, "5": 11.0, "3": 7.0}}


## A floor with a wall border, from real content ids.
static func _terrain(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-6, 7):
		for y in range(-5, 6):
			var wall: bool = x == -6 or x == 6 or y == -5 or y == 5
			tiles.append({"tileId": WALL_TILE if wall else FLOOR_TILE,
				"layer": 1 if wall else 0, "xIndex": y, "yIndex": x})
	state.apply_packet("LoadMapPacket", _map(tiles))


static func _entities(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.name = "Ruu"
	state.local.class_id = 0
	state.local.position = Vector2(-16, 0)
	state.apply_packet("LoadPacket", {
		"players": [
			_player(1, "Ruu", Vector2(-16, 0), 0),
			_player(2, "Mingau", Vector2(48, -40), 2),
		],
		"enemies": [_enemy(3, 1, Vector2(-80, -48), 4000, 4000),
			_enemy(4, 2, Vector2(64, 40), 30, 100)],
		"containers": [{"lootContainerId": 5, "tier": 2, "isChest": true,
			"items": [{}, {}], "pos": {"x": -96.0, "y": 48.0}}],
		"portals": [{"id": 6, "portalId": 1, "toRealmId": 2,
			"pos": {"x": 96.0, "y": -96.0},
			"targetLabel": "Grasslands", "targetTier": 2}],
	})


## Overlapping pairs arranged so that correct depth ordering and raw child
## order disagree.
##
## Sprites are synced players-first, so an unsorted layer always draws enemies
## over players. The left pair has the enemy ABOVE the player, where correct
## sorting must put the *player* in front -- that is the pair that fails if
## y-sorting regresses. The right pair is the opposite arrangement and should
## look the same either way, which isolates the difference to the left.
static func _ysort(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-72, 8)
	state.apply_packet("LoadPacket", {
		"players": [
			_player(1, "Front", Vector2(-72, 8), 0),
			_player(2, "Behind", Vector2(48, -8), 0),
		],
		"enemies": [
			_enemy(3, 2, Vector2(-64, -8), 100, 100),
			_enemy(4, 2, Vector2(56, 8), 100, 100),
		],
	})


## A fan of projectiles, to check rotation follows travel direction.
static func _bullets(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-16, -16)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, -16), 0)]})
	var id := 100
	for step in 8:
		var angle := float(step) * TAU / 8.0
		state.projectiles.bullets[id] = Projectile.from_wire({
			"id": id, "projectileId": 87, "size": 16,
			"pos": {"x": 48.0 * sin(angle), "y": 48.0 * cos(angle)},
			"angle": angle, "magnitude": 4.0, "range": 500.0, "flags": [],
			"invert": false, "timeStep": 0, "amplitude": 0, "frequency": 0,
			"orbitCenterX": 0.0, "orbitCenterY": 0.0, "orbitRadius": 0.0,
			"orbitPhase": 0.0, "damage": 1, "createdTime": 0}, 0)
		id += 1


## Players carrying status effects, so the tints are visible side by side.
##
## A multiply over the sprite, the way the web client does it; a wrong colour
## or a tint leaking onto the wrong character shows up here immediately.
static func _effects(state: RealmState) -> void:
	_terrain(state)
	var shown := [StatusTint.POISONED, StatusTint.BERSERK, StatusTint.CURSED,
		StatusTint.STASIS, StatusTint.SPEEDY]
	var players: Array = []
	var id := 10
	for i in shown.size():
		players.append(_player(id + i, "", Vector2(-96.0 + 48.0 * i, -16.0), 0))
	# One with nothing on it, as the control.
	players.append(_player(id + shown.size(), "", Vector2(-96.0 + 48.0 * shown.size(), 32.0), 0))
	state.apply_packet("LoadPacket", {"players": players})
	for i in shown.size():
		state.apply_packet("PlayerStatePacket", {
			"playerId": id + i, "health": 100, "mana": 10,
			"effectIds": [shown[i]], "effectTimes": [], "effectStacks": []})


## Two terrain types meeting, so the seam fringes are visible.
##
## Sand against grass: different enough in colour to clear the blend gate, and
## laid out as quadrants plus a lone island so both straight edges and corners
## show. Without feathering these read as a hard checkerboard boundary.
const GRASS_TILE := 13


static func _feather(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-7, 8):
		for y in range(-6, 7):
			var grass: bool = (x < 0) == (y < 0)
			tiles.append({"tileId": GRASS_TILE if grass else FLOOR_TILE,
				"layer": 0, "xIndex": y, "yIndex": x})
	# A single grass cell inside the sand, so all four fringes meet on one tile.
	tiles.append({"tileId": GRASS_TILE, "layer": 0, "xIndex": -3, "yIndex": 4})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.local.id = 1
	state.local.position = Vector2(-16, -16)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, -16), 0)]})


## LINE_SEGMENT walls, which are a row of sprites along the axis perpendicular
## to their facing rather than one stretched sprite -- and a MELEE_SWING,
## which must not draw at all.
static func _walls(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-16, -16)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, -16), 0)]})
	var id := 200
	for step in 3:
		var angle := float(step) * PI / 3.0
		state.projectiles.bullets[id] = _bullet(id, angle, Vector2(0.0, -64.0 + 64.0 * step), {
			"length": 96, "flags": [ProjectileKind.LINE_SEGMENT]})
		id += 1
	# Invisible: the wielder's swing animation stands in for it.
	state.projectiles.bullets[id] = _bullet(id, 0.0, Vector2(64.0, 64.0), {
		"flags": [ProjectileKind.MELEE_SWING]})


static func _bullet(id: int, angle: float, position: Vector2, overrides: Dictionary) -> Projectile:
	var wire := {
		"id": id, "projectileId": 87, "size": 16,
		"pos": {"x": position.x, "y": position.y},
		"angle": angle, "magnitude": 0.0, "range": 500.0, "flags": [],
		"invert": false, "timeStep": 0, "amplitude": 0, "frequency": 0,
		"orbitCenterX": 0.0, "orbitCenterY": 0.0, "orbitRadius": 0.0,
		"orbitPhase": 0.0, "damage": 1, "createdTime": 0, "length": 0,
	}
	wire.merge(overrides, true)
	return Projectile.from_wire(wire, 0)


## The local player mid-walk in one direction.
##
## Facing is the renderer's only per-entity state, and the sheet has no
## left-facing clip -- walking left is the side clip mirrored -- so a wrong
## facing or a lost mirror silently draws the player walking the wrong way.
## Four captures because facing is tracked for the local player only, and
## there is exactly one of those.
static func _walking(state: RealmState, direction: Vector2) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.name = "Ruu"
	state.local.class_id = 0
	state.local.position = Vector2(-16, -16)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, -16), 0)]})
	# Straight through the model rather than assigning facing, so the scenario
	# exercises the same path a held key does.
	state.local.moving = true
	state.local.face_toward(direction)


static func _collision(state: RealmState) -> void:
	_entities(state)


## Entities standing directly on collision-layer tiles.
##
## Terrain draws before entities, so an overlay tile under a character must
## not cover them. A *wall* legitimately does -- its top face is stamped back
## over the entities for depth, which walldepth covers -- so this uses a
## non-wall collision tile to keep testing the original rule.
static func _overlap(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-4, 5):
		for y in range(-3, 4):
			tiles.append({"tileId": FLOOR_TILE, "layer": 0, "xIndex": y, "yIndex": x})
			tiles.append({"tileId": DEEP_WATER_TILE, "layer": 1, "xIndex": y, "yIndex": x})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.local.id = 1
	state.local.position = Vector2(-16, 0)
	state.apply_packet("LoadPacket", {
		"players": [_player(1, "OnTop", Vector2(-16, 0), 0)],
		"enemies": [_enemy(3, 1, Vector2(32, 0), 100, 100)],
	})


## The three shapes a portal can take: defined art with a captioned target,
## defined art with no realm behind it (the vault, which gets no caption), and
## a portalId the content does not define, which must stay visible as a block
## rather than becoming an invisible doorway.
static func _portals(state: RealmState) -> void:
	_terrain(state)
	# Standing on the first portal, so it expands into its card; and the
	# realm itself mid-cleanse, so the banner shows the purification line.
	state.local.id = 1
	state.local.position = Vector2(-94, -62)
	state.apply_packet("RealmPurificationPacket", {"realmId": 1, "progress": 43, "goal": 100,
		"difficulty": 2.5, "tier": 2, "modifiers": "Frenzy, Fog"})
	state.apply_packet("LoadPacket", {
		"players": [_player(1, "Ruu", Vector2(-94, -62), 0)],
		"portals": [
			{"id": 6, "portalId": 1, "toRealmId": 2, "pos": {"x": -96.0, "y": -64.0},
				"targetLabel": "Grasslands", "targetTier": 2, "targetDifficulty": 3.5,
				"targetPlayerCount": 4, "targetPurificationProgress": 43,
				"targetPurificationGoal": 100, "targetModifiers": "Frenzy, Fog"},
			{"id": 7, "portalId": 2, "toRealmId": 3, "pos": {"x": 0.0, "y": -64.0},
				"targetLabel": ""},
			{"id": 8, "portalId": 999, "toRealmId": 4, "pos": {"x": 96.0, "y": -64.0},
				"targetLabel": "Undefined", "targetTier": 0},
		],
	})


## Mid-transition: we have asked to leave, the realm is torn down, and the
## next one has not arrived. The splash covers it -- the caption, the
## class walking, and the difficulty of the portal taken (3.6: four pips).
static func _transition(state: RealmState) -> void:
	_portals(state)
	state.local.id = 1
	state.local.name = "Ruu"
	state.local.position = Vector2(-16, 40)
	state.begin_transition(3.6)


## The same wait, once the server has said where we are going. Both images
## exist because the caption has two branches and one golden can only ever
## prove one of them.
##
## The arrival itself is in `advance()`, because it has to happen on a later
## frame than the wait: the server sends the tiles and only then the name, so
## the named splash is the FADE, not the cover. Applying both in one step
## produced a frame no live session reaches.
static func _transition_named(state: RealmState) -> void:
	_transition(state)
	state.local.name = "Ruu"


## Combat numbers as a real fight produces them: a burst on one enemy that
## merges into a single count, a heal on the player, a status label riding the
## lane above it, and an armor-pierce hit elsewhere -- four of the five colours
## and both lanes in one frame.
static func _damage(state: RealmState) -> void:
	_entities(state)
	for i in 3:
		_text(state, 0, "42", Vector2(64, 40))
	_text(state, 0, "17", Vector2(64, 40))
	_text(state, 1, "+120", Vector2(-16, 0))
	_text(state, 4, "SLOWED", Vector2(-16, 0))
	_text(state, 2, "88", Vector2(-80, -48))


## What the panel has to survive: a SYSTEM line, ordinary chatter, a long
## sender name, and a line longer than the panel is wide -- with each name in
## its chat role's colour, which the server sends in `to`: Mingau a moderator
## (green, over the head too), Ruu no role (the log's blue), the long name
## the sysadmin's red, and the Overseer in its own gold.
static func _chat(state: RealmState) -> void:
	_entities(state)
	var mod := _player(2, "Mingau", Vector2(48, -40), 2)
	mod["chatRole"] = "mod"
	state.apply_packet("LoadPacket", {"players": [mod]})
	_said(state, "SYSTEM", "Welcome to Nexus Auru V1")
	_said(state, "Mingau", "anyone running the beach?", "mod")
	_said(state, "Ruu", "give me a sec, swapping my ring")
	_said(state, "AVeryLongCharacterName", "on my way -- meet at the portal", "sysadmin")
	_said(state, "Overseer", "The realm grows restless")
	_said(state, "SYSTEM", "Mingau has entered the realm and this line is long enough to run past the panel")


## What was just said, over the heads that said it: a short line, and one
## long enough to wrap, on the local player.
static func _chat_bubbles(state: RealmState) -> void:
	_entities(state)
	_said(state, "Mingau", "anyone running the beach?")
	_said(state, "Ruu", "give me a sec, swapping my ring -- and this one is long enough to wrap")
	_said(state, "SYSTEM", "nothing over anyone's head for this")


## The same numbers, most of a second later. Everything time-dependent lives
## here and nowhere else: without a scenario that advances the clock, the fade,
## the float and the shrink all render identically to a fresh frame, and no
## image in the suite can fail on any of them.
static func _damage_fading(state: RealmState) -> void:
	_damage(state)
	state.advance(0.9, Vector2.ZERO, 0.0)


static func _said(state: RealmState, from: String, message: String, to := "") -> void:
	state.apply_packet("TextPacket", {"from": from, "to": to, "message": message})


static func _text(state: RealmState, effect_id: int, label: String,
		at: Vector2) -> void:
	state.apply_packet("TextEffectPacket", {
		"textEffectId": effect_id, "entityType": 1, "targetEntityId": 0,
		"text": label, "posX": at.x, "posY": at.y})


## Standing in shallow water, which takes the legs off the character we are
## playing and nobody else's -- the web client asks this of one entity. The
## remote player beside us is in the same pool with its feet on.
static func _wading(state: RealmState) -> void:
	_terrain(state)
	var pool: Array = []
	for x in range(-4, 5):
		for y in range(0, 3):
			pool.append({"tileId": SHALLOW_WATER_TILE, "layer": 0, "xIndex": y, "yIndex": x})
	state.apply_packet("LoadMapPacket", _map(pool))

	state.local.id = 1
	state.local.name = "Ruu"
	state.local.class_id = 0
	state.local.position = Vector2(-16, 16)
	state.apply_packet("LoadPacket", {"players": [
		_player(1, "Ruu", Vector2(-16, 16), 0),
		_player(2, "Mingau", Vector2(48, 16), 2),
	]})


## The bag as the panel has to draw it: gear in every equipment slot, a
## backpack with stacks in it, potions to drink, and a loot bag at our feet
## so the strip is open. Real item ids, so the icons come off the shipped
## sheets -- 16px weapons beside 8px gauntlets in one row is the point.
static func _inventory(state: RealmState) -> void:
	_entities(state)
	var carried: Array = []
	for i in Inventory.SIZE:
		carried.append({"itemId": -1})
	carried[0] = _item(49)       # Goblin Sword
	carried[1] = _item(3010)     # Wood Heavy Plate
	carried[2] = _item(839)      # Worn Leather Gauntlets
	carried[3] = _item(845)      # Tattered Boots
	carried[4] = _item(8)        # Lesser Ring of Attack
	carried[5] = _item(50)       # Goblin Axe
	carried[6] = _item(0, {"stackable": true, "stackCount": 4})     # Potion of Defense
	carried[7] = _item(800, {"stackable": true, "stackCount": 10})  # a full shard stack
	carried[12] = _item(3012)    # Wood Cloak
	state.apply_packet("UpdatePacket", {"playerId": state.local.id, "playerName": "Ruu",
		"stats": {}, "health": 100, "mana": 50, "experience": 0, "inventory": carried,
		"hpPotions": 3, "mpPotions": 1, "dyeId": 0})
	state.apply_packet("LoadPacket", {"containers": [{"lootContainerId": 9, "tier": 1,
		"isChest": false, "items": [_item(51), _item(846), {"itemId": -1}],
		"pos": {"x": -16.0, "y": 0.0}}]})


## The bar and what a cast leaves behind: a barbarian's three abilities with
## points in two of them, the middle one half cooled, the cast-range ring
## still fading, an effect that has just landed, and a neighbour mid-cast.
## Times are poked in directly, since the scenario clock stands at zero.
static func _abilities(state: RealmState) -> void:
	_entities(state)
	state.abilities.apply_update({"playerId": 1, "availableSkillPoints": 2,
		"investedSlot0": 1, "investedSlot2": 3}, 1)
	state.abilities.cooldown_until[1] = 3000
	state.abilities.cooldown_total[1] = 6000
	state.abilities.show_ring(state.local.centre(), 96.0)
	state.apply_packet("CreateEffectPacket", {"effectType": 0, "posX": 64.0, "posY": 40.0,
		"radius": 48.0, "duration": 1000, "targetPosX": 0.0, "targetPosY": 0.0,
		"tier": 3, "ownerId": 1})
	state.abilities.effects[0]["started"] = -400
	state.apply_packet("AbilityCastStartPacket", {"playerId": 2, "abilityId": 13006, "slot": 0,
		"durationMs": 1000, "worldTargetX": 0.0, "worldTargetY": -40.0})
	state.abilities.casts[2]["started"] = -500


## The potion storage open beside the bag, with the shelves the vault keeps:
## stacks of stat potions and shards. The Forge tile stands two cells away,
## so the prompt is up as well.
static func _potion_storage(state: RealmState) -> void:
	_inventory(state)
	state.apply_packet("LoadMapPacket", _map([{"tileId": 300, "layer": 1, "xIndex": -2, "yIndex": 1}]))
	var shelves: Array = []
	for i in ItemStore.SIZE:
		shelves.append({"itemId": -1})
	shelves[0] = _item(0, {"stackable": true, "stackCount": 10})
	shelves[1] = _item(1, {"stackable": true, "stackCount": 3})
	shelves[5] = _item(800, {"stackable": true, "stackCount": 7})
	shelves[16] = _item(801, {"stackable": true, "stackCount": 1})
	state.apply_packet("OpenItemStorePacket", {"storeKind": 0, "playerId": state.local.id,
		"items": shelves})


## The fame store open with a balance that covers the cheap rows and not
## the crown, so both states of the Buy button are in one frame.
static func _fame_store(state: RealmState) -> void:
	_entities(state)
	state.apply_packet("OpenFameStorePacket", {"playerId": state.local.id, "accountFame": 1200})


## The forge open with a full bench: the armour we wear, a crystal, and
## fifty armour essence -- every check satisfied, so the line reads green and
## Enchant is live. Real ids, so the icons are the shipped ones.
static func _forge(state: RealmState) -> void:
	_inventory(state)
	var bag := state.local.inventory
	bag.put(8, _item(813, {"name": "Def Crystal", "category": "crystal", "forgeStatId": 5}))
	bag.put(9, _item(818, {"name": "Armor Essence", "category": "essence", "forgeSlotId": 1,
		"stackable": true, "stackCount": 50, "maxStack": 50}))
	bag.slots[1]["rarity"] = 1
	bag.slots[1]["name"] = "Wood Heavy Plate"
	state.apply_packet("OpenForgePacket", {"playerId": state.local.id})
	state.forge.assign("target", 1)
	state.forge.assign("crystal", 8)
	state.forge.assign("essence", 9)


## A whole small map for the minimap: a walled floor with a pond and a lava
## field, three players and a realm event -- everything the picture has a
## colour or a shape for. The local player stands mid-map, facing right.
static func _minimap(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(0, 40):
		for y in range(0, 30):
			var edge: bool = x == 0 or x == 39 or y == 0 or y == 29
			var pond: bool = x >= 8 and x <= 14 and y >= 6 and y <= 11
			var lava: bool = x >= 25 and x <= 32 and y >= 18 and y <= 22
			var floor_id := SHALLOW_WATER_TILE if pond else (LAVA_TILE if lava else FLOOR_TILE)
			tiles.append({"tileId": floor_id, "layer": 0, "xIndex": y, "yIndex": x})
			if edge:
				tiles.append({"tileId": WALL_TILE, "layer": 1, "xIndex": y, "yIndex": x})
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 1, "mapWidth": 40,
		"mapHeight": 30, "tiles": tiles})
	state.local.id = 1
	state.local.name = "Ruu"
	state.local.class_id = 0
	state.local.position = Vector2(640, 480)
	state.local.face_toward(Vector2.RIGHT)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(640, 480), 0)],
		"enemies": [], "containers": [], "portals": []})
	state.apply_packet("GlobalPlayerPositionPacket", {"players": [
		{"playerId": 1, "name": "Ruu", "x": 640.0, "y": 480.0, "teleportable": true},
		{"playerId": 2, "name": "Mingau", "x": 160.0, "y": 200.0, "teleportable": true},
		{"playerId": 3, "name": "Ghost", "x": 900.0, "y": 700.0, "teleportable": false}]})
	_said(state, ChatLog.EVENT_MARKER, "ADD|7|99|400|600|Sand Wyrm")


## The same map in an admin's hop mode: the server's answer to /hop has
## come, and the badge says a click will teleport.
static func _minimap_hop(state: RealmState) -> void:
	_minimap(state)
	_said(state, ChatLog.SYSTEM, "Hop mode: ON")


## Four shots crossing the view, each trailing its own kind of particle:
## smoke (250), tar with its afterimage (1019), sparks with an impact
## (1020) and a bare afterimage (1372). Forty frames of flight so the
## trails have length, then the spark shot is removed and six more frames
## let its burst open. The field's own RNG is seeded, so the picture is
## the same every capture.
static func _trails(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-16, -16)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, -16), 0)]})
	state.particles.rng.seed = 7
	var groups := [250, 1019, 1020, 1372]
	var sizes := [44, 26, 30, 24]
	for i in 4:
		var angle := float(i) * TAU / 4.0 + TAU / 8.0
		var heading := Vector2(sin(angle), cos(angle))
		state.projectiles.bullets[200 + i] = _bullet(200 + i, angle, -heading * 64.0 - Vector2(sizes[i], sizes[i]) * 0.5,
			{"projectileId": groups[i], "magnitude": 3.0, "size": sizes[i]})
	for frame in 40:
		state.advance(1.0 / 60.0, Vector2.ZERO, 0.0)
	state.projectiles.bullets.erase(202)
	for frame in 6:
		state.advance(1.0 / 60.0, Vector2.ZERO, 0.0)


## The exchange market open over a bag of shards, crystals and essences,
## with a swap set up: five Vit Crystal Shards for four Wis.
static func _exchange_market(state: RealmState) -> void:
	_inventory(state)
	var bag := state.local.inventory
	bag.put(8, _item(800, {"name": "Vit Crystal Shard", "category": "shard", "stackable": true, "stackCount": 5, "maxStack": 10}))
	bag.put(9, _item(808, {"name": "Vit Crystal", "category": "crystal"}))
	bag.put(10, _item(818, {"name": "Armor Essence", "category": "essence", "stackable": true, "stackCount": 12, "maxStack": 50}))
	state.apply_packet("OpenExchangeMarketPacket", {"playerId": state.local.id})
	state.market.select_source(800, 5)
	state.market.select_target(801)
	state.market.set_quantity(5, 5)


## A room of square walls with a doorway, a free-standing pillar in it and
## a tall wall beside for contrast: every kind of exposure in one picture.
static func _wall_bands(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-7, 8):
		for y in range(-5, 6):
			tiles.append({"tileId": FLOOR_TILE, "layer": 0, "xIndex": y, "yIndex": x})
	for x in range(-5, 6):
		for y in range(-4, 5):
			var edge: bool = x == -5 or x == 5 or y == -4 or y == 4
			var doorway: bool = y == 4 and x in [0, 1]
			var pillar: bool = x == 2 and y == 0
			if (edge and not doorway) or pillar:
				tiles.append({"tileId": SQUARE_WALL_TILE, "layer": 1, "xIndex": y, "yIndex": x})
	for x in [-3, -2]:
		tiles.append({"tileId": WALL_TILE, "layer": 1, "xIndex": 0, "yIndex": x})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.local.id = 1
	state.local.position = Vector2(-16, 32)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, 32), 0)]})


## The six effects drawn by hand so far, laid out in two rows and caught
## a third of the way through -- each effect's start is moved back so the
## pinned clock finds it mid-flight -- plus a bolt to a target and a sword
## swing at the aim.
static func _effects_cast(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-16, 0)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, 0), 0)]})
	# Radii scaled down from the server's so six fit in one frame.
	var casts := [
		[63, Vector2(-200, -140), 56.0, 1400, Vector2.ZERO, 0],
		[10, Vector2(0, -140), 56.0, 700, Vector2.ZERO, 6],
		[9, Vector2(200, -140), 56.0, 1100, Vector2.ZERO, 5],
		[3, Vector2(-260, 120), 20.0, 600, Vector2(-120, 90), 2],
		[14, Vector2(0, 140), 60.0, 1400, Vector2.ZERO, 3],
		[62, Vector2(230, 90), 24.0, 400, Vector2(180, 130), 1],
	]
	for cast in casts:
		state.apply_packet("CreateEffectPacket", {"effectType": cast[0], "posX": cast[1].x, "posY": cast[1].y,
			"radius": cast[2], "duration": cast[3], "targetPosX": cast[4].x, "targetPosY": cast[4].y,
			"tier": cast[5], "ownerId": 1})
	for fx in state.abilities.effects:
		fx["started"] = -int(fx["duration_ms"] / 3)


## The generic form, which only an id this build does not know can reach
## now: retired 21 and 48-50 stand in for a newer server's, in the tier
## colours, then the boss-grenade sentinel in its three, all mid-flight.
static func _effects_generic(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-16, 0)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, 0), 0)]})
	var casts := [[21, Vector2(-200, -140), 1], [48, Vector2(0, -140), 3], [49, Vector2(200, -140), 6],
		[50, Vector2(-200, 120), 0], [21, Vector2(-40, 120), 10], [21, Vector2(90, 120), 11], [21, Vector2(220, 120), 12]]
	for cast in casts:
		state.apply_packet("CreateEffectPacket", {"effectType": cast[0], "posX": cast[1].x, "posY": cast[1].y,
			"radius": 48.0, "duration": 900, "targetPosX": 0.0, "targetPosY": 0.0, "tier": cast[2], "ownerId": 1})
	for fx in state.abilities.effects:
		fx["started"] = -int(fx["duration_ms"] * 0.4)


## A quest done, four ways through it: on the player just after the flash,
## then three more, ownerless so they stay put, as the fountain rises,
## peaks and falls away.
static func _quest_complete(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-16, 0)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, 0), 0)]})
	var ages := [[1, Vector2(-2, 14), 120], [0, Vector2(-120, 60), 380], [0, Vector2(110, 60), 700],
		[0, Vector2(0, -70), 1100]]
	for spec in ages:
		state.apply_packet("CreateEffectPacket", {"effectType": EffectType.QUEST_COMPLETE, "posX": spec[1].x,
			"posY": spec[1].y, "radius": 48.0, "duration": 1800, "targetPosX": 0.0, "targetPosY": 0.0,
			"tier": 0, "ownerId": spec[0]})
	for i in state.abilities.effects.size():
		state.abilities.effects[i]["started"] = -int(ages[i][2])


## Each group of ported effects: [type, radius, target offset from the
## effect (zero for an area, which the server sends as 0,0), tier], laid
## out three to a row by _effects_group. Radii are scaled down from the
## server's so nine fit in one frame; a line effect -- a dash, a beam, a
## thrown lob at radius 0 -- runs to its offset.
const EFFECT_GROUPS := {
	"holy": [[EffectType.HEAL_RADIUS, 44.0, Vector2.ZERO, 3], [EffectType.WATER_FOUNTAIN, 44.0, Vector2.ZERO, 2],
		[EffectType.SMITE_FLASH, 36.0, Vector2.ZERO, 4], [EffectType.INSPIRE_BLOOM, 44.0, Vector2.ZERO, 3],
		[EffectType.SANCTUARY_DOME, 48.0, Vector2.ZERO, 5], [EffectType.DIVINE_BEAM, 40.0, Vector2.ZERO, 3],
		[EffectType.FORTIFY_AURA, 44.0, Vector2.ZERO, 1]],
	"dark": [[EffectType.VAMPIRISM, 44.0, Vector2.ZERO, 5], [EffectType.POISON_CLOUD, 44.0, Vector2.ZERO, 2],
		[EffectType.LIFE_DRAIN, 44.0, Vector2.ZERO, 5], [EffectType.BONE_SPIKES, 40.0, Vector2.ZERO, 0],
		[EffectType.DEATH_PACT_AURA, 40.0, Vector2.ZERO, 6], [EffectType.SOUL_VORTEX, 48.0, Vector2.ZERO, 6],
		[EffectType.VAMPIRIC_LATCH, 44.0, Vector2.ZERO, 5]],
	"arcane": [[EffectType.STASIS_FIELD, 48.0, Vector2.ZERO, 2], [EffectType.BLINK_GLYPH, 36.0, Vector2.ZERO, 6],
		[EffectType.LIGHTNING_STRIKE, 36.0, Vector2.ZERO, 3], [EffectType.MANA_BOLT, 36.0, Vector2.ZERO, 6],
		[EffectType.TIME_STOP, 48.0, Vector2.ZERO, 1], [EffectType.ARCANE_AURA, 40.0, Vector2.ZERO, 6],
		[EffectType.STORM_AURA, 40.0, Vector2.ZERO, 1]],
	"knight": [[EffectType.KNIGHT_SHOCKWAVE, 40.0, Vector2(90, 20), 3], [EffectType.WARRIOR_BUFF, 44.0, Vector2.ZERO, 4],
		[EffectType.SHIELD_DOME, 40.0, Vector2.ZERO, 0], [EffectType.TAUNT_ROAR, 36.0, Vector2.ZERO, 5],
		[EffectType.BRACE_STANCE, 40.0, Vector2.ZERO, 0], [EffectType.WAR_CRY_WAVE, 48.0, Vector2.ZERO, 4],
		[EffectType.BANNER_RAISE, 36.0, Vector2.ZERO, 5], [EffectType.RAMPAGE_AURA, 40.0, Vector2.ZERO, 5]],
	"rogue": [[EffectType.NINJA_DASH, 20.0, Vector2(140, 30), 1], [EffectType.BEAST_CLAWS, 36.0, Vector2.ZERO, 4],
		[EffectType.DEATH_BLOSSOM, 44.0, Vector2.ZERO, 6], [EffectType.RECKLESS_SLASH, 40.0, Vector2.ZERO, 5],
		[EffectType.STAR_SHURIKEN, 32.0, Vector2.ZERO, 2], [EffectType.BLADE_STORM, 40.0, Vector2.ZERO, 0],
		[EffectType.BLADE_ORBIT, 40.0, Vector2.ZERO, 3], [EffectType.BLADE_BLENDER, 48.0, Vector2.ZERO, 6]],
	"trapper": [[EffectType.CURSE_RADIUS, 40.0, Vector2.ZERO, 4], [EffectType.CURSE_RADIUS, 40.0, Vector2.ZERO, 10],
		[EffectType.POISON_SPLASH, 0.0, Vector2(120, -30), 2], [EffectType.TRAP_THROW, 40.0, Vector2.ZERO, 3],
		[EffectType.TRAP_PLACED, 40.0, Vector2.ZERO, 3], [EffectType.TRAP_TRIGGER, 40.0, Vector2.ZERO, 3],
		[EffectType.SNARE_GEAR, 40.0, Vector2.ZERO, 1], [EffectType.COMBUSTION_TRAP, 44.0, Vector2.ZERO, 4],
		[EffectType.CALTROPS, 44.0, Vector2.ZERO, 0], [EffectType.HASTE_WIND, 36.0, Vector2.ZERO, 2]],
	"heavy": [[EffectType.FROST_NOVA, 44.0, Vector2.ZERO, 2], [EffectType.RAPIER_STAB, 36.0, Vector2.ZERO, 0],
		[EffectType.LOW_SWING, 40.0, Vector2.ZERO, 5], [EffectType.DISARM_FLOURISH, 40.0, Vector2.ZERO, 3],
		[EffectType.GROUND_POUND, 44.0, Vector2.ZERO, 0], [EffectType.DRUID_ROOTS, 44.0, Vector2.ZERO, 2],
		[EffectType.DRUID_MOONLIGHT, 44.0, Vector2.ZERO, 1], [EffectType.DRUID_WILD_SURGE, 44.0, Vector2.ZERO, 2],
		[EffectType.BEAM_WARNING, 8.0, Vector2(160, 20), 0]],
}


## One group of effects on a grid of 180 x 130, three or four to a row,
## each caught a third of the way through on the pinned clock.
static func _effects_group(state: RealmState, casts: Array) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.position = Vector2(-16, 0)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, 0), 0)]})
	var per_row := 3 if casts.size() <= 9 else 4
	for i in casts.size():
		var cast: Array = casts[i]
		var at := Vector2(-180.0 * (per_row - 1) / 2.0 + 180.0 * (i % per_row), -150.0 + 150.0 * (i / per_row))
		var target: Vector2 = at + cast[2] if cast[2] != Vector2.ZERO else Vector2.ZERO
		state.apply_packet("CreateEffectPacket", {"effectType": cast[0], "posX": at.x, "posY": at.y,
			"radius": cast[1], "duration": 900, "targetPosX": target.x, "targetPosY": target.y,
			"tier": cast[3], "ownerId": 1})
	for fx in state.abilities.effects:
		fx["started"] = -300


## A trade in progress: our page with two stacks on the table, theirs with
## a crystal and an essence, one of them offered, and their side confirmed.
static func _trade(state: RealmState) -> void:
	_inventory(state)
	var theirs: Array = []
	theirs.resize(Inventory.SIZE)
	theirs.fill({"itemId": -1})
	theirs[5] = _item(808, {"name": "Vit Crystal", "category": "crystal"})
	theirs[6] = _item(818, {"name": "Armor Essence", "category": "essence", "stackable": true, "stackCount": 7, "maxStack": 50})
	theirs[9] = _item(0, {"name": "Potion of Defense", "category": "generic", "consumable": true, "stackable": true, "stackCount": 2, "maxStack": 10})
	state.apply_packet("AcceptTradeRequestPacket", {"accepted": true,
		"player0": _player(state.local.id, "Ruu", Vector2(-16, 0), 0), "player1": _player(2, "Mingau", Vector2(48, -40), 2),
		"player0Inv": [], "player1Inv": theirs})
	state.trade.toggle(5)
	state.trade.toggle(7)
	state.apply_packet("UpdateTradePacket", {"selections": {
		"player0Selection": {"playerId": state.local.id, "selection": state.trade.my_selected, "itemRefs": [], "confirmed": false},
		"player1Selection": {"playerId": 2, "selection": [false, true, false, false, true], "itemRefs": [], "confirmed": true}}})


## Who you are and how you are doing: a barbarian at level 2, half way to
## 3 on the fixture's table, hurt, wearing a sword whose stats and affix
## push STR over its cap -- the value is boosted, the base is not, so it
## stays white -- and boots that cost speed, with the base SPD at its cap.
static func _player_hud(state: RealmState) -> void:
	_entities(state)
	var carried: Array = []
	for i in Inventory.SIZE:
		carried.append({"itemId": -1})
	carried[0] = _item(49, {"stats": {"str": 4}, "attributeModifiers": [{"statId": 4, "deltaValue": 3}]})
	carried[3] = _item(845, {"stats": {"spd": -2}, "enchantments": [{"statId": 5, "deltaValue": 2}]})
	state.apply_packet("UpdatePacket", {"playerId": state.local.id, "playerName": "Ruu",
		"stats": {"hp": 340, "mp": 120, "def": 12, "str": 79, "spd": 48, "dex": 22, "vit": 31, "wis": 15},
		"health": 210, "mana": 120, "experience": 200, "inventory": carried,
		"hpPotions": 2, "mpPotions": 0, "dyeId": 0})


## A party of three with us in it: the leader, a wizard in another realm
## with an ability half way through its cooldown, and a barbarian at half
## health; and an invite from a fourth waiting for an answer.
static func _party(state: RealmState) -> void:
	_entities(state)
	var member := func(id: int, name: String, class_id: int, hp: int, realm: int, bindings: Array, ends: Array) -> Dictionary:
		return {"playerId": id, "name": name, "classId": class_id, "health": hp, "maxHealth": 200,
			"mana": 60, "maxMana": 120, "level": 7, "realmId": realm, "effectIds": [],
			"hotbarBindings": bindings, "abilityCooldownEnds": ends, "hotbarInvested": [1, 0, 2, 0],
			"stats": {"hp": 200, "mp": 120, "def": 8, "str": 30, "spd": 20, "dex": 25, "vit": 12, "wis": 9},
			"equipment": []}
	state.apply_packet("PartyUpdatePacket", {"partyId": 77, "leaderId": 2, "members": [
		member.call(2, "Mingau", 2, 200, 0, [13006, 13007, 13008, 0], [0, PARTY_WALL_MS + 3000, 0, 0]),
		member.call(1, "Ruu", 0, 150, 0, [13000, 0, 13002, 0], [0, 0, 0, 0]),
		member.call(3, "Bort", 0, 100, 999, [13000, 0, 13002, 0], [0, 0, 0, 0]),
	]})
	state.apply_packet("TextPacket", {"from": "SYSTEM", "to": "Ruu",
		"message": "Zed invited you to a party. Type /party accept or /party decline."})


## A phone mid-play: a party, a few lines of chat and the vitals.
static func _phone_play(state: RealmState) -> void:
	_party(state)
	_player_hud(state)
	_said(state, "Mingau", "anyone running the beach?", "mod")
	_said(state, "Ruu", "give me a sec, swapping my ring")
	_said(state, "SYSTEM", "Mingau has entered the realm and this line is long enough to wrap")


## A phone standing on a bag of three.
static func _phone_loot(state: RealmState) -> void:
	_phone_play(state)
	state.apply_packet("LoadPacket", {"containers": [{"lootContainerId": 9, "tier": 1,
		"isChest": false, "items": [_item(51), _item(846), _item(3012)],
		"pos": {"x": state.local.position.x, "y": state.local.position.y}}]})


## Two companions on the bench, one out, with gear, stats short of the caps
## and points to spend.
static func _companions(state: RealmState) -> void:
	_inventory(state)
	var companion := func(uuid: String, name: String, class_id: int, points: int) -> Dictionary:
		return {"companionUuid": uuid, "companionName": name, "characterClass": class_id,
			"stats": {"hp": 640, "mp": 200, "def": 25, "str": 61, "spd": 50, "dex": 44, "vit": 70, "wis": 30,
				"availableSkillPoints": points, "abilitySkillPoints": {}},
			"items": [{"slotIdx": 0, "itemId": 49}, {"slotIdx": 1, "itemId": 3010}]}
	var roster := [companion.call("c1", "Brutus", 2, 3), companion.call("c2", "Sage", 1, 0)]
	state.apply_packet("CompanionRosterPacket", {"json": JSON.stringify(roster), "ownedCap": 2,
		"deployedUuid": "c1", "summonReadyAtMs": 0, "deployedUntilMs": 0})


## Who else is in view: Mingau, an admin and a demo account, the latter
## two just arrived, with the menu open on Mingau.
static func _nearby(state: RealmState) -> void:
	_entities(state)
	var admin := _player(7, "Sable", Vector2(-120, 60), 5)
	admin["chatRole"] = "admin"
	var demo := _player(8, "Guest", Vector2(140, 20), 9)
	demo["chatRole"] = "demo"
	state.apply_packet("LoadPacket", {"players": [admin, demo]})
	state.apply_packet("UpdatePacket", {"playerId": 2, "playerName": "Mingau",
		"stats": {"hp": 320, "mp": 140}, "health": 250, "mana": 90, "experience": 1400,
		"inventory": [], "hpPotions": 0, "mpPotions": 0, "dyeId": 0})


## The bag with a forged Goblin Sword in hand -- an epic with a rolled
## affix, two crystals and a crit gem -- so the card shows every section.
static func _item_card(state: RealmState) -> void:
	_inventory(state)
	var carried: Array = state.local.inventory.slots.duplicate(true)
	carried[0] = _item(49, {"rarity": 4, "tier": 3, "targetSlot": 0,
		"damage": {"projectileGroupId": 75, "min": 46, "max": 87},
		"attributeModifiers": [{"statId": 7, "deltaValue": 2}],
		"enchantments": [{"statId": 4, "deltaValue": 1}, {"statId": 7, "deltaValue": 1}], "gemstoneType": 2})
	for i in carried.size():
		if carried[i].is_empty():
			carried[i] = {"itemId": -1}
	state.apply_packet("UpdatePacket", {"playerId": state.local.id, "playerName": "Ruu",
		"stats": {"hp": 300, "mp": 100, "str": 40, "dex": 30}, "health": 300, "mana": 100, "experience": 0,
		"inventory": carried, "hpPotions": 3, "mpPotions": 1, "dyeId": 0})


## What each bag on the ground holds, under it: one at our feet, one across
## the floor with two rows of gear (ten, the cap), and one with a placeholder
## among its items that must not take a cell -- the web shows every bag on
## screen, not only the one underfoot.
static func _loot_preview(state: RealmState) -> void:
	_entities(state)
	state.apply_packet("LoadPacket", {"containers": [
		{"lootContainerId": 9, "tier": 1, "isChest": false,
			"items": [_item(51), _item(846), {"itemId": -1}], "pos": {"x": -16.0, "y": 0.0}},
		{"lootContainerId": 10, "tier": 3, "isChest": false, "pos": {"x": 128.0, "y": 96.0},
			"items": [_item(49), _item(3010), _item(839), _item(845), _item(8), _item(50),
				_item(0), _item(800), _item(3012), _item(51), _item(846)]},
		{"lootContainerId": 11, "tier": 0, "isChest": false, "pos": {"x": 0.0, "y": -112.0},
			"items": [{"itemId": -1}, _item(8), _item(839), _item(845), _item(3012), _item(50)]}]})


## The vault: an empty chest at our feet, its slots open beside the bag, and
## two more across the floor, one holding a few things in their own slots.
static func _vault(state: RealmState) -> void:
	_inventory(state)
	state.apply_packet("UnloadPacket", {"containers": [5, 9]})
	var empty := []
	for i in Inventory.LOOT_SIZE:
		empty.append({"itemId": -1})
	var some := empty.duplicate()
	some[0] = _item(51)
	some[2] = _item(846)
	some[7] = _item(3010)
	state.apply_packet("LoadPacket", {"containers": [
		{"lootContainerId": 20, "tier": -1, "isChest": true, "items": empty,
			"pos": {"x": state.local.position.x, "y": state.local.position.y}},
		{"lootContainerId": 21, "tier": -1, "isChest": true, "items": empty, "pos": {"x": 96.0, "y": 0.0}},
		{"lootContainerId": 22, "tier": -1, "isChest": true, "items": some, "pos": {"x": 96.0, "y": 96.0}}]})


static func _item(item_id: int, extra := {}) -> Dictionary:
	var item := {"itemId": item_id}
	item.merge(extra)
	return item


static func _map(tiles: Array) -> Dictionary:
	return {"realmId": 1, "mapId": 1, "mapWidth": 64, "mapHeight": 64, "tiles": tiles}


static func _player(id: int, name: String, position: Vector2, class_id: int) -> Dictionary:
	return {"id": id, "name": name, "accountUuid": "", "characterUuid": "",
		"classId": class_id, "size": 28, "pos": {"x": position.x, "y": position.y},
		"dX": 0.0, "dY": 0.0, "shortId": id, "chatRole": "", "dyeId": 0}


static func _enemy(id: int, enemy_id: int, position: Vector2, health: int, maximum: int) -> Dictionary:
	return {"id": id, "enemyId": enemy_id, "weaponId": 0, "size": 32,
		"pos": {"x": position.x, "y": position.y}, "dX": 0.0, "dY": 0.0,
		"difficulty": 1.0, "health": health, "maxHealth": maximum, "shortId": id}


## Characters either side of a tall wall, so the 2.5D depth is visible.
##
## Wall art is 8x16: the top face must cover the character standing behind it,
## while the one in front -- overlapping only the south-spilling front face --
## must still draw over the wall. Get the occlusion pass wrong in either
## direction and exactly one of these two reads incorrectly.
## A plus of tall vine walls copied cell for cell from a live map (JosephTest
## around 257, 238): the top wall's front face spills into the empty cell at
## the origin, between the two walls beside it.
static func _wall_plus(state: RealmState) -> void:
	var ground: Array = [[3, 24, 14, 14, 5, 5, 5, 5, 5, 5, 5], [3, 24, 5, 14, 5, 5, 5, 5, 5, 5, 5], [24, 24, 14, 5, 24, 5, 5, 5, 5, 5, 5], [3, 5, 14, 24, 24, 24, 24, 5, 5, 5, 5], [5, 14, 14, 24, 24, 24, 24, 5, 5, 5, 5], [5, 14, 24, 24, 24, 24, 24, 24, 5, 5, 5], [5, 14, 24, 24, 24, 24, 24, 5, 5, 5, 5], [5, 14, 24, 24, 24, 24, 24, 5, 5, 5, 5], [5, 14, 5, 5, 24, 4, 5, 5, 5, 5, 5], [5, 14, 5, 5, 4, 4, 4, 5, 5, 5, 5]]
	var walls: Array = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 423, 0, 0, 414, 0, 0, 0, 0, 0], [0, 0, 0, 0, 414, 0, 414, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 414, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 414, 0, 0, 0, 0]]
	var tiles: Array = []
	for row in ground.size():
		for col in ground[row].size():
			tiles.append({"tileId": ground[row][col], "layer": 0, "xIndex": row + 234, "yIndex": col + 252})
			if walls[row][col] > 0:
				tiles.append({"tileId": walls[row][col], "layer": 1, "xIndex": row + 234, "yIndex": col + 252})
	state.apply_packet("LoadMapPacket", {"realmId": 1, "mapId": 38, "mapWidth": 600, "mapHeight": 600, "tiles": tiles})
	var at := Vector2(254 * 32, 238 * 32 + 16)
	state.local.id = 1
	state.local.name = "ruusey"
	state.local.position = at
	state.apply_packet("LoadPacket", {"players": [_player(1, "ruusey", at, 0)], "enemies": [], "containers": [], "portals": []})


static func _wall_depth(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-4, 5):
		for y in range(-3, 4):
			tiles.append({"tileId": FLOOR_TILE, "layer": 0, "xIndex": y, "yIndex": x})
	for x in range(-4, 5):
		tiles.append({"tileId": WALL_TILE, "layer": 1, "xIndex": 0, "yIndex": x})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.apply_packet("LoadPacket", {"players": [
		_player(1, "Behind", Vector2(-48.0, -18.0), 0),
		_player(2, "InFront", Vector2(32.0, 24.0), 0),
	]})


## Ground shadows: two characters close enough that one's ellipse reaches
## under the other, and a pair of props -- one on dry ground, one in water.
##
## The prop in the water is the assertion that matters. It must have no shadow
## at all, or it reads as a hole in the surface; its twin on dry ground a few
## cells away has one, so a pass that stopped drawing them entirely cannot
## pass this by accident.
static func _shadows(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-4, 5):
		for y in range(-3, 4):
			var wet := x >= 2
			tiles.append({"tileId": SHALLOW_WATER_TILE if wet else FLOOR_TILE,
				"layer": 0, "xIndex": y, "yIndex": x})
	tiles.append({"tileId": PROP_TILE, "layer": 1, "xIndex": 1, "yIndex": -3})
	tiles.append({"tileId": PROP_TILE, "layer": 1, "xIndex": 1, "yIndex": 3})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.apply_packet("LoadPacket", {"players": [
		_player(1, "Far", Vector2(-8.0, -12.0), 0),
		_player(2, "Near", Vector2(6.0, 10.0), 0),
	]})


## A character mid-swing, aimed where the argument points.
##
## Three of these, because the failure modes are all different. Upward catches
## the axis test picking the wrong one of the three clips, and is the only one
## that catches a walk token being used for the clip name -- content calls
## them attack_up/down while the walk cycle says back/front, and "side" is
## spelled the same in both, so a swapped token resolves silently to idle.
##
## Left and right catch the frame rect. The second frame of attack_side is
## double-width -- the weapon overhangs the body cell -- and the two facings
## anchor it differently: unmirrored it extends right from the cell's left
## edge, mirrored it extends left from the cell's right edge. Drawing either
## into a plain square squashes the character to half width.
static func _attacking(state: RealmState, aim: Vector2) -> void:
	var tiles: Array = []
	for x in range(-4, 5):
		for y in range(-3, 4):
			tiles.append({"tileId": FLOOR_TILE, "layer": 0, "xIndex": y, "yIndex": x})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [
		_player(1, "Swing", Vector2(-16.0, -16.0), 0),
	]})
	state.local.attack.begin(aim)
	# Far enough in to be past the first frame, well short of the window.
	state.local.attack.tick(AttackPose.FRAME_SECONDS * 1.5)


## Spinning projectiles, both modes, fired along the same eight headings.
##
## The upper ring is an additive group and the lower a continuous one, which
## is the whole point: additive turns on top of each bullet's heading, so the
## ring stays fanned out, while continuous replaces the heading and every
## bullet in the ring points the same way. Swap the two and the lower ring
## fans out -- which no single-mode scenario would catch.
static func _spin(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, -16), 0)]})
	_spin_ring(state, 200, ADDITIVE_SPIN_GROUP, -64.0)
	_spin_ring(state, 300, CONTINUOUS_SPIN_GROUP, 48.0)


static func _spin_ring(state: RealmState, first_id: int, group: int, y: float) -> void:
	for step in 8:
		var angle := float(step) * TAU / 8.0
		state.projectiles.bullets[first_id + step] = Projectile.from_wire({
			"id": first_id + step, "projectileId": group, "size": 16,
			"pos": {"x": 28.0 * float(step) - 96.0, "y": y},
			"angle": angle, "magnitude": 0.0, "range": 500.0, "flags": [],
			"invert": false, "timeStep": 0, "amplitude": 0, "frequency": 0,
			"orbitCenterX": 0.0, "orbitCenterY": 0.0, "orbitRadius": 0.0,
			"orbitPhase": 0.0, "damage": 1, "createdTime": 0}, 0)


## The Skills window over a player: nothing earned, partway, and the cap.
static func _masteries(state: RealmState) -> void:
	_entities(state)
	var xp := [0, 1275, 2040, 18000, 250000, 7, 4998510, 900, 1200000]
	var data := {"playerId": state.local.id}
	for index in xp.size():
		data["xp%d" % index] = xp[index]
	state.apply_packet("SkillsPacket", data)


## The player blinded among the entities scene, with one enemy and one enemy
## shot past the tunnel -- both gone -- and a shot inside it that stays.
static func _blind(state: RealmState) -> void:
	_entities(state)
	state.apply_packet("LoadPacket", {"enemies": [_enemy(7, 1, Vector2(200, 0), 100, 100)]})
	state.local.effects = [Blind.EFFECT]
	var id := 300
	for at in [Vector2(40, -60), Vector2(-220, 60)]:
		state.projectiles.bullets[id] = Projectile.from_wire({
			"id": id, "projectileId": 87, "size": 16, "pos": {"x": at.x, "y": at.y},
			"angle": 0.0, "magnitude": 0.0, "range": 500.0, "flags": [],
			"invert": false, "timeStep": 0, "amplitude": 0, "frequency": 0,
			"orbitCenterX": 0.0, "orbitCenterY": 0.0, "orbitRadius": 0.0,
			"orbitPhase": 0.0, "damage": 1, "createdTime": 0, "srcEntityId": 3}, 0)
		id += 1


## Every shipped dye on two classes with masks: Barbarians undyed then Green,
## Yellow, Red and Blue along the top, Wizards Purple, Orange, White and Black
## along the bottom, and ourselves in Red between them -- the local player
## reads its dye off its own roster entry.
static func _dyes(state: RealmState) -> void:
	_terrain(state)
	state.local.id = 1
	state.local.name = "Ruu"
	state.local.class_id = 0
	state.local.position = Vector2(-16, 0)
	var me := _player(1, "Ruu", Vector2(-16, 0), 0)
	me["dyeId"] = 3
	var players := [me]
	for i in 5:
		var top := _player(10 + i, "Dye %d" % i, Vector2(-144 + 64 * i, -96), 0)
		top["dyeId"] = i
		players.append(top)
	for i in 4:
		var bottom := _player(20 + i, "Dye %d" % (5 + i), Vector2(-112 + 64 * i, 88), 2)
		bottom["dyeId"] = 5 + i
		players.append(bottom)
	state.apply_packet("LoadPacket", {"players": players})


## The quest log open over the entities scene: one quest of each status --
## the active one mid-way, the available one with Accept, the completed one
## dimmed -- with rewards of several kinds, and Mingau's stars under his name.
static func _quests(state: RealmState) -> void:
	_entities(state)
	state.apply_packet("UpdatePacket", {"playerId": 2, "stars": 7, "stats": {}})
	var quests := [
		{"id": 1, "name": "First Blood", "cat": "COMBAT", "status": "COMPLETE", "auto": true, "stars": 1,
			"desc": "Every hero starts somewhere. Cut down 25 enemies anywhere in the realm.",
			"objectives": [{"label": "Slay 25 enemies", "progress": 25, "target": 25}],
			"rewards": [{"type": "FAME", "amount": 100}]},
		{"id": 2, "name": "Monster Hunter", "cat": "COMBAT", "status": "ACTIVE", "auto": true, "stars": 2,
			"desc": "The realm is thick with them. Put down five hundred.",
			"objectives": [{"label": "Slay 500 enemies", "progress": 137, "target": 500}],
			"rewards": [{"type": "FAME", "amount": 1500}, {"type": "SKILL_XP", "amount": 2500, "skillId": 1}]},
		{"id": 6, "name": "Slayer of Drakes", "cat": "BOSSES", "status": "AVAILABLE", "auto": false,
			"stars": 3, "scoped": true, "desc": "Bring down the Fire Drake in its lair.",
			"objectives": [{"label": "Defeat the Fire Drake", "progress": 0, "target": 1}],
			"rewards": [{"type": "UNLOCK_VAULT_CHEST", "amount": 1}, {"type": "STAT_POINT", "amount": 2, "stat": "VIT"}]},
	]
	state.apply_packet("QuestStatePacket", {"playerId": state.local.id, "stars": 6,
		"json": JSON.stringify({"stars": 6, "quests": quests})})


## Props and decorations on the collision layer, packed the ways that lose
## an outline: trees stacked in a column over a tall wall, rocks in a row
## over a pool of deep water (solid, not a wall: a billboard too), a block of
## bushes, a flower beside them, and a stone standing in shallow water. The
## wall's top face and the pool's bodies are drawn after the tree and the
## rocks above them, over their lower fringe; the bottom pass puts it back.
static func _billboards(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-4, 5):
		for y in range(-3, 4):
			tiles.append({"tileId": SHALLOW_WATER_TILE if x >= 3 else FLOOR_TILE,
				"layer": 0, "xIndex": y, "yIndex": x})
	var props := [[340, -3, -2], [340, -3, -1], [341, -3, 0], [140, -1, 1], [140, 0, 1], [140, 1, 1],
		[178, 1, -2], [178, 2, -2], [178, 1, -1], [178, 2, -1], [344, -1, -2], [PROP_TILE, 3, 2],
		[WALL_TILE, -4, 1], [WALL_TILE, -3, 1], [DEEP_WATER_TILE, -1, 2], [DEEP_WATER_TILE, 0, 2],
		[DEEP_WATER_TILE, -1, 3], [DEEP_WATER_TILE, 0, 3]]
	for prop in props:
		tiles.append({"tileId": prop[0], "layer": 1, "xIndex": prop[2], "yIndex": prop[1]})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-40.0, -24.0), 0)]})


## The ground where four chunks meet (GroundChunk: cells -1 and 0 on both
## axes): runs of tall walls crossing the border north to south, whose
## front faces each spill onto the wall below; a row of them west to east;
## square walls and their bands, props and their rings, bottoms and
## shadows, and grass, sand and water seams, all straddling it. Its
## reference was made by the renderer that drew the whole view at once.
static func _chunk_seams(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-8, 8):
		for y in range(-6, 6):
			var ground: int = GRASS_TILE if x < 0 and y < 0 else SHALLOW_WATER_TILE if x >= 4 else FLOOR_TILE
			tiles.append({"tileId": ground, "layer": 0, "xIndex": y, "yIndex": x})
	var walls := []
	for y in range(-4, 3):
		walls.append([WALL_TILE, -3, y])
	for y in range(-3, 2):
		walls.append([WALL_TILE, 1, y])
	for x in range(-7, -3):
		walls.append([WALL_TILE, x, -1])
	for y in range(-3, 3):
		walls.append([SQUARE_WALL_TILE, 3, y])
	for prop in walls + [[PROP_TILE, -1, -1], [PROP_TILE, 0, 0], [PROP_TILE, -1, 0], [PROP_TILE, 0, -1],
			[PROP_TILE, 5, -1], [PROP_TILE, 5, 0]]:
		tiles.append({"tileId": prop[0], "layer": 1, "xIndex": prop[2], "yIndex": prop[1]})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.local.id = 1
	state.local.position = Vector2(-16, 64)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, 64), 0)]})


## Liquid against land: a ragged pond of shallow water around deep water in
## grass and sand, and a lava pool in rock with a rock island and a one-cell
## inlet, so straight shores, inner and outer corners and lone cells all show.
static func _shores(state: RealmState) -> void:
	var tiles: Array = []
	for x in range(-16, 17):
		for y in range(-12, 13):
			var tile_id := GRASS_TILE if x < 0 else ROCK_TILE
			if x < 0 and y > 3:
				tile_id = FLOOR_TILE
			var pond := Vector2(x + 7, y)
			var reach := 4.6 + 0.9 * sin(3.0 * pond.angle()) + 0.5 * cos(5.0 * pond.angle())
			if pond.length() < reach:
				tile_id = DEEP_WATER_TILE if pond.length() < reach - 2.0 else SHALLOW_WATER_TILE
			var pool := Vector2(x - 7, y)
			if pool.length() < 3.8 + 0.7 * sin(2.0 * pool.angle() + 1.0):
				tile_id = LAVA_TILE
			tiles.append({"tileId": tile_id, "layer": 0, "xIndex": y, "yIndex": x})
	for cell in [Vector2i(-3, -6), Vector2i(11, 4)]:
		tiles.append({"tileId": LAVA_TILE if cell.x > 0 else SHALLOW_WATER_TILE,
			"layer": 0, "xIndex": cell.y, "yIndex": cell.x})
	tiles.append({"tileId": ROCK_TILE, "layer": 0, "xIndex": 0, "yIndex": 7})
	state.apply_packet("LoadMapPacket", _map(tiles))
	state.local.id = 1
	state.local.position = Vector2(-16, -16)
	state.apply_packet("LoadPacket", {"players": [_player(1, "Ruu", Vector2(-16, 200), 0)]})


## The server's top five as the Menu's Leaderboard lists them, fame and

## The server's top five, fame and pre-fame both, one in a dye, and a gap in
## the gear for the card's "Empty".
static func leaderboard_entries() -> Array:
	var gear := [{"itemId": 3507, "slotIdx": 0}, {"itemId": 3512, "slotIdx": 1},
		{"itemId": 844, "slotIdx": 2}, {"itemId": 850, "slotIdx": 3}]
	var rows := [["Ruu", 2, "Wizard", 20, 48210], ["Mingau", 9, "Knight", 20, 12500],
		["Tarrasque", 0, "Barbarian", 20, 1320], ["Solstice", 8, "Priest", 17, 0], ["Hollow", 5, "Necromancer", 6, 0]]
	var out: Array = []
	for row in rows:
		out.append({"accountName": row[0], "characterClass": row[1], "className": row[2], "level": row[3],
			"fame": row[4], "equipment": gear if out.is_empty() else [],
			"stats": {"hp": 670, "mp": 385, "str": 50, "def": 25, "spd": 50, "dex": 55, "vit": 40, "wis": 60,
				"dyeId": 3 if row[0] == "Mingau" else 0}})
	return out
