class_name StatusChips
extends RefCounted

## The coloured chips stacked over a character's head, one per status on it.
##
## Both references draw the same table -- the native client's comment says
## its labels MUST match the web client's -- so a teammate reads "Slow" or
## "Invuln" the same on every client. A chip is the effect's colour with a
## short label on it, black-bordered for busy ground; the first sits just
## over the head and the rest stack upward. A stacked effect (poison, bleed)
## carries its count. Drawn in table order, not the order the server sent.

## [effect id, label, colour]. The web client's STATUS_ICON_DEFS, with the
## server's StatusEffectType ids. `+` is a buff up, `-` a debuff down.
const DEFS := [
	[1, "Heal", Color("ff4444")], [4, "Spd+", Color("44ff44")], [19, "Aspd+", Color("ff6644")],
	[14, "Atk+", Color("ffaa44")], [18, "Armr+", Color("6688cc")], [6, "Invuln", Color("44aaff")],
	[0, "Hide", Color("ccbb88")], [21, "Slow", Color("6688ff")], [2, "Para", Color("888888")],
	[3, "Stun", Color("88ccff")], [15, "Stasis", Color("444448")], [11, "Daze", Color("9988aa")],
	[17, "Pois", Color("40cc40")], [16, "Curse", Color("aa2255")], [22, "Armr-", Color("7060cc")],
	[24, "Def+", Color("88aacc")], [23, "Taunt", Color("c8201f")], [25, "Vit+", Color("ffe070")],
	[26, "Dome", Color("6cccff")], [27, "Atk-", Color("8a5a30")], [28, "Blind", Color("1a1a1a")],
	[29, "Ward", Color("c8c0ff")], [30, "MP+", Color("4080ff")], [31, "Vuln", Color("cc4080")],
	[32, "Grnd", Color("806040")], [33, "Mark", Color("ffd840")], [34, "Atk+", Color("ffaa44")],
	[35, "Dex+", Color("ffd060")], [41, "DEATH", Color("ff0000")], [42, "Sac", Color("b03060")],
	[43, "Downed", Color("9999a0")], [36, "Bleed", Color("b01818")], [37, "Drink", Color("8a1030")],
	[38, "Wither", Color("7a6a8a")], [39, "Venom", Color("70d040")], [40, "Dodge", Color("d0e8ff")],
	[44, "Sick", Color("8aa83a")],
]

## The standout violet shared with the "X Immune" floating text (DamageText.IMMUNE_COLOUR).
const IMMUNE_COLOUR := Color(0.80, 0.30, 1.0)

## Persistent "immune" chips for the effects a boss cannot be hit with in its
## current phase: [label, colour] pairs, one per id, all in the standout violet.
## Label is the status' short name + " IMM" (ASCII only -- the game font has no
## shield glyph), e.g. "Stun IMM", so a stun-immune boss reads at a glance.
static func immune_chips(immune_effects: Array) -> Array:
	var out: Array = []
	for raw in immune_effects:
		var id := int(raw)
		if id < 0:
			continue
		var label := label_for(id)
		if label.is_empty():
			continue
		out.append([label + " IMM", IMMUNE_COLOUR])
	return out


## The chips an entity earns, in table order: [label, colour] pairs.
static func active(effects: Array, stacks: Array) -> Array:
	var out: Array = []
	for entry in DEFS:
		var index := _index_of(effects, entry[0])
		if index < 0:
			continue
		var count := int(stacks[index]) if index < stacks.size() else 1
		out.append([entry[1] + (" x%d" % count if count > 1 else ""), entry[2]])
	return out


## The label an id gets, or "" for one the table does not know.
static func label_for(effect_id: int) -> String:
	for entry in DEFS:
		if entry[0] == effect_id:
			return entry[1]
	return ""


## `in` is type-strict and a wire id may arrive as a float; -1 is an empty
## slot on the wire and is never a status.
static func _index_of(effects: Array, effect_id: int) -> int:
	for i in effects.size():
		if int(effects[i]) == effect_id and effect_id >= 0:
			return i
	return -1
