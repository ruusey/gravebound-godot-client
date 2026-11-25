class_name Interaction
extends RefCounted

## Trades, party invites and PvP challenges: one player asks, the other answers.
##
## The server tells each player what happened on InteractionPacket -- a kind, an
## event, the other player's name and, for a refusal, the reason -- and takes
## requests and answers on InteractionActionPacket. The ordinals mirror the
## server's InteractionKind, InteractionAction and InteractionEvent. The wording
## lives here, so none of it passes through the chat.

enum Kind { TRADE, PARTY, PVP }
enum Action { REQUEST, ACCEPT, DECLINE, LEAVE, KICK }
enum Event { REQUESTED, SENT, ACCEPTED, DECLINED, CANCELLED, COMPLETED, FAILED, CLOSED, STARTED, WON, LOST,
	LEFT, DISBANDED, KICKED, REMOVED }

## Each kind's prompt; %s is the player asking.
const PROMPTS := {
	Kind.TRADE: "%s wants to trade",
	Kind.PARTY: "%s wants you in their party",
	Kind.PVP: "%s challenges you to a PvP battle!",
}

## What each event reads as, by kind; %s is the other player. FAILED reads as
## the server's reason, and an event missing here shows nothing.
const NOTICES := {
	Kind.TRADE: {
		Event.SENT: "Trade request sent to %s.",
		Event.ACCEPTED: "%s accepted your trade.",
		Event.DECLINED: "%s declined your trade.",
		Event.CANCELLED: "%s cancelled the trade.",
		Event.COMPLETED: "Trade with %s complete.",
	},
	Kind.PARTY: {
		Event.SENT: "Party invite sent to %s.",
		Event.ACCEPTED: "%s joined your party.",
		Event.DECLINED: "%s declined your party invite.",
		Event.LEFT: "%s left the party.",
		Event.DISBANDED: "Your party has disbanded.",
		Event.KICKED: "%s removed you from the party.",
		Event.REMOVED: "%s was removed from the party.",
	},
	Kind.PVP: {
		Event.SENT: "PvP challenge sent to %s.",
		Event.DECLINED: "%s declined your PvP challenge.",
		Event.STARTED: "PvP match against %s! Damage is scaled to 1/10; first minion wave in 10s.",
		Event.WON: "You won the PvP match against %s!",
		Event.LOST: "%s won the PvP match.",
	},
}


## What an event says, or "" for one that shows nothing.
static func notice(kind: int, event: int, other_name: String, detail: String) -> String:
	if event == Event.FAILED:
		return detail
	var by_event: Dictionary = NOTICES.get(kind, {})
	var line := String(by_event.get(event, ""))
	return line % other_name if line.contains("%s") else line
