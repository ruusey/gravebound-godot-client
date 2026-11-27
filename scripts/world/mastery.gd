class_name Mastery
extends RefCounted

## The nine account-wide skills and the server's level curve.
##
## `SkillsPacket` carries only XP totals, one per `PlayerSkill` ordinal; the
## level, the bar and every line of text are derived here. The curve is the
## server's (`PlayerSkillHelper`: total XP for level L is 510 L^2, capped at
## 99), and the text is the web client's (`SKILL_NAMES`, `SKILL_DESC`,
## `SKILL_EFFECT`, `SKILL_XP_RULE`), which mirrors the server's award rates.

const CURVE_K := 510
const MAX_LEVEL := 99

## Name, what it covers, its effect a level, the per-level percent and what
## it boosts, and how XP is earned. Indexed by the server's ordinal.
const SKILLS := [
	["Ranged Combat Mastery", "Damage with ranged (light) weapons.", 0.1, "ranged damage",
		"1 XP per 20 damage dealt with ranged weapons"],
	["Melee Combat Mastery", "Damage with melee (heavy) weapons.", 0.1, "melee damage",
		"1 XP per 20 damage dealt with melee weapons"],
	["Magic Combat Mastery", "Damage with magic weapons.", 0.1, "magic damage",
		"1 XP per 20 damage dealt with magic weapons"],
	["Heavy Armor Mastery", "Toughness while wearing heavy armor.", 0.1, "damage reduction",
		"1 XP per damage taken while in heavy armor"],
	["Light Armor Mastery", "Toughness while wearing light armor.", 0.1, "damage reduction",
		"1 XP per damage taken while in light armor"],
	["Cloak Armor Mastery", "Toughness while wearing cloak armor.", 0.1, "damage reduction",
		"1 XP per damage taken while in cloak armor"],
	["Support Caster Mastery", "Buffing your allies with abilities.", 0.15, "ally buff duration",
		"25 XP/sec of buff applied to an ally"],
	["Impairment Caster Mastery", "Debuffing enemies with abilities.", 0.15, "enemy debuff duration",
		"15 XP/sec of debuff applied to an enemy"],
	["DPS Caster Mastery", "Dealing ability damage.", 0.1, "ability damage",
		"0.5 XP per ability damage dealt"],
]


static func total_xp_for_level(level: int) -> int:
	if level <= 0:
		return 0
	var capped := mini(level, MAX_LEVEL)
	return CURVE_K * capped * capped


## The server's search: a square-root guess, walked up and down to the exact
## level, so float error at a boundary cannot land one off.
static func level_for_xp(xp: int) -> int:
	if xp <= 0:
		return 0
	var level := int(sqrt(float(xp) / CURVE_K))
	while level < MAX_LEVEL and total_xp_for_level(level + 1) <= xp:
		level += 1
	while level > 0 and total_xp_for_level(level) > xp:
		level -= 1
	return mini(level, MAX_LEVEL)


## How far into the current level, 0..1; full at the cap.
static func progress(xp: int) -> float:
	var level := level_for_xp(xp)
	if level >= MAX_LEVEL:
		return 1.0
	var base := total_xp_for_level(level)
	var span := maxi(1, total_xp_for_level(level + 1) - base)
	return clampf(float(xp - base) / span, 0.0, 1.0)


## The web client's hover card for one skill, as lines.
static func describe(index: int, xp: int) -> String:
	var skill: Array = SKILLS[index]
	var level := level_for_xp(xp)
	var pct: float = skill[2]
	var lines := PackedStringArray([
		skill[1],
		"Effect: +%s%% %s / level" % [_pct(pct), skill[3]],
		"Now: +%.1f%% %s" % [level * pct, skill[3]],
		"XP: " + skill[4],
		"Current XP: " + thousands(xp),
	])
	if level >= MAX_LEVEL:
		lines.append("Max level reached")
	else:
		var next := total_xp_for_level(level + 1)
		lines.append("Next level: %s XP" % thousands(next))
		lines.append("Remaining: %s XP" % thousands(next - xp))
	return "\n".join(lines)


static func _pct(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")


static func thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
