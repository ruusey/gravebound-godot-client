class_name ItemCard
extends RefCounted

## What an item's card says: the web client's getItemTooltipHTML, as
## [text, colour] lines, in its order -- name, the rarity / tier / class
## line, whether you can wear it, the description, damage and what it
## scales with, DPS in your hands, the stats, the rolled affix, a gem's
## effect and sockets, the crystals, the gem socket, the stack.
##
## The wire item lacks the catalog's fields (itemClass, archetypeId,
## scalingStat), so they are read by itemId from the content; the viewer
## -- {class_id, stats} -- decides the compatibility line and the DPS.
## Without content or a viewer those lines are left out, as the web
## leaves them out before it knows your class.

const MUTED := Color(0.6, 0.6, 0.65)
const BODY := Color(0.85, 0.85, 0.88)
const GAIN := Color("40c040")
const LOSS := Color("e06060")
const GOLD := Color("c8a86e")
const DAMAGE := Color("e0a060")
const DPS := Color("ffd24a")
## Magic-find line — a standout violet shared with the loot/immune accents.
const LOOT := Color("cc4dff")
const CLASS_LABELS := {1: "Heavy Weapon", 2: "Light Weapon", 3: "Magic Weapon",
	10: "Heavy Armor", 11: "Light Armor", 12: "Cloak Armor", 99: "Any class"}
const ARCHETYPE_LABELS := {1: "Sword", 2: "Axe", 3: "Hammer", 10: "Dagger", 11: "Bow",
	12: "Knife", 20: "Tome", 21: "Staff", 22: "Wand"}


static func lines(item: Dictionary, content: GameData = null, viewer := {}) -> Array:
	var definition := {} if content == null else content.item_definition(int(item.get("itemId", -1)))
	var rarity := ForgeRules.rarity(item)
	var out: Array = [[str(item.get("name", definition.get("name", "Unknown Item"))), ItemTooltip.RARITY_COLOURS[rarity]]]
	out.append([" - ".join(_subtitle(item, rarity, content)), MUTED])
	if content != null and viewer.has("class_id"):
		out.append(compatibility(item, definition, int(viewer["class_id"]), content))
	var description := str(item.get("description", definition.get("description", "")))
	if description != "":
		out.append([description, BODY])
	var damage: Dictionary = item.get("damage", {})
	if int(damage.get("min", 0)) > 0 or int(damage.get("max", 0)) > 0:
		out.append(["Damage: %d-%d (scales with %s)" % [int(damage.get("min", 0)), int(damage.get("max", 0)),
			ForgeRules.STAT_LABELS[WeaponDps.scaling_stat(item, definition)]], DAMAGE])
		var dps := WeaponDps.of(item, definition, viewer.get("stats", {}), content) if viewer.has("stats") else {}
		if int(dps.get("dps", 0)) > 0:
			out.append(["DPS: %d (%s - %s/s)" % [dps["dps"], "1 shot" if dps["bullets"] == 1 else "%d shots" % dps["bullets"],
				WeaponDps.rate_text(dps["per_second"])], DPS])
	out.append_array(_stats(item.get("stats", {})))
	# Magic find rides on the catalog template (lootFind), not the wire item, so read
	# it by itemId like itemClass/scalingStat above. Shown as a whole-percent bonus.
	var loot_find := float(item.get("lootFind", definition.get("lootFind", 0.0)))
	if loot_find > 0.0:
		out.append(["Loot Find +%d%%" % int(round(loot_find * 100.0)), LOOT])
	out.append_array(_affix(item.get("attributeModifiers", [])))
	out.append_array(_gem_item(item, definition))
	out.append_array(_forge(item))
	if bool(item.get("stackable", false)) and int(item.get("stackCount", 1)) > 1:
		out.append(["Stack x%d/%d" % [int(item["stackCount"]), int(item.get("maxStack", 0))], BODY])
	return out


## "Compatible - Heavy Weapon (Sword)", "Cannot equip - requires ...", or
## "Usable by: Any class" for an item with no class, as the web shows it.
static func compatibility(item: Dictionary, definition: Dictionary, class_id: int, content: GameData) -> Array:
	var item_class := int(item.get("itemClass", definition.get("itemClass", ItemRules.CLASS_NONE)))
	if item_class == ItemRules.CLASS_NONE:
		return ["Usable by: Any class", GOLD]
	var label := requirement(item_class, WeaponDps.archetype_id(item, definition))
	if ItemRules.class_allows(class_id, int(item.get("itemId", -1)), content):
		return ["Compatible - %s" % label, GAIN]
	return ["Cannot equip - requires %s" % label, LOSS]


static func requirement(item_class: int, archetype: int) -> String:
	var label: String = CLASS_LABELS.get(item_class, "Unknown")
	if item_class in ItemRules.WEAPON_CLASSES and ARCHETYPE_LABELS.has(archetype):
		label += " (%s)" % ARCHETYPE_LABELS[archetype]
	return label


static func _subtitle(item: Dictionary, rarity: int, content: GameData) -> Array:
	var bits: Array = [ItemTooltip.RARITY_NAMES[rarity]]
	if int(item.get("tier", -1)) >= 0:
		bits.append("Tier %d" % int(item["tier"]))
	elif not bool(item.get("consumable", false)) and Inventory.is_equipment(int(item.get("targetSlot", -1))):
		bits.append("Untiered")
	var target := int(item.get("targetClass", -1))
	if content != null and content.library.classes.has(target):
		bits.append(content.classes_art.display_name(target))
	if bool(item.get("consumable", false)):
		bits.append("Consumable")
	return bits


static func _stats(stats: Dictionary) -> Array:
	var gains := PackedStringArray()
	var losses := PackedStringArray()
	for stat in EquipmentBonus.STATS:
		var value := int(stats.get(stat, 0))
		if value > 0:
			gains.append("+%d %s" % [value, stat.to_upper()])
		elif value < 0:
			losses.append("%d %s" % [value, stat.to_upper()])
	var out: Array = []
	if not gains.is_empty():
		out.append(["  ".join(gains), GAIN])
	if not losses.is_empty():
		out.append(["  ".join(losses), LOSS])
	return out


## The rolled affix: "Affix: +2 VIT - -1 DEF".
static func _affix(modifiers: Array) -> Array:
	if modifiers.is_empty():
		return []
	var parts := PackedStringArray()
	for m in modifiers:
		var delta := int(m.get("deltaValue", 0))
		var stat := int(m.get("statId", -1))
		parts.append("%s%d %s" % ["+" if delta > 0 else "", delta,
			ForgeRules.STAT_LABELS[stat] if stat >= 0 and stat < ForgeRules.STAT_LABELS.size() else "?"])
	return [["Affix: " + " - ".join(parts), GOLD]]


## A gem, before it is socketed: what it does and where it can go.
static func _gem_item(item: Dictionary, definition: Dictionary) -> Array:
	if not (ForgeRules.is_gem(item) or ForgeRules.is_gem(definition)):
		return []
	var gem := int(item.get("gemstoneType", definition.get("gemstoneType", 0)))
	var out: Array = []
	if GemCatalog.description(gem) != "":
		out.append(["Gem Effect: " + GemCatalog.description(gem), GOLD])
	var slots := GemCatalog.sockets(gem, definition)
	if gem != 0 and not slots.is_empty():
		out.append(["Sockets into: " + ForgeRules._slot_names(slots), GOLD])
	return out


## What the forge has put on it: each crystal on its own line against the
## rarity's cap, then the socket only Epic and Legendary pieces carry.
static func _forge(item: Dictionary) -> Array:
	var out: Array = []
	var crystals := ForgeRules.enchantments(item)
	var equipment := Inventory.is_equipment(int(item.get("targetSlot", -1)))
	if not crystals.is_empty():
		out.append(["Crystals (%d/%d)" % [crystals.size(), ForgeRules.crystal_cap(item)], GOLD])
		for crystal in crystals:
			out.append(["  " + ForgeRules.enchantment_label(crystal), BODY])
	elif ForgeRules.crystal_cap(item) > 0 and equipment:
		out.append(["Crystal slots: 0/%d" % ForgeRules.crystal_cap(item), MUTED])
	if ForgeRules.has_gem_socket(item) and equipment:
		var gem := int(item.get("gemstoneType", 0))
		if gem > 0:
			var what := GemCatalog.description(gem)
			out.append(["Gem: %s%s" % [GemCatalog.name_of(gem), (" - " + what) if what != "" else ""], GOLD])
		else:
			out.append(["Gem socket: empty", MUTED])
	return out
