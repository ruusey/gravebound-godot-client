class_name LootArt
extends RefCounted

## What a loot container on the ground looks like: the web client's
## renderLootContainer.
##
## loot-containers.json, keyed by the container's tier, names each bag's
## sprite and whether it fills its tile or sits in the middle at half a
## tile -- a chest (tier -1) and a grave fill it, a bag does not. A tier the
## table lacks falls back as the web falls back: a chest to the third cell
## of the projectiles sheet, a bag to row 9 of the misc sheet, one column a
## tier. Only the tier and the chest flag travel on the wire.

const CHEST_TIER := -1
## The untiered bag (server LootTier.BLACK, value 4): rendered black, and the
## client gives it a soft white glow so an untiered drop stands out.
const BLACK_TIER := 4
const CHEST_FALLBACK := {"spriteKey": "realm-projectiles.png", "col": 2, "row": 0, "fullSize": true}
const BAG_SHEET := "realm-misc.png"
const BAG_ROW := 9
const BAG_COLUMNS := 5


static func definition(library: ContentLibrary, tier: int, is_chest: bool) -> Dictionary:
	var found: Dictionary = library.loot_containers.get(tier, {})
	if not found.is_empty():
		return found
	if is_chest or tier == CHEST_TIER:
		return CHEST_FALLBACK
	return {"spriteKey": BAG_SHEET, "row": BAG_ROW, "col": tier if tier >= 0 and tier < BAG_COLUMNS else 0,
		"fullSize": false}


## A vault chest, as the registry holds a container.
static func is_chest(container: Dictionary) -> bool:
	return bool(container.get("is_chest", false)) or int(container.get("tier", 0)) == CHEST_TIER


static func texture(content: GameData, tier: int, is_chest: bool) -> AtlasTexture:
	return content.sprites.atlas_for(definition(content.library, tier, is_chest))


## The rect it is drawn in: the whole tile, or half of it in the middle.
static func rect(content: GameData, position: Vector2, tier: int, is_chest: bool) -> Rect2:
	var tile := float(GameConstants.TILE_SIZE)
	if bool(definition(content.library, tier, is_chest).get("fullSize", false)):
		return Rect2(position, Vector2.ONE * tile)
	return Rect2(position + Vector2.ONE * tile / 4.0, Vector2.ONE * tile / 2.0)
