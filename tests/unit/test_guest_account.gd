extends GutTest

## The guest account: its credentials, where they are kept, and the flow
## that reuses a kept one or registers a new one.

const PATH := "user://test_guest.cfg"

var guest: GuestAccount
var service: DataService
var backend: FakeHttpBackend


func before_each():
	guest = GuestAccount.new()
	guest.path = PATH
	guest.rng.seed = 42
	guest.forget()
	backend = FakeHttpBackend.new()
	service = DataService.new()
	service.backend = backend
	service.base_url = "http://data.test"
	add_child_autofree(service)


func after_each():
	guest.forget()


func _body(request: int) -> Dictionary:
	return JSON.parse_string(backend.requests[request]["body"])


func test_made_credentials_look_like_the_web_clients():
	var made := guest.make()
	assert_true(RegEx.create_from_string("^guest_[0-9a-f]{8}@gravebound\\.net$").search(made["email"]) != null, made["email"])
	assert_true(RegEx.create_from_string("^[0-9a-f]{16}$").search(made["password"]) != null, made["password"])
	assert_true(made["name"] in GuestAccount.NAMES)
	assert_eq(GuestAccount.NAMES.size(), 44, "main.js GUEST_NAMES")
	assert_ne(guest.make()["email"], made["email"], "a second guest is someone else")


func test_kept_credentials_survive_and_forget_drops_them():
	assert_eq(guest.saved(), {})
	guest.save({"email": "a@b.c", "password": "pw"})
	var again := GuestAccount.new()
	again.path = PATH
	assert_eq(again.saved(), {"email": "a@b.c", "password": "pw"}, "read back by a new instance")
	guest.forget()
	assert_eq(guest.saved(), {})
	guest.forget()
	assert_eq(guest.saved(), {}, "forgetting nothing is fine")


func test_a_first_press_registers_a_guest_and_keeps_it():
	backend.push_json(200, {"accountGuid": "g"})
	var got: Dictionary = await guest.obtain(service)
	assert_true(got["success"])
	assert_true(got["created"])
	assert_eq(backend.requests.size(), 1)
	assert_string_ends_with(backend.requests[0]["url"], "/admin/account/register")
	var body := _body(0)
	assert_eq(body["guest"], true)
	assert_eq(body["email"], got["email"])
	assert_eq(body["password"], got["password"])
	assert_true(body["accountName"] in GuestAccount.NAMES)
	assert_eq(body["accountProvisions"], [])
	assert_eq(guest.saved(), {"email": got["email"], "password": got["password"]})


func test_a_kept_guest_that_still_signs_in_is_reused():
	guest.save({"email": "guest_1@grave-bound.com", "password": "pw"})
	backend.push_json(200, {"accountGuid": "g", "token": "t"})
	var got: Dictionary = await guest.obtain(service)
	assert_eq(got, {"success": true, "email": "guest_1@grave-bound.com", "password": "pw", "created": false})
	assert_string_ends_with(backend.requests[0]["url"], "/admin/account/login")
	assert_eq(backend.requests.size(), 1, "nothing registered")


func test_a_kept_guest_that_no_longer_signs_in_is_replaced():
	guest.save({"email": "guest_old@grave-bound.com", "password": "pw"})
	backend.push_json(401, {"reason": "bad credentials"})
	backend.push_json(200, {"accountGuid": "g2"})
	var got: Dictionary = await guest.obtain(service)
	assert_true(got["created"])
	assert_ne(got["email"], "guest_old@grave-bound.com")
	assert_eq(guest.saved()["email"], got["email"], "the new one is kept instead")


func test_a_refused_registration_is_reported_and_nothing_is_kept():
	backend.push_json(500, {"reason": "Failed to register account"})
	var got: Dictionary = await guest.obtain(service)
	assert_false(got["success"])
	assert_string_contains(str(got["result"]), "Failed to register account")
	assert_eq(guest.saved(), {})


func test_a_kept_guest_that_no_longer_signs_in_is_dropped_even_if_no_new_one_can_be_made():
	guest.save({"email": "guest_old@grave-bound.com", "password": "pw"})
	backend.push_json(401, {"reason": "bad credentials"})
	backend.push_json(500, {"reason": "Failed to register account"})
	var got: Dictionary = await guest.obtain(service)
	assert_false(got["success"])
	assert_eq(guest.saved(), {}, "the dead credentials are not tried again next time")
