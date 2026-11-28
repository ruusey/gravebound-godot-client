extends GutTest

## The ability card's wording for effects with their own line.


func _line(effect: Dictionary) -> String:
	return AbilityDescriber._effect_text(effect, {}, 0, {})


func test_a_dash_reads_in_tiles():
	assert_eq(_line({"type": "DASH", "baseMagnitude": 96}), "Dash up to 3.0 tiles")


func test_a_dash_names_its_kill_refund():
	assert_eq(_line({"type": "DASH", "baseMagnitude": 96, "killRefund": 1.0}),
		"Dash up to 3.0 tiles, a kill resets the cooldown")
	assert_eq(_line({"type": "DASH", "baseMagnitude": 96, "killRefund": 0.5}),
		"Dash up to 3.0 tiles, 50% cooldown back on a kill")


func test_an_absorb_names_its_burst_multiplier():
	assert_eq(_line({"type": "ABSORB", "baseMagnitude": 10}), "Armored guard: burst for 10x the damage you take")


func test_a_duel_names_its_length_bonus_and_refund():
	assert_eq(_line({"type": "DUEL", "baseDurationMs": 6000, "baseMagnitude": 25, "killRefund": 0.5}),
		"Duel 6.0s: +25% damage from you, 50% cooldown back on a kill")
