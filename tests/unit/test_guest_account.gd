extends GutTest

## The guest account: its credentials, and the flow that registers a brand-new
## one on every press and keeps none.

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
	assert_true(RegEx.create_from_string("^guest_[0-9a-f]{8}@grave-bound\\.com$").search(made["email"]) != null, made["email"])
	assert_true(RegEx.create_from_string("^[0-9a-f]{16}$").search(made["password"]) != null, made["password"])
	assert_true(made["name"] in GuestAccount.NAMES)
	assert_eq(GuestAccount.NAMES.size(), 44, "main.js GUEST_NAMES")
	assert_ne(guest.make()["email"], made["email"], "a second guest is someone else")


## A guest a previous build cached, as it wrote it.
func _old_cache() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(GuestAccount.SECTION, "email", "guest_old@grave-bound.com")
	cfg.set_value(GuestAccount.SECTION, "password", "pw")
	cfg.save(PATH)


func test_forget_drops_an_old_cache_and_forgetting_nothing_is_fine():
	_old_cache()
	assert_true(FileAccess.file_exists(PATH))
	guest.forget()
	assert_false(FileAccess.file_exists(PATH))
	guest.forget()
	assert_false(FileAccess.file_exists(PATH), "forgetting nothing is fine")


func test_a_press_registers_a_fresh_guest_and_keeps_nothing():
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
	assert_false(FileAccess.file_exists(PATH), "the credentials are shown, never stored")


func test_every_press_is_a_new_guest():
	backend.push_json(200, {"accountGuid": "g1"})
	backend.push_json(200, {"accountGuid": "g2"})
	var first: Dictionary = await guest.obtain(service)
	var second: Dictionary = await guest.obtain(service)
	assert_ne(first["email"], second["email"])
	assert_eq(backend.requests.size(), 2)
	for request in backend.requests:
		assert_string_ends_with(request["url"], "/admin/account/register")


func test_an_old_builds_cached_guest_is_cleared_and_never_signed_in():
	_old_cache()
	backend.push_json(200, {"accountGuid": "g"})
	var got: Dictionary = await guest.obtain(service)
	assert_ne(got["email"], "guest_old@grave-bound.com")
	assert_false(FileAccess.file_exists(PATH))
	assert_eq(backend.requests.size(), 1, "no login with the old credentials")
	assert_string_ends_with(backend.requests[0]["url"], "/admin/account/register")


func test_a_refused_registration_is_reported():
	backend.push_json(500, {"reason": "Failed to register account"})
	var got: Dictionary = await guest.obtain(service)
	assert_false(got["success"])
	assert_string_contains(str(got["result"]), "Failed to register account")
	assert_false(FileAccess.file_exists(PATH))
