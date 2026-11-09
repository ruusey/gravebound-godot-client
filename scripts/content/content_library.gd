class_name ContentLibrary
extends RefCounted

## Loads the game-content JSON the server also reads.
##
## Only ids travel on the wire (tileId, enemyId, classId, projectileGroupId),
## so everything visual and every gameplay constant is resolved from here.
## Where it comes from is ContentSource's problem -- the data repo on disk, or
## the data service over HTTP, which is what a web build has to use.

## filename -> destination dictionary key, keyed by the id field in each entry.
## Shared crack overlay for breakable walls: one 8x16 cell per stage (75/50/25% HP).
const CRACK_SHEET := "gravebound-wall-cracks.png"
const SOURCES := {
	"tiles.json": ["tiles", "tileId"],
	"enemies.json": ["enemies", "enemyId"],
	"character-classes.json": ["classes", "classId"],
	"game-items.json": ["items", "itemId"],
	"weapon-archetypes.json": ["weapon_archetypes", "id"],
	"projectile-groups.json": ["projectile_groups", "projectileGroupId"],
	"portals.json": ["portals", "portalId"],
	"maps.json": ["maps", "mapId"],
	"abilities.json": ["abilities", "id"],
	"passives.json": ["passives", "id"],
	"loot-containers.json": ["loot_containers", "tierId"],
	"dye-assets.json": ["dyes", "dyeId"],
	"character-class-masks.json": ["class_masks", "classId"],
}

var tiles := {}
var enemies := {}
var classes := {}
var items := {}
var weapon_archetypes := {}
var projectile_groups := {}
var portals := {}
## Only the name is read off a map, for the nexus and vault guards.
var maps := {}
var abilities := {}
var passives := {}
## A dropped bag's art by its tier; LootArt reads it.
var loot_containers := {}
var animations := {}   # classId -> player animation set
## Dungeon definitions and prefab rooms, for the login backdrop's synthetic
## dungeon. Optional content: a data service that doesn't serve them leaves both
## empty, and the backdrop falls back to the torchlit hall.
var dungeons := {}         # dungeonId -> dungeon definition
var dungeon_rooms := {}     # roomId -> prefab room definition
## A dye by its id, and each class's painted masks of which pixels take one.
var dyes := {}
var class_masks := {}
## itemId -> fame cost; the one content file that is an object, not a list.
var fame_store := {}
## exp-levels.json as it comes: level -> "min-max". ExperienceLevels reads it.
var exp_levels := {}
## sounds.json as it comes: the event/archetype/ability-tag -> ogg map Sfx reads.
## Optional content -- an older data service that doesn't serve it leaves this empty.
var sounds := {}
var errors: Array[String] = []


func load_from(source: ContentSource) -> bool:
	errors.clear()
	var blocked := source.unavailable()
	if blocked != "":
		errors.append(blocked)
		return false

	for filename in SOURCES:
		var target: String = SOURCES[filename][0]
		var id_field: String = SOURCES[filename][1]
		var destination: Dictionary = get(target)
		for entry in await _read_array(source, filename):
			destination[int(entry.get(id_field, -1))] = entry

	var prices: Dictionary = await _read_object(source, "fame-store.json")
	for key in prices:
		fame_store[int(key)] = int(prices[key])
	exp_levels = await _read_object(source, "exp-levels.json")
	# Animations are keyed by objectId. Player class sets drive the character
	# sprites; enemy sets drive enemy walk/attack frames (EntityQueue). Class ids
	# (0-11) and enemy ids (200+) never collide, so both live in one table.
	for entry in await _read_array(source, "animations.json"):
		var object_type := String(entry.get("objectType", ""))
		if object_type == "player" or object_type == "enemy":
			animations[int(entry.get("objectId", -1))] = entry

	# Optional, like sounds.json: an absent dungeons/rooms file just disables the
	# login backdrop's synthetic dungeon, so it is read without the error a
	# required file would raise.
	for entry in await _read_optional_array(source, "dungeons.json"):
		dungeons[int(entry.get("dungeonId", -1))] = entry
	for entry in await _read_optional_array(source, "dungeon-rooms.json"):
		dungeon_rooms[int(entry.get("roomId", -1))] = entry

	# Optional: a missing sounds.json leaves the client silent, not broken, so it
	# is read without the _read_object error an absent required file would raise.
	var sound_result: Array = await source.read("sounds.json")
	if sound_result[0] == OK:
		var parsed = JSON.parse_string(PackedByteArray(sound_result[1]).get_string_from_utf8())
		if parsed is Dictionary:
			sounds = parsed

	return errors.is_empty()


## Every sprite sheet the loaded content refers to. SpriteCache reads them up
## front, because a sheet cannot be fetched from inside _draw.
func sheet_keys() -> Array:
	var keys := {}
	for table in [tiles, enemies, classes, items, projectile_groups, portals, animations, abilities,
			loot_containers]:
		for entry in table.values():
			var key: String = entry.get("spriteKey", "")
			if key != "":
				keys[key] = true
	keys[CRACK_SHEET] = true
	return keys.keys()


## Every ogg the sound map refers to -- what Sfx preloads, the way sheet_keys()
## lists the sprite sheets.
func sound_files() -> Array:
	var files := {}
	for group in ["attack", "abilityByTag", "abilityByName", "event"]:
		for value in sounds.get(group, {}).values():
			if value is String and value != "":
				files[value] = true
	var fallback: Variant = sounds.get("abilityDefault", "")
	if fallback is String and fallback != "":
		files[fallback] = true
	return files.keys()


func summary() -> String:
	return "%d tiles, %d enemies, %d classes, %d animation sets, %d items, %d projectile groups, %d portals, %d abilities" % [
		tiles.size(), enemies.size(), classes.size(), animations.size(),
		items.size(), projectile_groups.size(), portals.size(), abilities.size(),
	]


## A content file that is one JSON object rather than a list of entries.
func _read_object(source: ContentSource, filename: String) -> Dictionary:
	var result: Array = await source.read(filename)
	if result[0] != OK:
		errors.append("missing content file: %s" % filename)
		return {}
	var parsed = JSON.parse_string(PackedByteArray(result[1]).get_string_from_utf8())
	if not parsed is Dictionary:
		errors.append("%s did not contain a JSON object" % filename)
		return {}
	return parsed


## Like _read_array, but an absent or malformed file yields an empty list
## without recording an error -- for content the client can run without.
func _read_optional_array(source: ContentSource, filename: String) -> Array:
	var result: Array = await source.read(filename)
	if result[0] != OK:
		return []
	var parsed = JSON.parse_string(PackedByteArray(result[1]).get_string_from_utf8())
	return parsed if parsed is Array else []


func _read_array(source: ContentSource, filename: String) -> Array:
	var result: Array = await source.read(filename)
	if result[0] != OK:
		errors.append("missing content file: %s" % filename)
		return []
	var parsed = JSON.parse_string(PackedByteArray(result[1]).get_string_from_utf8())
	if not parsed is Array:
		errors.append("%s did not contain a JSON array" % filename)
		return []
	return parsed
