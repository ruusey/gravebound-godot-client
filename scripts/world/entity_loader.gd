class_name EntityLoader
extends RefCounted

## Maps a LoadPacket's wire entities onto the registry.
##
## Split out from EntityRegistry so that the registry stays about storage and
## lookup: this is the only place that knows NetPlayer/NetEnemy/NetPortal
## field names, which is also the part that changes when the protocol does.

const BROWN_BAG_TIER := 0
const WHITE_BAG_TIER := 4
const GRAVE_TIER := 5


## Returns how many rare drops (untiered gear) came into sight for the first time
## this map, so the caller can chime once per new one.
static func apply(registry: EntityRegistry, data: Dictionary, now: float) -> int:
	var rare_spotted := 0
	for wire in data.get("players", []):
		var player := registry.upsert(registry.players, int(wire.get("id", 0)), GameConstants.ENTITY_PLAYER)
		player["name"] = wire.get("name", "")
		player["class_id"] = int(wire.get("classId", 0))
		player["size"] = int(wire.get("size", GameConstants.PLAYER_SIZE))
		player["dye_id"] = int(wire.get("dyeId", 0))
		player["chat_role"] = wire.get("chatRole", "")
		registry.register_short_id(wire.get("shortId", 0), player["id"])
		registry.snapshot_from_wire(player, wire, now)

	for wire in data.get("enemies", []):
		var enemy := registry.upsert(registry.enemies, int(wire.get("id", 0)), GameConstants.ENTITY_ENEMY)
		enemy["enemy_id"] = int(wire.get("enemyId", 0))
		enemy["size"] = int(wire.get("size", 16))
		enemy["health"] = int(wire.get("health", 0))
		enemy["max_health"] = int(wire.get("maxHealth", 1))
		registry.register_short_id(wire.get("shortId", 0), enemy["id"])
		registry.snapshot_from_wire(enemy, wire, now)

	for wire in data.get("containers", []):
		var container := registry.upsert(registry.containers, int(wire.get("lootContainerId", 0)), -1)
		container["tier"] = int(wire.get("tier", 0))
		container["is_chest"] = bool(wire.get("isChest", false))
		container["item_count"] = (wire.get("items", []) as Array).size()
		# Kept whole: the loot strip reads the bag at our feet straight off this.
		container["items"] = wire.get("items", [])
		# Who fell here, on a grave; empty on any other bag.
		container["grave"] = GraveCard.record(wire.get("grave", []))
		registry.snapshot_from_wire(container, wire, now)
		if not registry.rare_loot_seen.has(container["id"]) and is_rare_drop(wire):
			registry.rare_loot_seen[container["id"]] = true
			rare_spotted += 1

	# portalId resolves the art out of portals.json -- it is the whole of what a
	# portal looks like -- while the target fields summarise the realm on the
	# far side and are what gets drawn under it.
	for wire in data.get("portals", []):
		var portal := registry.upsert(registry.portals, int(wire.get("id", 0)), -1)
		portal["portal_id"] = int(wire.get("portalId", 0))
		portal["to_realm_id"] = int(wire.get("toRealmId", 0))
		portal["label"] = wire.get("targetLabel", "")
		portal["difficulty"] = float(wire.get("targetDifficulty", 0.0))
		portal["tier"] = int(wire.get("targetTier", 0))
		portal["player_count"] = int(wire.get("targetPlayerCount", 0))
		portal["purified"] = int(wire.get("targetPurificationProgress", 0))
		portal["goal"] = int(wire.get("targetPurificationGoal", 0))
		portal["modifiers"] = String(wire.get("targetModifiers", ""))
		registry.snapshot_from_wire(portal, wire, now)
	return rare_spotted


## A dropped bag that is white, or holds untiered gear (a boosted bag can).
## Chests, graves and player-dropped brown bags hold old loot, not a new drop.
static func is_rare_drop(wire: Dictionary) -> bool:
	if bool(wire.get("isChest", false)):
		return false
	var tier := int(wire.get("tier", 0))
	if tier == BROWN_BAG_TIER or tier == GRAVE_TIER or tier < 0:
		return false
	if tier == WHITE_BAG_TIER:
		return true
	for item in wire.get("items", []):
		if item is Dictionary and int(item.get("tier", 0)) == -1 and not bool(item.get("consumable", false)) \
				and Inventory.is_equipment(int(item.get("targetSlot", -1))):
			return true
	return false
