class_name EquipmentBonus
extends RefCounted

## What the worn equipment adds to each stat: each of the five worn items'
## own stats, its affix modifiers and its forge enchantments, the additive
## parts of Player.getComputedStats, keyed by statId in its order. Gems and
## buffs scale rather than add and are left out.

const STATS := ["hp", "mp", "def", "str", "spd", "dex", "vit", "wis"]
## Player.applyStatDelta's switch: statId 0..7.
const BY_ID := ["vit", "wis", "hp", "mp", "str", "def", "spd", "dex"]


static func of(inventory: Inventory) -> Dictionary:
	var bonus := empty()
	for slot in Inventory.EQUIPMENT_SLOTS:
		var item := inventory.item_at(slot)
		if item.is_empty():
			continue
		var stats: Dictionary = item.get("stats", {})
		for stat in STATS:
			bonus[stat] += int(stats.get(stat, 0))
		for delta in item.get("attributeModifiers", []) + item.get("enchantments", []):
			var id := int(delta.get("statId", -1))
			if id >= 0 and id < BY_ID.size():
				bonus[BY_ID[id]] += int(delta.get("deltaValue", 0))
	return bonus


static func empty() -> Dictionary:
	var out := {}
	for stat in STATS:
		out[stat] = 0
	return out
