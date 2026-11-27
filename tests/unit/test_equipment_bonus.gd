extends GutTest

## What the worn items add, taken back off the wire's computed stats.

var inventory: Inventory


func before_each():
	inventory = Inventory.new()


func _wear(slot: int, item: Dictionary) -> void:
	item["itemId"] = 100 + slot
	inventory.slots[slot] = item


func test_sums_stats_affixes_and_enchantments_across_the_five_worn_slots():
	_wear(0, {"stats": {"str": 4, "dex": 1}, "attributeModifiers": [{"statId": 4, "deltaValue": 3}]})
	_wear(3, {"stats": {"spd": -2}, "enchantments": [{"statId": 5, "deltaValue": 2}, {"statId": 2, "deltaValue": 20}]})
	_wear(4, {"attributeModifiers": [{"statId": 0, "deltaValue": 5}, {"statId": 1, "deltaValue": 1}]})
	var bonus := EquipmentBonus.of(inventory)
	assert_eq(bonus["str"], 7, "4 on the sword and 3 from its affix (statId 4)")
	assert_eq(bonus["dex"], 1)
	assert_eq(bonus["spd"], -2)
	assert_eq(bonus["def"], 2, "the forge enchantment, statId 5")
	assert_eq(bonus["hp"], 20, "statId 2 is hp")
	assert_eq(bonus["vit"], 5, "statId 0 is vit")
	assert_eq(bonus["wis"], 1)
	assert_eq(bonus["mp"], 0)


func test_the_backpack_does_not_count():
	_wear(Inventory.BACKPACK_START, {"stats": {"str": 50}})
	_wear(Inventory.SIZE - 1, {"stats": {"def": 50}})
	assert_eq(EquipmentBonus.of(inventory), EquipmentBonus.empty())


func test_an_unknown_stat_id_is_ignored():
	_wear(1, {"attributeModifiers": [{"statId": 8, "deltaValue": 9}, {"statId": -1, "deltaValue": 9}]})
	assert_eq(EquipmentBonus.of(inventory), EquipmentBonus.empty())
