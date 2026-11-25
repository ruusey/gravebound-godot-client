class_name InteractionState
extends RefCounted

## The requests waiting on this player's answer, one per kind, and the recent
## notices about their trades, party and PvP matches (InteractionPacket).
##
## A REQUESTED event opens the prompt for the server's durationMs; CLOSED, a PvP
## STARTED, answering it or the time running out takes it down. Every other event
## that reads as something (Interaction.notice) joins the notices, which stand
## NOTICE_MS each, at most MAX_NOTICES at once.

const NOTICE_MS := 5_000
const MAX_NOTICES := 3

## [{"text", "failed", "at"}], oldest first.
var notices: Array = []
## Bumped on every change, so a view can redraw only then.
var version := 0

## Kind -> {"from": the asking player, "until": clock ms}.
var _requests := {}
var _clock: Callable


func _init(clock: Callable = func() -> int: return Time.get_ticks_msec()) -> void:
	_clock = clock


## Drops the standing requests (the notices fade on their own).
func clear() -> void:
	_requests.clear()
	version += 1


func apply(data: Dictionary) -> void:
	var kind := int(data.get("kind", -1))
	var event := int(data.get("event", -1))
	var other := String(data.get("otherName", ""))
	if event == Interaction.Event.REQUESTED:
		_requests[kind] = {"from": other, "until": int(_clock.call()) + int(data.get("durationMs", 0))}
	elif event == Interaction.Event.CLOSED or event == Interaction.Event.STARTED:
		_requests.erase(kind)
	var text := Interaction.notice(kind, event, other, String(data.get("detail", "")))
	if text != "":
		notices.append({"text": text, "failed": event == Interaction.Event.FAILED, "at": _clock.call()})
		if notices.size() > MAX_NOTICES:
			notices.pop_front()
	version += 1


## Who is asking for this kind, or "".
func request_from(kind: int) -> String:
	var request: Dictionary = _requests.get(kind, {})
	return String(request.get("from", ""))


## Takes the prompt down once answered, without waiting on the server.
func answered(kind: int) -> void:
	if _requests.erase(kind):
		version += 1


func expire() -> void:
	var now: int = _clock.call()
	for kind in _requests.keys():
		if now >= int(_requests[kind]["until"]):
			_requests.erase(kind)
			version += 1
	while not notices.is_empty() and now - int(notices[0]["at"]) >= NOTICE_MS:
		notices.pop_front()
		version += 1
