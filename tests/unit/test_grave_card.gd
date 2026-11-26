extends GutTest

## What a grave says, under it and when stood on.

const GRAVE := {"name": "Ruu", "classId": 0, "level": 17, "maxedStats": 6,
	"killedBy": "Dragon King", "killingBlow": 412, "diedAt": 1_000_000}


func test_the_record_comes_off_a_list_of_none_or_one():
	assert_eq(GraveCard.record([]), {})
	assert_eq(GraveCard.record(null), {})
	assert_eq(GraveCard.record([GRAVE]), GRAVE)


func test_the_caption_is_the_name_and_level():
	assert_eq(GraveCard.caption(GRAVE), "Ruu lvl 17")
	assert_eq(GraveCard.caption({}), "", "a bag that is not a grave says nothing")


func test_the_card_tells_the_whole_story():
	var lines := GraveCard.card(GRAVE, null, 1_000_000 + 5 * 60_000).split("\n")
	assert_eq(lines[0], "Ruu lvl 17")
	assert_eq(lines[1], "6/8 maxed")
	assert_eq(lines[2], "Killed by Dragon King")
	assert_eq(lines[3], "Final blow: 412 damage")
	assert_eq(lines[4], "Died 5 min ago")


func test_an_unknown_blow_is_left_out():
	var grave := GRAVE.duplicate()
	grave["killingBlow"] = 0
	assert_false("Final blow" in "\n".join(GraveCard.facts(grave, null)))


func test_time_reads_in_the_largest_unit():
	assert_eq(GraveCard.ago(10_000), "just now")
	assert_eq(GraveCard.ago(-5_000), "just now", "a clock a little ahead")
	assert_eq(GraveCard.ago(59 * 60_000), "59 min ago")
	assert_eq(GraveCard.ago(3 * 3_600_000), "3 h ago")
	assert_eq(GraveCard.ago(50 * 3_600_000), "2 d ago")


func test_a_loaded_grave_keeps_its_record_and_a_bag_has_none():
	var state := RealmState.new(null, func() -> int: return 0)
	state.apply_packet("LoadPacket", {"containers": [
		{"lootContainerId": 3, "tier": 5, "items": [], "pos": {"x": 0.0, "y": 0.0}, "grave": [GRAVE]},
		{"lootContainerId": 4, "tier": 0, "items": [], "pos": {"x": 8.0, "y": 0.0}, "grave": []}]})
	assert_eq(state.entities.containers[3]["grave"]["killedBy"], "Dragon King")
	assert_eq(state.entities.containers[4]["grave"], {})
