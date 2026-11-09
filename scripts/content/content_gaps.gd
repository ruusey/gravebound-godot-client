class_name ContentGaps
extends RefCounted

## Things the shipped content refers to that were never shipped with it.
##
## These are bugs in gravebound-data, not in the client, and the client cannot
## fix them -- it can only decide whether to shout about each one on every
## launch. Listing a sheet here says "known, already understood, not worth a
## warning banner". It is deliberately not silence: check-content.sh still
## prints them, so a gap cannot quietly become permanent, and anything *not*
## on this list still fails that check.
##
## Each entry carries why it is here, so removing it later is a decision
## someone can make without re-deriving the reason.

## sheet -> why it is here. Empty today: the one entry there was,
## lofi_char.png for enemy 263, went when gravebound-data repointed that enemy
## at lofiCharacter10x10.png (11320fe), and check-content.sh now fails on an
## entry like that one -- listed, but named by nothing -- so the list cannot
## outlive what it excuses. An entry reads:
##   "some_sheet.png": "enemy 123 (Name) placeholder; sheet never shipped",
const MISSING_SHEETS := {}

## The list in force; a test sets its own and puts this back.
static var sheets: Dictionary = MISSING_SHEETS.duplicate()


static func is_known(sprite_key: String) -> bool:
	return sheets.has(sprite_key)


static func reason(sprite_key: String) -> String:
	return sheets.get(sprite_key, "")


## Every entry that no longer excuses anything: nothing the content names
## asks for it, or the sheet now resolves. Each is a line saying which, and
## to remove it.
static func stale(named: Array, resolves: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	for key in sheets:
		if not key in named:
			out.append("%s is listed in ContentGaps but nothing names it any more -- remove it" % key)
		elif resolves.call(key):
			out.append("%s is listed in ContentGaps but now resolves -- remove it" % key)
	return out
