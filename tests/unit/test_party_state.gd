extends GutTest

## The roster as the server sends it, and a teammate's cooldown read against the wall.

var party: PartyState
var now := 10_000
var wall := 1_700_000_000_000


func before_each():
	now = 10_000
	wall = 1_700_000_000_000
	party = PartyState.new(func() -> int: return wall)


func _member(id: int, name: String, ends := []) -> Dictionary:
	return {"playerId": id, "name": name, "classId": 0, "abilityCooldownEnds": ends}


func test_the_roster_is_whatever_the_last_update_said():
	assert_false(party.in_party())
	party.apply_update({"partyId": 7, "leaderId": 2, "members": [_member(1, "Ruu"), _member(2, "Mingau")]})
	assert_true(party.in_party())
	assert_true(party.is_leader(2))
	assert_false(party.is_leader(1))
	assert_eq(party.member_ids(), [1, 2])
	assert_eq(party.others(1).map(func(m: Dictionary) -> String: return m["name"]), ["Mingau"])
	var version := party.version
	party.apply_update({"partyId": 7, "leaderId": 2, "members": [_member(1, "Ruu"), _member(2, "Mingau"), _member(3, "Bort")]})
	assert_eq(party.members.size(), 3)
	assert_gt(party.version, version)


func test_party_id_zero_is_no_party_whatever_else_the_packet_carries():
	party.apply_update({"partyId": 7, "leaderId": 2, "members": [_member(1, "Ruu"), _member(2, "Mingau")]})
	party.apply_update({"partyId": 0, "leaderId": 2, "members": [_member(1, "Ruu")]})
	assert_false(party.in_party())
	assert_eq(party.members, [])
	assert_eq(party.leader_id, 0)
	assert_false(party.is_leader(2))


func test_a_cooldown_is_what_is_left_of_it_against_the_wall_clock():
	var m := _member(2, "Mingau", [0, wall + 3000, wall - 10, 0])
	assert_almost_eq(party.cooldown_fraction(m, 1, 6000), 0.5, 0.001, "3 of 6 seconds left")
	assert_eq(party.cooldown_fraction(m, 1, 2000), 1.0, "more left than the cooldown is long: capped")
	assert_eq(party.cooldown_fraction(m, 2, 6000), 0.0, "already over")
	assert_eq(party.cooldown_fraction(m, 0, 6000), 0.0)
	assert_eq(party.cooldown_fraction(m, 1, 0), 0.0, "no cooldown known")
	assert_eq(party.cooldown_fraction(m, 7, 6000), 0.0, "no such slot")
	wall += 1500
	assert_almost_eq(party.cooldown_fraction(m, 1, 6000), 0.25, 0.001, "and it drains as the wall clock runs")


func test_clear_drops_everything():
	party.apply_update({"partyId": 7, "leaderId": 2, "members": [_member(1, "Ruu"), _member(2, "Mingau")]})
	party.clear()
	assert_false(party.in_party())


func test_the_realm_state_routes_the_packet_and_resets_it():
	var state := RealmState.new(null, func() -> int: return now)
	state.apply_packet("PartyUpdatePacket", {"partyId": 7, "leaderId": 2, "members": [_member(1, "Ruu"), _member(2, "Mingau")]})
	assert_true(state.party.in_party())
	state.reset_world()
	assert_false(state.party.in_party())
