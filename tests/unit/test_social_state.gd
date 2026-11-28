extends GutTest

## The friends and guild directory: what SocialStatusPacket fills, how the tabs
## filter it, how the nearby list ranks and colours friends and guild members,
## and the friend and summon wording.

var state: RealmState


func before_each():
	state = RealmState.new(null, func() -> int: return 0)
	state.local.id = 1


func _entry(name: String, flags: int, extra := {}) -> Dictionary:
	var row := {"name": name, "flags": flags, "guildRank": 3, "classId": 2, "level": 12, "dyeId": 0,
		"location": "Nexus", "equipment": [7, -1, -1, -1, -1]}
	row.merge(extra, true)
	return row


func _status(rows: Array) -> void:
	state.apply_packet("SocialStatusPacket", {"entries": rows, "maxFriends": 100})


func test_a_status_fills_the_directory_online_first_then_by_name():
	_status([
		_entry("zed", SocialState.FRIEND | SocialState.ONLINE),
		_entry("amy", SocialState.FRIEND),
		_entry("bob", SocialState.FRIEND | SocialState.GUILD | SocialState.ONLINE | SocialState.SAME_REALM),
		_entry("cat", SocialState.GUILD),
	])
	var social := state.social
	assert_eq(social.max_friends, 100)
	assert_eq(social.entries.map(func(e: Dictionary) -> String: return e["name"]), ["bob", "zed", "amy", "cat"])
	assert_true(social.entries[0]["same_realm"])
	assert_eq(social.entries[0]["equipment"][0], {"itemId": 7}, "item ids become item dicts for the card")
	assert_eq(social.friend_count(), 3)


func test_the_tabs_overlap_and_filter_by_online_and_name():
	_status([
		_entry("bob", SocialState.FRIEND | SocialState.GUILD | SocialState.ONLINE),
		_entry("amy", SocialState.FRIEND),
		_entry("cat", SocialState.GUILD | SocialState.ONLINE),
	])
	var social := state.social
	var names := func(rows: Array) -> Array: return rows.map(func(e: Dictionary) -> String: return e["name"])
	assert_eq(names.call(social.listed(false, SocialState.Filter.ALL)), ["bob", "amy"])
	assert_eq(names.call(social.listed(true, SocialState.Filter.ALL)), ["bob", "cat"], "bob is on both tabs")
	assert_eq(names.call(social.listed(false, SocialState.Filter.ONLINE)), ["bob"])
	assert_eq(names.call(social.listed(false, SocialState.Filter.OFFLINE)), ["amy"])
	assert_eq(names.call(social.listed(true, SocialState.Filter.ALL, "CA")), ["cat"], "search ignores case")
	assert_eq(social.online_count(true), 2)


func test_friends_then_guild_members_lead_the_nearby_list_in_gold_and_green():
	_status([_entry("Guildie", SocialState.GUILD), _entry("Pal", SocialState.FRIEND | SocialState.GUILD)])
	state.apply_packet("LoadPacket", {"players": [WireHelper.player(1, "Me", Vector2.ZERO),
		WireHelper.player(2, "Stranger", Vector2(1, 0)), WireHelper.player(3, "Guildie", Vector2(2, 0)),
		WireHelper.player(4, "Pal", Vector2(3, 0))]})
	var listed := NearbyPlayers.list(state.entities, 1, [], state.social.nearby_rank)
	assert_eq(listed.map(func(p: Dictionary) -> String: return p["name"]), ["Pal", "Guildie", "Stranger"])
	assert_eq(state.social.name_colour("pal", Color.WHITE), NameColours.FRIEND, "a friend in a guild is still gold")
	assert_eq(state.social.name_colour("Guildie", Color.WHITE), NameColours.GUILDMATE)
	assert_eq(state.social.name_colour("Stranger", Color.WHITE), Color.WHITE)


func test_the_directory_survives_a_realm_change():
	_status([_entry("Pal", SocialState.FRIEND)])
	state.reset_world()
	assert_true(state.social.is_friend("Pal"))


func test_friend_and_summon_requests_read_as_prompts_and_notices():
	state.apply_packet("InteractionPacket", {"kind": Interaction.Kind.SUMMON, "event": Interaction.Event.REQUESTED,
		"otherName": "Pal", "detail": "Nexus", "durationMs": 1000})
	assert_eq(state.interactions.prompt(Interaction.Kind.SUMMON), "Pal wants to summon you to Nexus")
	assert_eq(Interaction.notice(Interaction.Kind.FRIEND, Interaction.Event.JOINED, "Pal", ""),
		"You and Pal are now friends.")
	assert_eq(Interaction.notice(Interaction.Kind.FRIEND, Interaction.Event.SENT, "Pal", ""),
		"Friend request sent to Pal.")


func test_the_row_detail_says_where_or_offline():
	var online := {"online": true, "location": "Grasslands", "level": 9, "same_realm": true}
	assert_eq(SocialPanel.detail(online, "Wizard"), "Lv 9 Wizard  -  Grasslands  (here)")
	assert_eq(SocialPanel.detail({"online": false}, "Wizard"), "Offline")
	assert_eq(SocialPanel.empty_text(true, false, SocialState.Filter.ALL, ""), "You are not in a guild.")
