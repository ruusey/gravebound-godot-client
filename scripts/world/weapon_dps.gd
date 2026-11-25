class_name WeaponDps
extends RefCounted

## What a weapon would do in your hands: the web client's computeWeaponDps.
##
## A shot is the damage range's average plus the weapon's scaling stat,
## times the archetype's damage multiplier, times whatever a combat gem
## adds (crushing +15% damage, crit +15% as an expected value). The shots
## per attack are the projectile group's count times the archetype's
## projectiles, plus a multishot gem's -- except a melee swing, which is one
## cone hit (repeated per multishot) plus the group's other projectiles as bolts
## at the server's MELEE_BURST_DAMAGE_SCALE, or a bolt's own flat damage when it
## sets one; attacks per second are the
## server's DEX formula times the archetype's speed (AttackRate, with no
## status effects -- the card describes the weapon, not this moment).

## statId order, as ForgeRules.STAT_LABELS and the stats keys.
const STAT_KEYS := ["vit", "wis", "hp", "mp", "str", "def", "spd", "dex"]
const STR := 4
const WIS := 1
const DEX := 7
## ServerGameLogic.MELEE_BURST_DAMAGE_SCALE: a melee weapon's bolts hit for this
## share of the swing.
const MELEE_BURST_SCALE := 0.4


## The stat a weapon scales with: its own, the catalog's, or its archetype
## family's -- magic (20-22) WIS, light (10-12) DEX, anything else STR.
static func scaling_stat(item: Dictionary, definition: Dictionary) -> int:
	for source in [item, definition]:
		if source.get("scalingStat") != null:
			return int(source["scalingStat"])
	var archetype := archetype_id(item, definition)
	if archetype >= 20 and archetype <= 22:
		return WIS
	if archetype >= 10 and archetype <= 12:
		return DEX
	return STR


static func archetype_id(item: Dictionary, definition: Dictionary) -> int:
	return int(item.get("archetypeId", definition.get("archetypeId", 0)))


## {dps, per_shot, bullets, per_second}, or {} for something that deals no
## damage.
static func of(item: Dictionary, definition: Dictionary, stats: Dictionary, content: GameData) -> Dictionary:
	var damage: Dictionary = item.get("damage", definition.get("damage", {}))
	if int(damage.get("min", 0)) <= 0 and int(damage.get("max", 0)) <= 0:
		return {}
	var average := (float(damage.get("min", 0)) + float(damage.get("max", 0))) / 2.0
	var archetype: Dictionary = {} if content == null \
		else content.library.weapon_archetypes.get(archetype_id(item, definition), {})
	var damage_mul := _positive(archetype, "damageMul")
	var speed_mul := _positive(archetype, "attackSpeedMul")
	var projectiles := int(_positive(archetype, "projectileCount"))
	var gem := GemCatalog.shot_effect(int(item.get("gemstoneType", 0)))
	var stat := int(stats.get(STAT_KEYS[scaling_stat(item, definition)], 0))
	var per_shot := (average + stat) * damage_mul
	per_shot *= 1.0 + float(gem.get("damage_pct", 0)) / 100.0
	per_shot *= 1.0 + float(gem.get("crit_pct", 0)) / 100.0
	var group: Array = [] if content == null else content.projectiles_in_group(int(damage.get("projectileGroupId", -1)))
	var volley := maxi(1, projectiles + int(gem.get("extra_projectiles", 0)))
	var bullets := maxi(group.size(), 1) * volley
	var per_attack := per_shot * bullets
	if bool(archetype.get("melee", false)):
		per_attack = per_shot * volley
		for bolt in group.slice(1):
			var flat := float(bolt.get("damage", 0))
			per_attack += flat if flat > 0.0 else per_shot * MELEE_BURST_SCALE
	var per_second := AttackRate.per_second(int(stats.get("dex", 0)), speed_mul, [])
	return {"dps": roundi(per_attack * per_second), "per_shot": roundi(per_shot),
		"bullets": bullets, "per_second": snappedf(per_second, 0.01)}


## "3" or "4.5": the web's Math.round(x * 100) / 100, printed as a number.
static func rate_text(per_second: float) -> String:
	return str(roundi(per_second)) if is_equal_approx(per_second, roundf(per_second)) else str(snappedf(per_second, 0.01))


static func _positive(table: Dictionary, key: String) -> float:
	var value := float(table.get(key, 0.0))
	return value if value > 0.0 else 1.0
