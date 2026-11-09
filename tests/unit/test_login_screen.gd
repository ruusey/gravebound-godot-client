extends GutTest

## LoginScreen drives the data service and hands a chosen character upward.

var screen: LoginScreen
var service: DataService
var backend: FakeHttpBackend
var data: GameData


func before_each():
	backend = FakeHttpBackend.new()
	service = DataService.new()
	service.backend = backend
	service.base_url = "http://data.test"
	add_child_autofree(service)

	data = GameData.new()
	await data.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))

	screen = LoginScreen.new()
	screen.data_service = service
	screen.game_data = data
	add_child_autofree(screen)
	watch_signals(screen)


const ACCEPTED := {"currentVersion": 1, "acceptedVersion": 1, "needsAcceptance": false}


func _sign_in(characters: Array) -> void:
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	backend.push_json(200, ACCEPTED)
	backend.push_json(200, {"characters": characters})
	screen.prefill("me@example.com", "pw")
	await screen._on_login_pressed()


func test_prefill_populates_the_form():
	screen.prefill("a@b.c", "secret")
	assert_eq(screen._form.email.text, "a@b.c")
	assert_eq(screen._form.password.text, "secret")


func test_status_line_switches_colour_for_errors():
	screen.set_status("all good")
	assert_eq(screen._status.text, "all good")
	screen.set_status("broken", true)
	assert_eq(screen._status.text, "broken")


func test_empty_email_is_rejected_without_a_request():
	screen.prefill("   ", "pw")
	await screen._on_login_pressed()
	assert_eq(backend.requests.size(), 0)
	assert_string_contains(screen._status.text, "Enter an email")


func test_successful_sign_in_lists_characters():
	await _sign_in([
		{"characterUuid": "c1", "characterClass": 0, "stats": {"hp": 200, "spd": 15}},
		{"characterUuid": "c2", "characterClass": 2, "stats": {"hp": 300, "spd": 20}},
	])
	assert_true(screen._stage.picker.visible)
	assert_true(screen._stage.play_button.visible)
	assert_eq(screen._stage.picker.list.item_count, 2)
	assert_string_contains(screen._stage.picker.list.get_item_text(0), "Barbarian")
	assert_string_contains(screen._stage.picker.list.get_item_text(1), "Wizard")
	assert_eq(screen._stage.picker.list.get_selected_items(), PackedInt32Array([0]), "first is preselected")


func test_the_dead_are_on_the_graveyard_page_and_cannot_be_played():
	await _sign_in([
		{"characterUuid": "c1", "characterClass": 0, "stats": {"hp": 200, "spd": 15}},
		{"characterUuid": "c2", "characterClass": 2, "stats": {"hp": 300, "spd": 20},
			"deleted": "2026-09-22T05:59:19.824+00:00"},
		{"characterUuid": "c3", "characterClass": 0, "stats": {}, "deleted": null},
	])
	var picker := screen._stage.picker
	assert_eq(picker.tabs.get_tab_title(0), "Characters (2)", "a null deleted is a living character")
	assert_eq(picker.tabs.get_tab_title(1), "Graveyard (1)")
	assert_eq(picker.tabs.current_tab, CharacterPicker.ALIVE, "opens on the living")
	assert_eq(picker.list.item_count, 2)
	picker.tabs.current_tab = CharacterPicker.GRAVEYARD
	assert_eq(picker.list.item_count, 1)
	assert_string_contains(picker.list.get_item_text(0), "Wizard")
	assert_string_contains(picker.list.get_item_text(0), "died 2026-09-22", "the day, as the native client shows it")
	screen._stage.play()
	assert_signal_not_emitted(screen, "character_chosen", "a dead character is never handed up")
	assert_string_contains(screen._status.text, "living character")
	picker.tabs.current_tab = CharacterPicker.ALIVE
	picker.list.select(1)
	screen._stage.play()
	assert_signal_emitted_with_parameters(screen, "character_chosen", ["me@example.com", "pw", "c3"])


func test_an_account_with_only_the_dead_opens_on_the_graveyard():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}, "deleted": "2026-01-01T00:00:00Z"}])
	assert_true(screen._stage.picker.visible, "still worth a look")
	assert_eq(screen._stage.picker.tabs.current_tab, CharacterPicker.GRAVEYARD)
	assert_false(screen._stage.play_button.visible)
	assert_true(screen._stage.creator.visible, "a class can still be made")
	assert_string_contains(screen._status.text, "pick a class below")


func test_character_list_tolerates_missing_stats():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0}])
	assert_string_contains(screen._stage.picker.list.get_item_text(0), "?")


func test_character_list_without_game_data_shows_class_ids():
	screen.game_data = null
	await _sign_in([{"characterUuid": "c1", "characterClass": 7, "stats": {}}])
	assert_string_contains(screen._stage.picker.list.get_item_text(0), "class 7")


func test_after_a_death_the_account_comes_back_without_signing_in_again():
	await _sign_in([{"characterUuid": "c1", "characterClass": 2, "stats": {"classId": 2}}])
	screen.visible = false
	var before := backend.requests.size()
	backend.push_json(200, {"characters": [
		{"characterUuid": "c1", "characterClass": 2, "stats": {"classId": 2}, "deleted": "2026-09-23T10:00:00"},
		{"characterUuid": "c2", "characterClass": 0, "stats": {"classId": 0}}]})
	await screen.return_after_death()
	var sent: Array = backend.requests.slice(before)
	assert_eq(sent.size(), 1, "the account alone, no second sign-in")
	assert_string_ends_with(sent[0]["url"], "/data/account/g")
	assert_eq(sent[0]["method"], HTTPClient.METHOD_GET)
	assert_true(screen.visible)
	assert_eq(screen._stage.picker.alive_count(), 1, "the living one to pick")
	assert_eq(screen._stage.picker.dead_count(), 1, "and the fallen one in the graveyard")
	assert_string_contains(screen._status.text, "Pick a character")


func test_after_a_death_a_lost_session_falls_back_to_signing_in():
	await _sign_in([{"characterUuid": "c1", "characterClass": 2, "stats": {"classId": 2}}])
	backend.push_json(401, {"reason": "expired"})
	await screen.return_after_death()
	assert_eq(screen._stage.picker.alive_count(), 0, "nothing stale left to pick")
	assert_false(screen._stage.picker.visible)
	assert_string_contains(screen._status.text, "Sign in to choose another")
	assert_false(screen._form.button.disabled, "and the form is usable")


func test_rejected_sign_in_shows_the_reason_and_re_enables():
	backend.push_json(401, {"reason": "bad password"})
	screen.prefill("a@b.c", "nope")
	await screen._on_login_pressed()
	assert_string_contains(screen._status.text, "bad password")
	assert_false(screen._form.button.disabled, "the form is usable again")
	assert_false(screen._stage.picker.visible)


func test_character_fetch_failure_is_reported():
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	backend.push_json(200, ACCEPTED)
	backend.push_json(500, {"reason": "database down"})
	screen.prefill("a@b.c", "pw")
	await screen._on_login_pressed()
	assert_string_contains(screen._status.text, "character list could not be loaded")


func test_account_with_no_characters_is_explained():
	await _sign_in([])
	assert_string_contains(screen._status.text, "No characters yet")
	assert_false(screen._stage.play_button.visible)
	assert_false(screen._stage.picker.visible, "an empty list is not shown")
	assert_true(screen._stage.creator.visible, "the class grid is the way in")
	assert_eq(screen._stage.creator.options.size(), 2, "filled from the content on sign-in")


func test_play_without_a_selection_is_rejected():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}}])
	screen._stage.picker.list.deselect_all()
	screen._stage.play()
	assert_signal_not_emitted(screen, "character_chosen")
	assert_string_contains(screen._status.text, "Pick a living character")


func test_play_emits_the_chosen_character():
	await _sign_in([
		{"characterUuid": "c1", "characterClass": 0, "stats": {}},
		{"characterUuid": "c2", "characterClass": 2, "stats": {}},
	])
	screen._stage.picker.list.select(1)
	screen._stage.play()
	assert_signal_emitted_with_parameters(screen, "character_chosen", ["me@example.com", "pw", "c2"])


func test_double_clicking_a_character_enters_the_realm():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}}])
	screen._stage.picker.list.item_activated.emit(0)
	assert_signal_emitted(screen, "character_chosen")


func test_submitting_the_password_field_signs_in():
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	backend.push_json(200, ACCEPTED)
	backend.push_json(200, {"characters": []})
	screen.prefill("a@b.c", "pw")
	screen._form.password.text_submitted.emit("pw")
	await wait_process_frames(2)
	assert_gt(backend.requests.size(), 0, "enter in the password field submits the form")


# --- creation ---------------------------------------------------------------

func _pick_class(class_id: int) -> void:
	screen._stage.creator.options[class_id].button_pressed = true


func test_signing_in_shows_the_class_grid_under_the_list():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}}])
	assert_true(screen._stage.creator.visible)
	assert_true(screen._stage.creator.play_button.disabled, "nothing picked yet")


func test_create_refills_the_list_and_selects_the_new_character():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}}])
	_pick_class(2)
	backend.push_json(200, {"characters": [
		{"characterUuid": "c1", "characterClass": 0, "stats": {}},
		{"characterUuid": "c2", "characterClass": 2, "stats": {"hp": 100, "spd": 10}},
	]})
	await screen._stage.creator._create(false)
	assert_eq(screen._stage.picker.list.item_count, 2)
	assert_eq(screen._stage.picker.list.get_selected_items(), PackedInt32Array([1]), "the newest is under the cursor")
	assert_string_contains(screen._stage.picker.list.get_item_text(1), "Wizard")
	assert_true(screen._stage.play_button.visible)
	assert_string_contains(screen._status.text, "Character created")
	assert_signal_not_emitted(screen, "character_chosen", "plain Create stays on the screen")


func test_create_and_play_goes_straight_in_on_the_new_character():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}}])
	_pick_class(2)
	backend.push_json(200, {"characters": [
		{"characterUuid": "c1", "characterClass": 0, "stats": {}},
		{"characterUuid": "c2", "characterClass": 2, "stats": {}},
	]})
	await screen._stage.creator._create(true)
	assert_signal_emitted_with_parameters(screen, "character_chosen", ["me@example.com", "pw", "c2"])
	assert_string_contains(screen._status.text, "Connecting")


func test_create_and_play_on_an_empty_account():
	await _sign_in([])
	_pick_class(0)
	backend.push_json(200, {"characters": [{"characterUuid": "new", "characterClass": 0, "stats": {}}]})
	await screen._stage.creator._create(true)
	assert_signal_emitted_with_parameters(screen, "character_chosen", ["me@example.com", "pw", "new"])


func test_create_skips_the_dead_when_choosing_the_newest():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}, "deleted": "2026-01-01T00:00:00Z"}])
	_pick_class(0)
	backend.push_json(200, {"characters": [
		{"characterUuid": "c1", "characterClass": 0, "stats": {}, "deleted": "2026-01-01T00:00:00Z"},
		{"characterUuid": "c2", "characterClass": 0, "stats": {}},
	]})
	await screen._stage.creator._create(true)
	assert_signal_emitted_with_parameters(screen, "character_chosen", ["me@example.com", "pw", "c2"])


func test_a_rejected_create_shows_the_reason():
	await _sign_in([])
	_pick_class(0)
	backend.push_json(400, {"reason": "Character limit reached (15 max)"})
	await screen._stage.creator._create(true)
	assert_string_contains(screen._status.text, "Character limit reached (15 max)")
	assert_signal_not_emitted(screen, "character_chosen")
	assert_eq(screen._stage.creator.selected_class_id(), 0, "the pick is kept for a retry")


func test_forgetting_characters_hides_the_class_grid_too():
	await _sign_in([{"characterUuid": "c1", "characterClass": 0, "stats": {}}])
	screen.forget_characters("gone")
	assert_false(screen._stage.creator.visible)
	assert_false(screen._stage.picker.visible)
	assert_true(screen.visible)


func _guest_path() -> void:
	screen._form.guest.path = "user://test_login_guest.cfg"
	screen._form.guest.forget()


func test_play_as_guest_registers_signs_in_and_shows_the_credentials_once():
	_guest_path()
	assert_false(screen._form.guest_notice.visible)
	backend.push_json(200, {"accountGuid": "g"})
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	backend.push_json(200, ACCEPTED)
	backend.push_json(200, {"characters": []})
	screen._form.guest_button.pressed.emit()
	await wait_process_frames(1)
	var urls: Array = backend.requests.map(func(r: Dictionary) -> String: return r["url"].trim_prefix("http://data.test"))
	assert_eq(urls, ["/admin/account/register", "/admin/account/login", "/admin/account/terms", "/data/account/g"])
	var made: Dictionary = screen._form.guest.saved()
	assert_eq(screen._form.email_text(), made["email"], "the form now holds the guest")
	assert_eq(screen._form.password_text(), made["password"])
	assert_true(screen._form.guest_notice.visible)
	assert_string_contains(screen._form.guest_details.text, made["email"])
	assert_string_contains(screen._status.text, "pick a class below", "a guest starts with no characters")
	assert_false(screen._form.guest_button.disabled, "usable again")
	screen._form.guest.forget()


func test_a_returning_guest_just_signs_in():
	_guest_path()
	screen._form.guest.save({"email": "guest_1@grave-bound.com", "password": "pw"})
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	backend.push_json(200, ACCEPTED)
	backend.push_json(200, {"characters": []})
	screen._form.play_as_guest()
	await wait_process_frames(1)
	assert_eq(screen._form.email_text(), "guest_1@grave-bound.com")
	assert_false(screen._form.guest_notice.visible, "shown only when the account is new")
	screen._form.guest.forget()


func test_a_guest_that_cannot_be_made_says_why():
	_guest_path()
	backend.push_json(500, {"reason": "Failed to register account"})
	screen._form.play_as_guest()
	await wait_process_frames(1)
	assert_string_contains(screen._status.text, "Could not make a guest account")
	assert_string_contains(screen._status.text, "Failed to register account")
	assert_false(screen._form.button.disabled)
	assert_eq(backend.requests.size(), 1, "no sign-in attempted")


func test_register_swaps_in_its_form_and_back_again():
	assert_true(screen._form.sign_in.visible)
	assert_false(screen._form.register.visible)
	screen._form.register_link.pressed.emit()
	assert_false(screen._form.sign_in.visible, "the sign-in fields make way")
	assert_true(screen._form.register.visible)
	screen._form.register.back_button.pressed.emit()
	assert_true(screen._form.sign_in.visible)
	assert_false(screen._form.register.visible)
	assert_eq(backend.requests.size(), 0, "nothing sent by looking")


func test_registering_signs_straight_in_to_the_new_accounts_characters():
	screen._form.show_register()
	var form: RegisterForm = screen._form.register
	form.account_name.text = "Newbie"
	form.email.text = "new@example.com"
	form.password.text = "hunter2"
	backend.push_json(200, {"accountGuid": "g"})
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	backend.push_json(200, ACCEPTED)
	backend.push_json(200, {"characters": [{"characterUuid": "c1", "characterClass": 2, "stats": {"classId": 2}}]})
	form.button.pressed.emit()
	await wait_process_frames(1)
	var urls: Array = backend.requests.map(func(r: Dictionary) -> String: return r["url"].trim_prefix("http://data.test"))
	assert_eq(urls, ["/admin/account/register", "/admin/account/login", "/admin/account/terms", "/data/account/g"])
	var body: Dictionary = JSON.parse_string(backend.requests[0]["body"])
	assert_eq([body["email"], body["password"], body["accountName"], body["guest"]],
		["new@example.com", "hunter2", "Newbie", false], "a normal account, not a guest")
	assert_true(screen._form.sign_in.visible, "back on the sign-in side, filled in")
	assert_eq(screen._form.email_text(), "new@example.com")
	assert_string_contains(screen._status.text, "Pick a character", "the starting character is there to pick")


func test_register_says_what_is_missing_before_sending_anything():
	screen._form.show_register()
	var form: RegisterForm = screen._form.register
	form.submit()
	assert_string_contains(screen._status.text, "username")
	form.account_name.text = "Newbie"
	form.email.text = "not-an-email"
	form.submit()
	assert_string_contains(screen._status.text, "email")
	form.email.text = "new@example.com"
	form.submit()
	assert_string_contains(screen._status.text, "password")
	assert_eq(backend.requests.size(), 0)


func test_a_refused_registration_says_why_and_stays_on_the_form():
	screen._form.show_register()
	var form: RegisterForm = screen._form.register
	form.account_name.text = "Newbie"
	form.email.text = "taken@example.com"
	form.password.text = "pw"
	backend.push_json(500, {"reason": "Account already exists"})
	form.submit()
	await wait_process_frames(1)
	assert_string_contains(screen._status.text, "Could not register")
	assert_string_contains(screen._status.text, "Account already exists")
	assert_true(form.visible, "still on the form to fix it")
	assert_false(form.button.disabled)
	assert_eq(backend.requests.size(), 1, "no sign-in attempted")


func test_stats_read_as_whole_numbers_as_the_service_sends_them():
	# The live service's JSON parses to floats; a row once read "hp 130.0".
	var row := {"characterUuid": "c1", "characterClass": 0, "stats": {"hp": 130.0, "spd": 10.0}}
	assert_string_contains(CharacterPicker.describe(row, null), "hp 130  spd 10")
	assert_eq(CharacterPicker.stat_text(539.6), "540", "rounded, not truncated")
	assert_eq(CharacterPicker.stat_text(null), "?", "left out by the service")
	assert_eq(CharacterPicker.stat_text("fast"), "?", "and anything that is not a number")


func test_living_characters_show_the_fame_they_would_bank():
	var content := GameData.new()
	content.levels.parse({"levelExperienceMap": {"1": "0-999", "2": "1000-101482"}})
	var alive := {"characterUuid": "c1", "characterClass": 0, "stats": {"hp": 130.0, "spd": 10.0, "xp": 3601482.0}}
	assert_string_contains(CharacterPicker.describe(alive, content), "fame 1,400")
	var fresh := {"characterUuid": "c2", "characterClass": 0, "stats": {"hp": 100.0, "spd": 10.0, "xp": 500.0}}
	assert_string_contains(CharacterPicker.describe(fresh, content), "fame 0", "below max level: none yet")
	var fallen := alive.merged({"deleted": "2026-09-20T18:00:00Z"})
	assert_false(CharacterPicker.describe(fallen, content).contains("fame"), "the fallen show the day they fell")
