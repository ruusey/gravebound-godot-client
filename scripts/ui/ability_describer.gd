class_name AbilityDescriber
extends RefCounted

## The info card for a class ability or passive, as [text, colour] lines for
## ItemTooltip.show_lines. Works for anyone's kit -- the hotbar describes your own,
## the companion panel a companion's -- so everything it reads is passed in: the
## invested points and the stats that scale it.

const NAME_COLOUR := Color(1.0, 0.85, 0.42)
const MUTED := Color(0.6, 0.6, 0.65)
const BODY := Color(0.85, 0.85, 0.88)
const DAMAGE_COLOUR := Color(0.9, 0.66, 0.4)
const PIERCE_COLOUR := Color(0.4, 0.66, 1.0)
const EFFECT_COLOUR := Color(0.56, 0.82, 0.56)


static func passive_lines(abilities: AbilityCatalog, class_id: int) -> Array:
	var passive := abilities.passive(class_id)
	if passive.is_empty():
		return []
	return [[str(passive.get("name", "")), NAME_COLOUR], ["Class passive - always on", MUTED],
		[str(passive.get("description", "")), BODY]]


## `subtitle` leads the second line ("Active - Key 1"); the tags follow it.
static func ability_lines(abilities: AbilityCatalog, id: int, invested: int, stats: Dictionary,
		subtitle: String) -> Array:
	var definition := abilities.ability(id)
	if definition.is_empty():
		return []
	var lines: Array = [[str(definition.get("name", "")), NAME_COLOUR]]
	var tags := _tags_text(definition)
	if tags != "":
		subtitle += " - " + tags
	lines.append([subtitle, MUTED])
	var description := str(definition.get("description", ""))
	if description != "":
		lines.append([description, BODY])
	lines.append_array(_damage_lines(definition, invested, stats))
	lines.append([_facts_text(abilities, definition, id, invested), MUTED])
	for effect in definition.get("effects", []):
		var effect_text := _effect_text(effect, definition, invested, stats)
		if effect_text != "":
			lines.append([effect_text, EFFECT_COLOUR])
	for scaling in definition.get("scalings", []):
		if str(scaling.get("target", "")).to_upper() == "DAMAGE":
			continue
		lines.append([_scaling_text(scaling, invested, stats), MUTED])
	lines.append(["Level %d/%d" % [invested, abilities.cap(id)], MUTED])
	return lines


## Damage total plus the per-stat breakdown that builds it, like the web client:
## "Damage 162" then "= 90 base +48 (STR) +24 (SPx3)". Empty for a non-damage ability.
static func _damage_lines(definition: Dictionary, invested: int, stats: Dictionary) -> Array:
	var base := int(definition.get("baseDamage", 0))
	var total := float(base)
	var parts := PackedStringArray()
	if base > 0:
		parts.append("%d base" % base)
	for scaling in definition.get("scalings", []):
		if str(scaling.get("target", "")).to_upper() != "DAMAGE":
			continue
		var contribution := _scaling_contribution(scaling, invested, stats)
		if contribution > 0:
			total += contribution
			parts.append("+%d (%s)" % [int(contribution), _stat_label(scaling, invested)])
	if total <= 0:
		return []
	var pierces := _has_tag(definition, "armor_pierce")
	var header := ("Armor-pierce damage %d" if pierces else "Damage %d") % int(total)
	var out: Array = [[header, PIERCE_COLOUR if pierces else DAMAGE_COLOUR]]
	if not parts.is_empty():
		out.append(["= " + " ".join(parts), MUTED])
	return out


## MP, cooldown, cast time and reach on one line, all point-adjusted.
static func _facts_text(abilities: AbilityCatalog, definition: Dictionary, id: int, invested: int) -> String:
	var facts := PackedStringArray()
	var mp := int(definition.get("mpCost", 0))
	if mp > 0:
		facts.append("MP %d" % mp)
	facts.append("Cooldown %.1fs" % (abilities.cooldown_ms(id, invested) / 1000.0))
	var cast := abilities.cast_ms(id, invested)
	facts.append("Instant" if cast <= 0 else "Cast %.1fs" % (cast / 1000.0))
	var reach := int(definition.get("maxCastRange", -1))
	facts.append("Self" if reach == 0 else ("Range %d" % reach if reach > 0 else "Ranged"))
	return " - ".join(facts)


## One effect in words: a status and its duration, a heal, a shield, and so on.
static func _effect_text(effect: Dictionary, definition: Dictionary, invested: int, stats: Dictionary) -> String:
	var kind := str(effect.get("type", "")).to_upper()
	var target := _target_text(str(effect.get("target", "")))
	match kind:
		"STATUS_APPLY":
			# Total duration at the current rank (base + per-point/per-stat scaling),
			# so the shown duration equals the real one -- base alone was wrong for
			# every scaling self-buff and HoT.
			var duration := (float(effect.get("baseDurationMs", 0))
				+ _status_duration_bonus(effect, definition, invested, stats)) / 1000.0
			var status := _status_name(effect.get("statusId", ""))
			return "Apply %s%s%s" % [status, (" %.1fs" % duration) if duration > 0 else "", target]
		"HEAL":
			# Show the total at the current rank (base + per-point scaling), like damage,
			# so the number matches what the ability actually heals in game.
			return "Heal %d HP%s" % [_effect_total(effect, definition, invested, stats, "HEAL"), target]
		"SHIELD":
			return "Shield %d HP%s" % [_effect_total(effect, definition, invested, stats, "SHIELD"), target]
		"CLEANSE":
			var count := int(effect.get("baseMagnitude", 0))
			return "Cleanse " + ("all effects" if count <= 0 else "%d effects" % count)
		"TELEPORT":
			return "Teleport to target"
		"REFLECT_PROJECTILE":
			return "Reflect projectiles x%s" % _number(effect.get("damageMul", 1))
		"EMPOWER_NEXT_BASIC":
			return "Empower next basic +%d%%" % int(effect.get("baseMagnitude", 0))
		"SPAWN_POTIONS":
			return "Drop %d potions" % int(effect.get("baseMagnitude", 0))
		"PROJECTILE_GROUP":
			return "Fires a projectile volley%s" % target
		"DASH":
			return "Dash up to %.1f tiles" % (float(effect.get("baseMagnitude", 0)) / GameConstants.TILE_SIZE)
		"DEFLECT":
			var most := int(effect.get("maxStacks", 0))
			return "Deflect shots: +%d%% damage each%s" % [int(effect.get("baseMagnitude", 0)),
				(" (max +%d%%)" % (most * int(effect.get("baseMagnitude", 0)))) if most > 0 else ""]
		"DUEL":
			var refund := float(effect.get("killRefund", 0))
			return "Duel %.1fs: +%d%% damage from you%s" % [float(effect.get("baseDurationMs", 0)) / 1000.0,
				int(effect.get("baseMagnitude", 0)),
				(", %d%% cooldown back on a kill" % roundi(refund * 100.0)) if refund > 0.0 else ""]
		_:
			# Never silently drop an effect the card has no bespoke line for: name the
			# effect in words (never its raw type/id) and show any magnitude / duration
			# it carries, so the hover lists everything the ability does.
			if kind == "":
				return ""
			var parts := PackedStringArray([_prettify(kind)])
			var magnitude := int(effect.get("baseMagnitude", 0))
			if magnitude != 0:
				parts.append(str(magnitude))
			var seconds := float(effect.get("baseDurationMs", 0)) / 1000.0
			if seconds > 0.0:
				parts.append("%.1fs" % seconds)
			return " ".join(parts) + target


## A non-damage scaling: "DEX x1.5 -> Radius (+3)".
static func _scaling_text(scaling: Dictionary, invested: int, stats: Dictionary) -> String:
	var target := _prettify(str(scaling.get("target", "")))
	var contribution := _scaling_contribution(scaling, invested, stats)
	var current := " (+%d)" % int(contribution) if contribution > 0 else ""
	return "%s x%s -> %s%s" % [_stat_label(scaling, invested), _number(scaling.get("coeff", 0)), target, current]


## An effect's magnitude at the current rank: its base plus every scaling that
## targets it (HEAL/SHIELD). Mirrors the server's base + scaling sum so the shown
## number equals the real effect.
static func _effect_total(effect: Dictionary, definition: Dictionary, invested: int, stats: Dictionary,
		target_kind: String) -> int:
	var total := int(effect.get("baseMagnitude", 0))
	for scaling in definition.get("scalings", []):
		if str(scaling.get("target", "")).to_upper() == target_kind:
			total += int(_scaling_contribution(scaling, invested, stats))
	return total


## Extra duration (ms) a status gains at the current rank. Mirrors the server: a
## SELF status takes every "DURATION" scaling (selfDurationBonusMs); a targeted
## status (allies/enemies) takes the "STATUS_DURATION_MS" scalings keyed to its
## own effect index (statusDurationBonusMs).
static func _status_duration_bonus(effect: Dictionary, definition: Dictionary, invested: int,
		stats: Dictionary) -> float:
	var is_self := str(effect.get("target", "")).to_upper() == "SELF"
	var index: int = definition.get("effects", []).find(effect)
	var bonus := 0.0
	for scaling in definition.get("scalings", []):
		var target := str(scaling.get("target", "")).to_upper()
		if is_self and target == "DURATION":
			bonus += _scaling_contribution(scaling, invested, stats)
		elif target == "STATUS_DURATION_MS" and int(scaling.get("effectIndex", -1)) == index:
			bonus += _scaling_contribution(scaling, invested, stats)
	return bonus


## How much a scaling adds right now: the stat (or invested points) times the
## coefficient. Linear only -- the server's other curves aren't previewed.
static func _scaling_contribution(scaling: Dictionary, invested: int, stats: Dictionary) -> float:
	return _stat_value(str(scaling.get("stat", "")), invested, stats) * float(scaling.get("coeff", 0))


static func _stat_value(stat: String, invested: int, stats: Dictionary) -> float:
	if _is_skill_point_stat(stat):
		return float(invested)
	return float(stats.get(stat.to_lower(), 0))


static func _stat_label(scaling: Dictionary, invested: int) -> String:
	var stat := str(scaling.get("stat", ""))
	return "SPx%d" % invested if _is_skill_point_stat(stat) else stat.to_upper()


static func _is_skill_point_stat(stat: String) -> bool:
	var upper := stat.to_upper()
	return upper == "SKILL_POINTS" or upper == "SKILLPOINTS" or upper == "SP" or upper == "POINTS"


static func _has_tag(definition: Dictionary, tag: String) -> bool:
	for entry in definition.get("tags", []):
		if str(entry) == tag:
			return true
	return false


static func _tags_text(definition: Dictionary) -> String:
	var tags := PackedStringArray()
	for entry in definition.get("tags", []):
		tags.append(str(entry))
	return ", ".join(tags)


static func _target_text(target: String) -> String:
	return "" if target == "" else " to " + _prettify(target).to_lower()


## A status id (as it arrives in ability JSON, a numeric string) to its name, so the
## info card reads "Apply Slow" / "Apply Dome", never "Apply 21". Falls back to
## prettifying whatever was there for any id the chip table doesn't know.
static func _status_name(raw: Variant) -> String:
	var text := str(raw)
	if text.is_valid_int():
		var label := StatusChips.label_for(int(text))
		# Never fall through to showing the raw number: an id the chip table doesn't
		# know renders as a generic word, so the card never prints a bare status id.
		return label if label != "" else "status effect"
	return _prettify(text)


## A JSON enum to words: "ENEMIES_HIT" -> "Enemies hit".
static func _prettify(raw: String) -> String:
	if raw == "":
		return ""
	var words := raw.to_lower().replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


static func _number(value) -> String:
	var number := float(value)
	return str(int(number)) if is_equal_approx(number, round(number)) else "%.1f" % number
