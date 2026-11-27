class_name ChatLog
extends RefCounted

## What the server and the other players have said.
##
## One flat ring, oldest dropped first, capped at 150 lines of scrollback. The
## cap is not cosmetic: the web client's own comment records what an uncapped
## log cost it, 1500-3000 retained lines after half an hour and 2-5 ms of layout
## per frame, which lands as ack jitter and then as reconciliation desync.
##
## The log survives a realm change, which is the web client's behaviour; the
## native wipes it per realm. It goes on disconnect, with the rest of the
## session.

const MAX_LINES := 150
## Not a flag on the wire: both references branch on the literal sender name.
const SYSTEM := "SYSTEM"
## Minimap payload wearing a chat packet's clothes -- `ADD|id|boss|x|y|name`,
## rebroadcast every three seconds while a realm event is live. The web client
## returns before its log ("never display in chat"); the native appends it and
## then only skips the bubble, which is why its chat fills with coordinates.
const EVENT_MARKER := "EVENT_MARKER"
## The `to` a received /tell arrives with; `from` is who sent it.
const WHISPER_IN := "WHISPER_IN"

var lines: Array = []
## Bumped on every stored line and on clear. `size` saturates at MAX_LINES once
## the ring is full, so a panel watching size alone would stop seeing new lines
## -- watch this instead.
var revision := 0
## Who last sent us a /tell, for the reply key; "" until someone has.
var last_whisper_from := ""

var _clock: Callable


func _init(clock: Callable = func() -> int: return Time.get_ticks_msec()) -> void:
	_clock = clock


func clear() -> void:
	lines.clear()
	last_whisper_from = ""
	revision += 1


## Stores whatever arrived, and does nothing else.
##
## Every field is read with a default and no lookup happens here. The web
## client wraps each of its side effects in its own try/catch and says why in
## a comment: a side effect must never be the thing that stops the line being
## shown, because that is the path that made chat look dead while the server
## was broadcasting fine.
func apply_text(data: Dictionary) -> void:
	if String(data.get("from", "")) == EVENT_MARKER:
		return
	lines.append({
		"from": String(data.get("from", "")),
		# Dual-purposed by the server: the recipient's name on a SYSTEM line,
		# and the SENDER'S CHAT ROLE on a player line, which is not a
		# recipient at all. Anyone building whispers on this field should read
		# ServerGameLogic's chat rebroadcast first.
		"to": String(data.get("to", "")),
		"message": String(data.get("message", "")),
		"at_ms": _clock.call(),
	})
	if String(data.get("to", "")) == WHISPER_IN:
		last_whisper_from = String(data.get("from", ""))
	while lines.size() > MAX_LINES:
		lines.pop_front()
	revision += 1


static func is_system(line: Dictionary) -> bool:
	return String(line.get("from", "")) == SYSTEM


## How a line reads: the server speaks plainly, a player is named.
static func rendered(line: Dictionary) -> String:
	var message := String(line.get("message", ""))
	if is_system(line):
		return message
	return "[%s]: %s" % [String(line.get("from", "")), message]


## The tail, oldest first, for a panel that shows only the last few.
func last(count: int) -> Array:
	if lines.is_empty():
		return []
	return lines.slice(maxi(lines.size() - count, 0))
