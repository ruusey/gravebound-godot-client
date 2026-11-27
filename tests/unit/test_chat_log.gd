extends GutTest

## What the server and the other players said, and the panel that shows it.

var state: RealmState
var panel: ChatPanel
var now := 5000


func before_each():
	state = RealmState.new(null, func() -> int: return now)
	panel = ChatPanel.new()
	panel.setup(state)
	add_child_autofree(panel)


func _said(from: String, message: String, to := "") -> void:
	state.apply_packet("TextPacket", {"from": from, "to": to, "message": message})


## The order the server actually produces on a transition: the tiles, then our
## position, and only then the name -- `sendImmediateLoadMap` is followed by
## `onPlayerJoin`, and it is onPlayerJoin that writes the name. A test that
## sends the name first proves nothing, because that never happens.
func _server_moves_us_to(zone: String) -> void:
	state.apply_packet("LoadMapPacket", {"realmId": 9, "mapId": 31,
		"tiles": [WireHelper.tile(1, 0, 0, 0)]})
	state.apply_packet("ObjectMovePacket", {"movements": [{
		"entityType": GameConstants.ENTITY_PLAYER, "entityId": state.local.id,
		"posX": 100.0, "posY": 100.0, "velX": 0.0, "velY": 0.0, "flags": 0}]})
	_said("SYSTEM", zone, "Ruu")


# --- the log ---------------------------------------------------------------

func test_a_line_is_stored_whole():
	_said("Mingau", "anyone running the beach?", "Ruu")
	var line: Dictionary = state.chat.lines[0]
	assert_eq(line["from"], "Mingau")
	# Dual-purposed by the server: a recipient on a SYSTEM line, the sender's
	# own chat role on a player line. It is not a "who was this for" field.
	assert_eq(line["to"], "Ruu")
	assert_eq(line["message"], "anyone running the beach?")
	assert_eq(line["at_ms"], now)


func test_the_cap_is_the_one_both_references_use():
	# Spelled out: an uncapped log is what the web client's comment blames for
	# 2-5 ms of layout per frame, which lands as reconciliation desync.
	assert_eq(ChatLog.MAX_LINES, 150)


func test_the_oldest_lines_go_first():
	for i in ChatLog.MAX_LINES + 10:
		_said("Ruu", "line %d" % i)
	assert_eq(state.chat.lines.size(), ChatLog.MAX_LINES)
	assert_eq(state.chat.lines[0]["message"], "line 10", "the first ten are gone")
	assert_eq(state.chat.lines[-1]["message"], "line %d" % (ChatLog.MAX_LINES + 9), "and the newest is kept")


func test_a_line_missing_every_field_is_still_a_line():
	# Nothing is looked up here on purpose: a side effect must never be what
	# stops a line being shown.
	state.apply_packet("TextPacket", {})
	assert_eq(state.chat.lines.size(), 1)
	assert_eq(state.chat.lines[0]["from"], "")
	assert_eq(state.chat.lines[0]["message"], "")


func test_the_server_is_told_apart_by_its_name():
	_said("SYSTEM", "Welcome")
	_said("Ruu", "hi")
	assert_true(ChatLog.is_system(state.chat.lines[0]))
	assert_false(ChatLog.is_system(state.chat.lines[1]))


func test_how_a_line_reads():
	assert_eq(ChatLog.rendered({"from": "SYSTEM", "message": "Welcome"}), "Welcome",
		"the server speaks plainly")
	assert_eq(ChatLog.rendered({"from": "Ruu", "message": "hi"}), "[Ruu]: hi")


func test_the_log_crosses_a_realm_change():
	# The web client keeps it; the native wipes it per realm. AGENTS.md says
	# default to the web client.
	_said("Ruu", "hi")
	state.begin_transition()
	assert_eq(state.chat.lines.size(), 1)


func test_the_log_goes_with_the_session():
	_said("Ruu", "hi")
	state.reset_world()
	assert_eq(state.chat.lines.size(), 0)


func test_the_tail_is_what_the_panel_asks_for():
	for i in 10:
		_said("Ruu", "line %d" % i)
	var tail := state.chat.last(3)
	assert_eq(tail.size(), 3)
	assert_eq(tail[0]["message"], "line 7", "oldest first")
	assert_eq(tail[2]["message"], "line 9")
	assert_eq(state.chat.last(0), [], "and nothing is a legitimate ask")


func test_an_empty_log_has_no_tail():
	assert_eq(state.chat.last(6), [], "which is what the panel asks for before anyone speaks")


func test_the_splash_prefers_the_servers_name_over_the_maps():
	# Both are available on the way out: the map id resolves to a name, and
	# the server has usually sent a better one by then -- and it is the only
	# name an assembled dungeon has, since it shares its parent's map id.
	var content := GameData.new()
	await content.load_from(FileContentSource.new(
		ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	var screen := TransitionScreen.new()
	screen.setup(state, content)
	add_child_autofree(screen)

	state.local.name = "Ruu"
	state.begin_transition()
	screen._process(0.0)
	_server_moves_us_to("Deep Beach")
	screen._process(0.0)
	assert_string_contains(screen._label.text, "Deep Beach",
		"both names are available here -- map 31 resolves to Nexus Auru V1")

	state.begin_transition()
	screen._process(0.0)
	state.apply_packet("LoadMapPacket", {"realmId": 3, "mapId": 31, "tiles": []})
	screen._process(0.0)
	assert_string_contains(screen._label.text, "Nexus Auru V1",
		"and falls back to the map when the server has not said")


# --- naming the realm we are entering --------------------------------------

func test_the_realm_is_named_by_the_line_that_follows_the_tiles():
	# The name lands AFTER the LoadMapPacket, so a capture window that closes
	# when the tiles arrive never sees it.
	state.local.name = "Ruu"
	state.begin_transition()
	_server_moves_us_to("Deep Beach")
	assert_false(state.transition_pending, "the tiles already ended the wait")
	assert_eq(state.transition.zone, "Deep Beach")


func test_a_later_line_does_not_rename_it():
	# The server says more than one thing; the rest are about the realm, not
	# its name.
	state.begin_transition()
	_server_moves_us_to("Deep Beach")
	_said("SYSTEM", "Difficulty 4", "Ruu")
	assert_eq(state.transition.zone, "Deep Beach")


func test_a_player_never_names_the_realm():
	state.begin_transition()
	_said("Mingau", "Deep Beach", "Ruu")
	assert_eq(state.transition.zone, "")


func test_a_global_announcement_never_names_the_realm():
	# "X joined the game" and friends are broadcast with `to` empty, while the
	# name of the realm you just entered is addressed to you. Sent AFTER the
	# tiles, so it is the addressing that rejects this one and not the
	# ordering -- before them, everything is rejected anyway.
	state.begin_transition()
	state.apply_packet("LoadMapPacket", {"realmId": 9, "mapId": 31,
		"tiles": [WireHelper.tile(1, 0, 0, 0)]})
	_said("SYSTEM", "Mingau joined the game")
	assert_eq(state.transition.zone, "")
	_said("SYSTEM", "Deep Beach", "Ruu")
	assert_eq(state.transition.zone, "Deep Beach",
		"and we take it even before we have been told our own name")


func test_the_wait_for_a_name_ends_with_everything_else():
	# The window outlasts both flags on purpose, so it needs the same bound.
	# Reached only once the tiles AND the position have landed -- until then
	# the other two keep the timeout alive and this clause never decides.
	state.local.id = 5
	state.local.name = "Ruu"
	state.begin_transition()
	state.apply_packet("LoadMapPacket", {"realmId": 9, "mapId": 31,
		"tiles": [WireHelper.tile(1, 0, 0, 0)]})
	state.apply_packet("ObjectMovePacket", {"movements": [{
		"entityType": GameConstants.ENTITY_PLAYER, "entityId": 5,
		"posX": 10.0, "posY": 10.0, "velX": 0.0, "velY": 0.0, "flags": 0}]})
	assert_false(state.transition_pending)
	assert_false(state.transition.awaiting_snap, "both already settled")

	now += RealmTransition.MAX_WAIT_MS + 1
	state.advance(0.1, Vector2.ZERO, 0.0)
	_said("SYSTEM", "You have been granted a gift", "Ruu")
	assert_eq(state.transition.zone, "", "that window closed with the rest")


func test_a_name_that_never_comes_gives_up_with_the_rest():
	state.local.id = 5
	state.begin_transition()
	now += RealmTransition.MAX_WAIT_MS + 1
	state.advance(0.1, Vector2.ZERO, 0.0)
	_said("SYSTEM", "Deep Beach", "Ruu")
	assert_eq(state.transition.zone, "", "that window closed")


func test_nothing_is_named_outside_a_wait():
	_said("SYSTEM", "Deep Beach", "Ruu")
	assert_eq(state.transition.zone, "")


func test_the_next_wait_starts_unnamed():
	state.begin_transition()
	_server_moves_us_to("Deep Beach")
	state.begin_transition()
	assert_eq(state.transition.zone, "")


func test_an_event_marker_is_not_chat():
	# A minimap payload in a chat packet's clothes, rebroadcast every three
	# seconds while a realm event runs. Stored, it evicts real conversation
	# from the log six lines at a time.
	# The literal, not the constant: driven through ChatLog.EVENT_MARKER this
	# passes whatever the constant says.
	_said("EVENT_MARKER", "ADD|3|9987|4032|2176|Skull Shrine", "Ruu")
	assert_eq(state.chat.lines.size(), 0)
	_said("Ruu", "hi")
	assert_eq(state.chat.lines.size(), 1, "and ordinary chat still lands")


func test_the_compact_line_count_is_what_the_panel_shows():
	assert_eq(ChatPanel.COMPACT_LINES, 6)


func test_a_blanked_panel_redraws_its_lines():
	_said("Ruu", "hi")
	panel._process(0.1)
	panel.blank()
	assert_false(panel._rows[0].visible, "blanked")
	panel._process(0.1)
	assert_eq(panel._rows[0].get_parsed_text(), "[Ruu]: hi")


# --- the panel -------------------------------------------------------------

func test_the_panel_keeps_the_whole_log_oldest_at_the_top():
	# Every line goes into the scrollback; the viewport's height decides how
	# many show at once.
	for i in ChatPanel.COMPACT_LINES + 3:
		_said("Ruu", "line %d" % i)
	panel.refresh()
	assert_eq(panel._rows.size(), ChatPanel.COMPACT_LINES + 3)
	assert_eq(panel._rows[0].get_parsed_text(), "[Ruu]: line 0")
	assert_eq(panel._rows[-1].get_parsed_text(), "[Ruu]: line %d" % (ChatPanel.COMPACT_LINES + 2))


func test_a_row_is_made_per_line_and_a_blanked_one_hides():
	_said("Ruu", "hi")
	panel.refresh()
	assert_eq(panel._rows.size(), 1, "no empty rows pushing the log up")
	assert_eq(panel._rows[0].get_parsed_text(), "[Ruu]: hi")
	assert_true(panel._rows[0].visible)
	panel._rows[0].blank()
	assert_eq(panel._rows[0].get_parsed_text(), "")
	assert_false(panel._rows[0].visible, "hidden, or its empty height pushes the log up")


func test_the_server_reads_differently_from_a_player():
	_said("SYSTEM", "Welcome")
	_said("Ruu", "hi")
	panel.refresh()
	assert_eq(panel._rows[0].get_theme_color("default_color"), ChatRow.SYSTEM_COLOUR)
	assert_eq(panel._rows[1].get_theme_color("default_color"), ChatRow.PLAYER_COLOUR)


func test_a_senders_name_takes_the_role_the_server_put_in_to():
	# The server writes the sender's chat role into `to` on a player line; the
	# name is that role's colour and what they said is the line's own.
	_said("Zed", "hi", "sysadmin")
	_said("Ruu", "hello")
	_said("Overseer", "The realm is closing")
	panel.refresh()
	assert_eq(panel._rows[0].get_parsed_text(), "[Zed]: hi")
	assert_eq(panel._rows[0].text, "[color=#ff4040][lb]Zed][/color]: hi", "red, the sysadmin's")
	assert_eq(panel._rows[1].text, "[color=#4080e0][lb]Ruu][/color]: hello",
		"no role is the chat log's blue, not the off-white over a head")
	assert_eq(panel._rows[2].text, "[color=#e8c840][lb]Overseer][/color]: The realm is closing")


func test_nothing_typed_into_chat_can_open_a_tag():
	_said("[b]Zed", "[color=red]not red[/color] [url]x[/url]", "admin")
	panel.refresh()
	assert_eq(panel._rows[0].get_parsed_text(), "[[b]Zed]: [color=red]not red[/color] [url]x[/url]",
		"every bracket drawn as itself")


func test_the_panel_shows_nothing_without_a_state():
	var bare := ChatPanel.new()
	add_child_autofree(bare)
	bare._process(0.1)
	assert_eq(bare._rows.size(), 0)


func test_the_panel_only_repaints_what_changed():
	_said("Ruu", "hi")
	panel._process(0.1)
	panel._rows[0].text = "scribbled over"
	panel._process(0.1)
	assert_eq(panel._rows[0].get_parsed_text(), "scribbled over", "no new line, no rebuild")
	_said("Ruu", "again")
	panel._process(0.1)
	assert_eq(panel._rows[0].get_parsed_text(), "scribbled over", "an unchanged line's row is left alone")
	assert_eq(panel._rows[1].get_parsed_text(), "[Ruu]: again", "and the new line is drawn")


func test_a_refusal_never_becomes_the_caption():
	# A purifying realm or a full dungeon sends its apology and returns --
	# no tiles, no name. Taking the first SYSTEM line of the wait puts the
	# whole sentence on the splash behind the word "Entering".
	state.local.name = "Ruu"
	state.begin_transition()
	_said("SYSTEM", "This realm has been purified - you cannot enter now.", "Ruu")
	assert_eq(state.transition.zone, "")
	assert_true(state.transition_pending, "still waiting, because no tiles came")


func test_a_line_addressed_to_someone_else_is_about_them():
	state.local.name = "Ruu"
	state.begin_transition()
	state.apply_packet("LoadMapPacket", {"realmId": 9, "mapId": 31,
		"tiles": [WireHelper.tile(1, 0, 0, 0)]})
	_said("SYSTEM", "Mingau has died", "Mingau")
	assert_eq(state.transition.zone, "")
	_said("SYSTEM", "Deep Beach", "Ruu")
	assert_eq(state.transition.zone, "Deep Beach")


func test_a_name_that_never_comes_stops_being_waited_for():
	# The window outlasts the tiles on purpose, so it needs the same bound as
	# the flags it outlasts, or the next stray SYSTEM line inherits it.
	state.local.name = "Ruu"
	state.local.id = 5
	state.begin_transition()
	state.apply_packet("LoadMapPacket", {"realmId": 9, "mapId": 31, "tiles": []})
	now += RealmTransition.MAX_WAIT_MS + 1
	state.advance(0.1, Vector2.ZERO, 0.0)
	_said("SYSTEM", "You have been granted a gift", "Ruu")
	assert_eq(state.transition.zone, "")


func test_the_last_tell_received_is_who_a_reply_goes_to():
	var log := ChatLog.new()
	assert_eq(log.last_whisper_from, "", "nobody has messaged us yet")
	log.apply_text({"from": "Gharr", "to": ChatLog.WHISPER_IN, "message": "hi"})
	log.apply_text({"from": "Mira", "to": ChatLog.WHISPER_IN, "message": "yo"})
	log.apply_text({"from": "Tess", "to": "WHISPER_OUT", "message": "our own echo"})
	log.apply_text({"from": "Bram", "to": "", "message": "said in the open"})
	assert_eq(log.last_whisper_from, "Mira", "only a received tell counts, the latest one")
	log.clear()
	assert_eq(log.last_whisper_from, "", "gone with the session")
