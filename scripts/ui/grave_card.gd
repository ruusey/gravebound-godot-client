class_name GraveCard
extends RefCounted

## What a grave says: "Ruu lvl 17" under it, and for the one you are standing
## on, the card -- class, maxed stats, what killed them and how hard, and how
## long ago. The death screen tells the one who fell the same facts.
##
## The record is the server's NetGrave, which rides a grave bag and the death
## packet as a list of none or one.

## The stats a class can max, as the server counts them.
const STATS := 8
const COLOUR := Color("d9d2c3")


## The record off a wire list, or empty for a bag that is not a grave.
static func record(wire: Variant) -> Dictionary:
	if wire is Array and not (wire as Array).is_empty() and wire[0] is Dictionary:
		return wire[0]
	return {}


static func caption(grave: Dictionary) -> String:
	if grave.is_empty():
		return ""
	return "%s lvl %d" % [String(grave.get("name", "")), int(grave.get("level", 0))]


## The class and stats line, the killer and the final blow: what the card and
## the death screen both list.
static func facts(grave: Dictionary, content: GameData) -> Array:
	var lines: Array = []
	var cls := content.classes_art.display_name(int(grave.get("classId", 0))) if content != null else ""
	var maxed := "%d/%d maxed" % [int(grave.get("maxedStats", 0)), STATS]
	lines.append("%s  -  %s" % [cls, maxed] if cls != "" else maxed)
	var killer := String(grave.get("killedBy", ""))
	if killer != "":
		lines.append("Killed by %s" % killer)
	var blow := int(grave.get("killingBlow", 0))
	if blow > 0:
		lines.append("Final blow: %d damage" % blow)
	return lines


## The whole card, for a grave `now_ms` (wall clock) after it was dug.
static func card(grave: Dictionary, content: GameData, now_ms: int) -> String:
	if grave.is_empty():
		return ""
	var lines: Array = [caption(grave)]
	lines.append_array(facts(grave, content))
	var died_at := int(grave.get("diedAt", 0))
	if died_at > 0:
		lines.append("Died %s" % ago(now_ms - died_at))
	return "\n".join(lines)


## "just now", "5 min ago", "3 h ago", "2 d ago".
static func ago(elapsed_ms: int) -> String:
	var minutes := maxi(0, elapsed_ms) / 60_000
	if minutes < 1:
		return "just now"
	if minutes < 60:
		return "%d min ago" % minutes
	if minutes < 60 * 24:
		return "%d h ago" % (minutes / 60)
	return "%d d ago" % (minutes / (60 * 24))


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
