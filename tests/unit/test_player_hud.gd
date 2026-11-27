extends GutTest

## The player HUD under the minimap: identity, the three bars, the stats
## grid with the equipment's part beside each, and when a stat reads gold.

var data: GameData
var state: RealmState
var hud: PlayerHud


func before_each():
	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(data, func() -> int: return 0)
	hud = PlayerHud.new()
	hud.setup(state, data)
	add_child_autofree(hud)


func _arrive(stats: Dictionary, health: int, mana: int, experience: int, worn := {}, maxed := 0) -> void:
	state.local.id = 1
	state.local.name = "Ruu"
	state.local.class_id = 0
	var carried: Array = []
	for i in Inventory.SIZE:
		carried.append({"itemId": -1})
	for slot in worn:
		carried[slot] = worn[slot]
	state.apply_packet("UpdatePacket", {"playerId": 1, "playerName": "Ruu", "stats": stats,
		"health": health, "mana": mana, "experience": experience, "inventory": carried,
		"hpPotions": 0, "mpPotions": 0, "dyeId": 0, "maxedStats": maxed})
	hud._process(0.0)


func test_hidden_until_there_is_a_player_and_pinned_under_the_minimap():
	hud._process(0.0)
	assert_false(hud.visible)
	_arrive({"hp": 200, "mp": 100}, 150, 100, 0)
	assert_true(hud.visible)
	assert_eq(hud._root.offset_top, 10.0 + 200.0 + 8.0, "the minimap's margin and side, then ours")
	assert_eq(hud._root.offset_bottom, float(PlayerHud.BOTTOM))
	assert_eq(hud._root.offset_right - hud._root.offset_left, 200.0, "as wide as the minimap")
	hud.shown = false
	hud._process(0.0)
	assert_false(hud.visible)


func test_identity_bars_and_level_read_the_wire():
	_arrive({"hp": 340, "mp": 120, "str": 18}, 210, 30, 200)
	assert_eq(hud._identity.text, "Ruu  Barbarian")
	assert_eq(hud._bars["hp"][1].text, "210/340")
	assert_almost_eq(hud._bars["hp"][0].value, 210.0 / 340.0, 0.001)
	assert_eq(hud._bars["mp"][1].text, "30/120")
	assert_eq(hud._bars["xp"][1].text, "Lv 2  99 / 199", "200 on a level running 101-300")
	assert_almost_eq(hud._bars["xp"][0].value, 99.0 / 199.0, 0.001)
	assert_eq(hud._cells["str"][0].text, "18")
	assert_eq(hud._cells["str"][1].text, "", "nothing worn, no bonus shown")


func test_the_xp_bar_becomes_fame_past_the_table():
	_arrive({"hp": 1}, 1, 0, 600 + 2500 * 3)
	assert_eq(hud._bars["xp"][1].text, "Lv 4  Fame: 3")
	assert_eq(hud._bars["xp"][0].value, 1.0, "full, and gold")


func test_the_bonus_shows_beside_the_value_and_gold_follows_the_server_flag():
	# A sword worth +7 STR shows 79 and the server says STR is not maxed;
	# boots costing 2 SPD show 48 and the server says SPD is (bit 4).
	_arrive({"hp": 340, "mp": 120, "str": 79, "spd": 48}, 340, 120, 0, {
		0: {"itemId": 49, "stats": {"str": 4}, "attributeModifiers": [{"statId": 4, "deltaValue": 3}]},
		3: {"itemId": 845, "stats": {"spd": -2}}}, 1 << 4)
	assert_eq(hud._cells["str"][0].text, "79")
	assert_eq(hud._cells["str"][1].text, "+7")
	assert_eq(hud._cells["str"][1].get_theme_color("font_color"), PlayerHud.BONUS_UP)
	assert_eq(hud._cells["str"][0].get_theme_color("font_color"), Color.WHITE, "not flagged maxed")
	assert_eq(hud._cells["spd"][0].text, "48")
	assert_eq(hud._cells["spd"][1].text, "-2")
	assert_eq(hud._cells["spd"][1].get_theme_color("font_color"), PlayerHud.BONUS_DOWN)
	assert_eq(hud._cells["spd"][0].get_theme_color("font_color"), PlayerHud.GOLD, "flagged maxed")


func test_a_passive_bonus_alone_never_reads_gold():
	# A Wizard's passive WIS lifts the shown value past the cap with no gear
	# worn; only the server's flag on the base turns it gold.
	_arrive({"hp": 340, "mp": 120, "wis": 78}, 340, 120, 0)
	assert_eq(hud._cells["wis"][0].get_theme_color("font_color"), Color.WHITE)
	_arrive({"hp": 340, "mp": 120, "wis": 80}, 340, 120, 0, {}, -128)
	assert_eq(hud._cells["wis"][0].get_theme_color("font_color"), PlayerHud.GOLD, "bit 7 arrives as a signed byte")


func test_hp_and_mp_numbers_go_gold_at_their_caps():
	_arrive({"hp": 780, "mp": 100}, 400, 100, 0, {}, 1 << 0)
	assert_eq(hud._bars["hp"][1].get_theme_color("font_color"), PlayerHud.GOLD)
	assert_eq(hud._bars["mp"][1].get_theme_color("font_color"), Color.WHITE)


func test_redraws_only_when_something_it_shows_changed():
	_arrive({"hp": 200, "mp": 100}, 150, 100, 0)
	var drawn: String = hud._drawn
	hud._process(0.0)
	assert_eq(hud._drawn, drawn)
	state.apply_packet("PlayerStatePacket", {"playerId": 1, "health": 120, "mana": 100,
		"effectIds": [], "effectTimes": [], "effectStacks": []})
	hud._process(0.0)
	assert_ne(hud._drawn, drawn)
	assert_eq(hud._bars["hp"][1].text, "120/200")


func test_the_strings_the_bar_is_built_from():
	var levels := ExperienceLevels.new()
	assert_eq(PlayerHud.xp_line(levels, 50), ["Lv 1", 0.0, false], "no table: a level and nothing to count")
	assert_eq(PlayerHud.bonus_text(0), "")
	assert_eq(PlayerHud.bonus_text(5), "+5")
	assert_eq(PlayerHud.bonus_text(-3), "-3")
	assert_false(PlayerHud.maxed({"str": 80}, {}, "str"), "no cap known, never gold")
