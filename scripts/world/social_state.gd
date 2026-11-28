class_name SocialState
extends RefCounted

## The friends and guild directory (SocialStatusPacket): every friend and guild
## member, online or not, and for the online ones where they are and what they
## wear. Account-wide, so it is kept across realms like the guild.
##
## Only players on the same server count as online.

const FRIEND := 1
const GUILD := 2
const ONLINE := 4
const SAME_REALM := 8

enum Filter { ALL, ONLINE, OFFLINE }

## Bumped on every change, so a view can redraw only then.
var version := 0
var max_friends := 0
## [{"name", "friend", "guild", "online", "same_realm", "rank", "class_id", "level",
## "dye_id", "location", "equipment"}], online first, then by name.
var entries: Array = []

var _by_name := {}


func apply(data: Dictionary) -> void:
	entries = []
	_by_name = {}
	max_friends = int(data.get("maxFriends", 0))
	for row in data.get("entries", []):
		var flags := int(row.get("flags", 0))
		var entry := {
			"name": String(row.get("name", "?")),
			"friend": flags & FRIEND != 0,
			"guild": flags & GUILD != 0,
			"online": flags & ONLINE != 0,
			"same_realm": flags & SAME_REALM != 0,
			"rank": int(row.get("guildRank", 0)),
			"class_id": int(row.get("classId", 0)),
			"level": int(row.get("level", 0)),
			"dye_id": int(row.get("dyeId", 0)),
			"location": String(row.get("location", "")),
			"equipment": (row.get("equipment", []) as Array).map(
				func(id) -> Dictionary: return {"itemId": int(id)}),
		}
		entries.append(entry)
		_by_name[entry["name"].to_lower()] = entry
	entries.sort_custom(before)
	version += 1


## Online before offline, then by name.
static func before(a: Dictionary, b: Dictionary) -> bool:
	if a["online"] != b["online"]:
		return a["online"]
	return String(a["name"]).nocasecmp_to(String(b["name"])) < 0


func is_friend(player_name: String) -> bool:
	return bool(_by_name.get(player_name.to_lower(), {}).get("friend", false))


func is_guildmate(player_name: String) -> bool:
	return bool(_by_name.get(player_name.to_lower(), {}).get("guild", false))


func friend_count() -> int:
	return entries.filter(func(e: Dictionary) -> bool: return e["friend"]).size()


## The friends (or guild members) that pass the filter and whose name holds `search`.
func listed(guild: bool, filter: int, search := "") -> Array:
	var needle := search.strip_edges().to_lower()
	return entries.filter(func(e: Dictionary) -> bool:
		return bool(e["guild"] if guild else e["friend"]) \
			and (filter == Filter.ALL or (filter == Filter.ONLINE) == bool(e["online"])) \
			and (needle == "" or String(e["name"]).to_lower().contains(needle)))


func online_count(guild: bool) -> int:
	return listed(guild, Filter.ONLINE).size()


## How the nearby list ranks a player: friends first, then guild members, then the rest.
func nearby_rank(player_name: String) -> int:
	if is_friend(player_name):
		return 0
	return 1 if is_guildmate(player_name) else 2


## The colour a player's name takes for being a friend or guild member, or `otherwise`.
func name_colour(player_name: String, otherwise: Color) -> Color:
	if is_friend(player_name):
		return NameColours.FRIEND
	return NameColours.GUILDMATE if is_guildmate(player_name) else otherwise
