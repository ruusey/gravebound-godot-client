extends GutTest

## The ability card's wording for effects with their own line.


func _line(effect: Dictionary) -> String:
	return AbilityDescriber._effect_text(effect, {}, 0, {})


func test_a_dash_reads_in_tiles():
	assert_eq(_line({"type": "DASH", "baseMagnitude": 96}), "Dash up to 3.0 tiles")


func test_a_deflect_names_its_bonus_and_cap():
	assert_eq(_line({"type": "DEFLECT", "baseMagnitude": 20, "maxStacks": 5}),
		"Deflect shots: +20% damage each (max +100%)")
	assert_eq(_line({"type": "DEFLECT", "baseMagnitude": 20}), "Deflect shots: +20% damage each")


func test_a_duel_names_its_length_bonus_and_refund():
	assert_eq(_line({"type": "DUEL", "baseDurationMs": 6000, "baseMagnitude": 25, "killRefund": 0.5}),
		"Duel 6.0s: +25% damage from you, 50% cooldown back on a kill")
