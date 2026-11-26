extends GutTest

## The effect names generated off CreateEffectPacket, and that the
## registry and the renderer's rules speak them.


func test_the_names_are_the_servers_ids():
	assert_eq(EffectType.HEAL_RADIUS, 0)
	assert_eq(EffectType.STASIS_FIELD, 2)
	assert_eq(EffectType.BLADE_BLENDER, 47)
	assert_eq(EffectType.SANCTUARY_DOME, 51)
	assert_eq(EffectType.BEAM_WARNING, 64)
	assert_eq(EffectType.NAMES[62], "MELEE_SWING")
	assert_eq(EffectType.CONE_WARNING, 67)
	assert_eq(EffectType.EMERGE, 73)
	assert_eq(EffectType.CIRCLE_WARNING, 74)


func test_retired_ids_have_no_name():
	# 21 was never used; 48-50 were the old Sorcerer/Rogue/Mystic effects.
	for retired in [21, 48, 49, 50]:
		assert_false(EffectType.NAMES.has(retired), "id %d" % retired)
	assert_eq(EffectType.NAMES.size(), 71)


func test_every_drawer_is_registered_under_a_live_type():
	for kind in range(0, 80):
		if Fx.for_type(kind).is_valid():
			assert_true(EffectType.NAMES.has(kind), "a drawer for retired id %d" % kind)


func test_the_persistent_refresh_types_are_the_two_blade_fields():
	assert_eq(AbilityState.PERSISTENT_TYPES, [46, 47])
