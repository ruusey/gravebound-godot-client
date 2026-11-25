extends GutTest

## The item card in the web client's order and words: compatibility for
## the viewer's class, damage with its scaling stat, DPS in the viewer's
## hands, affixes, a gem's effect and sockets, crystals, the socket, the
## stack. Numbers are worked by hand from the fixture.

const BARBARIAN := 0
const WIZARD := 2

var content: GameData


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))


func _item(item_id: int, extra := {}) -> Dictionary:
	var item := content.item_definition(item_id).duplicate(true)
	item.erase("itemClass")
	item.erase("archetypeId")
	item.merge(extra, true)
	return item


func _texts(item: Dictionary, viewer := {}) -> Array:
	return ItemCard.lines(item, content, viewer).map(func(line: Array) -> String: return line[0])


## The line's text, or "" when there is no such line -- never an index
## into nothing, which would error, and GUT counts an error as a pass.
func _text(item: Dictionary, starts: String, viewer := {}) -> String:
	var line := _line(item, starts, viewer)
	return line[0] if not line.is_empty() else ""


func _line(item: Dictionary, starts: String, viewer := {}) -> Array:
	for line in ItemCard.lines(item, content, viewer):
		if String(line[0]).begins_with(starts):
			return line
	return []


func test_whether_the_viewer_can_wear_it():
	var barbarian := {"class_id": BARBARIAN}
	assert_eq(_line(_item(101), "Compatible", barbarian), ["Compatible - Heavy Weapon (Axe)", ItemCard.GAIN],
		"the wire item has no itemClass; the catalog's is read by itemId")
	assert_eq(_line(_item(100), "Cannot", barbarian), ["Cannot equip - requires Light Weapon (Bow)", ItemCard.LOSS])
	assert_eq(_line(_item(103), "Cannot", barbarian), ["Cannot equip - requires Cloak Armor", ItemCard.LOSS])
	assert_eq(_line(_item(103), "Compatible", {"class_id": WIZARD}), ["Compatible - Cloak Armor", ItemCard.GAIN])
	assert_eq(_text(_item(104), "Compatible", barbarian), "Compatible - Any class")
	assert_eq(_text(_item(200), "Usable", barbarian), "Usable by: Any class", "no class: anyone")
	assert_eq(_line(_item(101), "Compatible"), [], "no viewer yet: no line, rather than a wrong one")


func test_damage_names_the_stat_it_scales_with():
	assert_eq(_text(_item(101), "Damage"), "Damage: 3-4 (scales with STR)", "a heavy archetype")
	assert_eq(_text(_item(100), "Damage"), "Damage: 5-9 (scales with DEX)", "a bow: light, 10-12")
	assert_eq(_text(_item(102), "Damage"), "Damage: 1-1 (scales with WIS)", "a tome: magic, 20-22")
	assert_eq(_text(_item(100, {"scalingStat": 0}), "Damage"), "Damage: 5-9 (scales with VIT)", "its own stat first")


func test_dps_in_the_viewers_hands():
	var viewer := {"class_id": BARBARIAN, "stats": {"str": 10, "dex": 25}}
	# Scattergun: (3.5 + 10 STR) a shot, the group's 2 x the archetype's 3
	# projectiles, int(6.5 * (25 + 17.3) / 75) = 3 attacks a second.
	assert_eq(_text(_item(101), "DPS", viewer), "DPS: 243 (6 shots - 3/s)")
	# Short Bow: (7 + 25 DEX), one shot, 3 a second.
	assert_eq(_text(_item(100), "DPS", viewer), "DPS: 96 (1 shot - 3/s)")
	assert_eq(_text(_item(101, {"gemstoneType": 2}), "DPS", viewer), "DPS: 279 (6 shots - 3/s)", "crit: +15% expected")
	assert_eq(_text(_item(101, {"gemstoneType": 7}), "DPS", viewer), "DPS: 279 (6 shots - 3/s)", "crushing: +15%")
	assert_eq(_text(_item(101, {"gemstoneType": 3}), "DPS", viewer), "DPS: 324 (8 shots - 3/s)", "multishot: one more")
	assert_eq(_text(_item(101, {"gemstoneType": 10}), "DPS", viewer), "DPS: 243 (6 shots - 3/s)",
		"a scaling gem is already in the stats")
	assert_eq(_line(_item(101), "DPS"), [], "no viewer: no DPS")


func test_a_melee_swing_counts_its_bolts_at_the_servers_share():
	var viewer := {"class_id": BARBARIAN, "stats": {"str": 10, "dex": 25}}
	var archetype_id := WeaponDps.archetype_id({}, content.item_definition(101))
	content.library.weapon_archetypes[archetype_id]["melee"] = true
	var group_id := int(content.item_definition(101)["damage"]["projectileGroupId"])
	content.library.projectile_groups[group_id]["projectiles"][1]["damage"] = 0
	# The 3-hit volley is the cone, the group's second projectile a bolt at 40%:
	# 13.5 x (3 + 0.4) x 3/s.
	assert_eq(_text(_item(101), "DPS", viewer), "DPS: 138 (6 shots - 3/s)")
	assert_eq(WeaponDps.of(_item(200), {}, {}, content), {}, "a potion deals nothing")


func test_a_melee_bolt_with_its_own_damage_counts_that_flat():
	var viewer := {"class_id": BARBARIAN, "stats": {"str": 10, "dex": 25}}
	var definition := content.item_definition(101)
	content.library.weapon_archetypes[WeaponDps.archetype_id({}, definition)]["melee"] = true
	var group: Dictionary = content.library.projectile_groups[int(definition["damage"]["projectileGroupId"])]
	group["projectiles"][1]["damage"] = 20
	# The 3-hit cone plus a flat 20 bolt: (13.5 x 3 + 20) x 3/s.
	assert_eq(_text(_item(101), "DPS", viewer), "DPS: 182 (6 shots - 3/s)")


func test_the_subtitle_affix_and_stack():
	var item := _item(104, {"tier": 3, "targetClass": WIZARD, "rarity": 2,
		"attributeModifiers": [{"statId": 0, "deltaValue": 2}, {"statId": 5, "deltaValue": -1}]})
	var texts := _texts(item)
	assert_eq(texts[1], "Uncommon - Tier 3 - Wizard")
	assert_true("Affix: +2 VIT - -1 DEF" in texts, str(texts))
	assert_eq(_texts(_item(104, {"targetClass": -4}))[1], "Mundane - Tier 0", "a negative class is no class")
	assert_eq(_texts(_item(104, {"tier": -1, "targetClass": -4, "rarity": 3}))[1], "Rare - Untiered",
		"untiered gear says so, so copies compare by rarity")
	assert_true("Stack x4/10" in _texts(_item(105, {"stackable": true, "stackCount": 4, "maxStack": 10})))
	assert_false(_texts(_item(105, {"stackable": true, "stackCount": 1, "maxStack": 10})).any(
		func(t: String) -> bool: return t.begins_with("Stack")), "one is not a stack")


func test_a_gem_says_what_it_does_and_where_it_goes():
	var texts := _texts(_item(321))
	assert_true("Gem Effect: Reflects 20% of damage taken back to enemy attackers." in texts, str(texts))
	assert_true("Sockets into: Armor, Gauntlet, Boots" in texts)
	assert_true("Sockets into: Weapon" in _texts(_item(320)))
	assert_eq(GemCatalog.sockets(9, {}), [0, 1, 2, 3, 4], "the table when the catalog says nothing")
	assert_false(_texts(_item(101)).any(func(t: String) -> bool: return t.begins_with("Gem Effect")), "a sword is not a gem")


func test_the_tooltip_knows_its_viewer_once_there_is_a_player():
	var state := RealmState.new(content, func() -> int: return 0)
	var card := ItemTooltip.of(state, content)
	autofree(card)
	assert_eq(card.viewer(), {})
	state.local.id = 1
	state.local.class_id = WIZARD
	state.local.stats = {"wis": 30}
	assert_eq(card.viewer(), {"class_id": WIZARD, "stats": {"wis": 30}})
	assert_eq(ItemCard.requirement(1, 99), "Heavy Weapon", "an archetype it has no name for is left off")
	assert_eq(ItemCard.requirement(50, 0), "Unknown")
