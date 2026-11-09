class_name DataService
extends Node

## HTTP client for the gravebound-data service.
##
## The game server authenticates against this same service during the login
## handshake, so the client only needs it to discover which characters the
## account owns -- the game server's login requires a characterUuid.
##
##   POST /admin/account/login  {email, password}      -> {accountGuid, token, expires}
##   GET  /data/account/{guid}  Authorization: <token> -> PlayerAccountDto
##   POST /data/account/{guid}/character?classId=N     -> PlayerAccountDto
##   POST /admin/account/register {email, password, accountName, guest, ...}
##   GET  /data/stats/top?count=N  -> [LeaderboardEntryDto]  (LeaderboardRequest)
##   GET  /admin/account/terms, POST /admin/account/terms/accept  (AccountTerms)
##   GET  /data/fame/packages, POST /data/account/{guid}/fame/checkout,
##   GET  /data/account/{guid}/fame/purchases/{sessionId}  (FamePurchasePanel)
##
## The Authorization header carries the raw token, with no Bearer prefix.

signal login_completed(success: bool, result: Variant)
signal characters_completed(success: bool, characters: Array)
signal character_created(success: bool, result: Variant)

var base_url := "http://127.0.0.1"
var account_guid := ""
var token := ""
## The last account DTO fetched (fetch_characters / create_chest), so the vault
## chest count is on hand without a second request.
var account := {}
## Defaults to a real HTTPRequest on first use; tests assign a scripted backend.
var backend: HttpBackend = null


func _ready() -> void:
	_ensure_backend()


## Returns {success, result} as well as emitting login_completed. Callers that
## await the call get the result directly, which avoids the race where a fast
## backend emits before the caller has attached to the signal.
func login(email: String, password: String) -> Dictionary:
	var body := JSON.stringify({"email": email, "password": password})
	var response := await send(HTTPClient.METHOD_POST, "/admin/account/login", body, false)
	if not response["ok"]:
		return _finish_login(false, response["error"])
	var payload = response["body"]
	if not payload is Dictionary or not payload.has("token"):
		return _finish_login(false, "unexpected login response: %s" % str(payload))
	token = str(payload["token"])
	account_guid = str(payload.get("accountGuid", ""))
	return _finish_login(true, payload)


## Returns {success, characters}, and emits characters_completed.
func fetch_characters() -> Dictionary:
	if token == "" or account_guid == "":
		return _finish_characters(false, [])
	var response := await send(HTTPClient.METHOD_GET, "/data/account/%s" % account_guid, "", true)
	if not response["ok"]:
		return _finish_characters(false, [])
	var payload = response["body"]
	if not payload is Dictionary:
		return _finish_characters(false, [])
	account = payload
	return _finish_characters(true, payload.get("characters", []))


## Re-reads the account DTO into `account` (no signals), so an in-game readout can
## refresh its vault count without disturbing the character-list listeners.
func refresh_account() -> void:
	if token == "" or account_guid == "":
		return
	var response := await send(HTTPClient.METHOD_GET, "/data/account/%s" % account_guid, "", true)
	if response["ok"] and response["body"] is Dictionary:
		account = response["body"]


## How many vault chests the account holds, from the last fetched DTO.
func chest_count() -> int:
	var vault: Variant = account.get("playerVault")
	return vault.size() if vault is Array else 0


## Adds a vault chest (POST /chest/new). The service enforces the cap (1 for a
## guest, 50 otherwise) and returns the updated account, so the readout refreshes
## from it. Returns {success, result}; result is the service's reason on failure
## (e.g. "Vault chest limit reached (1 max)").
func create_chest() -> Dictionary:
	if token == "" or account_guid == "":
		return {"success": false, "result": "not signed in"}
	var response := await send(HTTPClient.METHOD_POST,
		"/data/account/%s/chest/new" % account_guid, "", true)
	if not response["ok"]:
		return {"success": false, "result": response["error"]}
	if response["body"] is Dictionary:
		account = response["body"]
	return {"success": true, "result": response["body"]}


## Adds a character of `class_id` to the account, as both references do:
## one POST with the class as a query parameter and no body. The reply is
## the whole account, so the result on success is its character list and
## the picker can be refilled without a second fetch; on failure it is the
## reason -- the service says "Character limit reached (15 max)" itself.
func create_character(class_id: int) -> Dictionary:
	if token == "" or account_guid == "":
		return _finish_created(false, "not signed in")
	var response := await send(HTTPClient.METHOD_POST,
		"/data/account/%s/character?classId=%d" % [account_guid, class_id], "", true)
	if not response["ok"]:
		return _finish_created(false, response["error"])
	var payload = response["body"]
	if not payload is Dictionary:
		return _finish_created(false, "unexpected create response: %s" % str(payload))
	return _finish_created(true, payload.get("characters", []))


## A new account, as the web client's api.register makes one: a guest gets
## the GRAVEBOUND_DEMO provision and an empty account, no character or chest.
## Returns {success, result}, the reason on failure. Signs nothing in.
func register(email: String, password: String, account_name: String, guest: bool) -> Dictionary:
	var body := JSON.stringify({"email": email, "password": password, "accountName": account_name,
		"guest": guest, "accountProvisions": [], "accountSubscriptions": []})
	var response := await send(HTTPClient.METHOD_POST, "/admin/account/register", body, false)
	if not response["ok"]:
		return {"success": false, "result": response["error"]}
	return {"success": true, "result": response["body"]}


## The fame packages on sale, {enabled, currency, packages}; {} on failure.
func fame_packages() -> Dictionary:
	if token == "":
		return {}
	var response := await send(HTTPClient.METHOD_GET, "/data/fame/packages", "", true)
	if response["ok"] and response["body"] is Dictionary:
		return response["body"]
	return {}


## Starts a Stripe Checkout for one package. Returns {success, result}; result
## is {sessionId, url} on success, the service's reason otherwise (a 503 when
## purchases are switched off).
func fame_checkout(package_id: String) -> Dictionary:
	if token == "" or account_guid == "":
		return {"success": false, "result": "not signed in"}
	var body := JSON.stringify({"packageId": package_id})
	var response := await send(HTTPClient.METHOD_POST,
		"/data/account/%s/fame/checkout" % account_guid, body, true)
	if not response["ok"]:
		return {"success": false, "result": response["error"]}
	if not response["body"] is Dictionary:
		return {"success": false, "result": "unexpected checkout response: %s" % str(response["body"])}
	return {"success": true, "result": response["body"]}


## Where a checkout stands: {sessionId, status, fame, packageId, accountFame}.
## Returns {success, result}.
func fame_purchase_status(session_id: String) -> Dictionary:
	if token == "" or account_guid == "":
		return {"success": false, "result": "not signed in"}
	var response := await send(HTTPClient.METHOD_GET,
		"/data/account/%s/fame/purchases/%s" % [account_guid, session_id.uri_encode()], "", true)
	if not response["ok"]:
		return {"success": false, "result": response["error"]}
	if not response["body"] is Dictionary:
		return {"success": false, "result": "unexpected status response: %s" % str(response["body"])}
	return {"success": true, "result": response["body"]}


## Drops the session, as the web client's clearSession does: what a
## refused Terms of Use leaves behind, so nothing signed in lingers.
func sign_out() -> void:
	token = ""
	account_guid = ""


func _finish_login(success: bool, result: Variant) -> Dictionary:
	login_completed.emit(success, result)
	return {"success": success, "result": result}


func _finish_characters(success: bool, characters: Array) -> Dictionary:
	characters_completed.emit(success, characters)
	return {"success": success, "characters": characters}


func _finish_created(success: bool, result: Variant) -> Dictionary:
	character_created.emit(success, result)
	return {"success": success, "result": result}


func headers_for(authenticated: bool) -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if authenticated:
		headers.append("Authorization: %s" % token)
	return headers


## Pure translation of an HTTPRequest completion into {ok, body} / {ok, error}.
static func interpret_response(http_result: int, status: int, body_bytes: PackedByteArray, url: String) -> Dictionary:
	if http_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "%s unreachable (result %d)" % [url, http_result]}

	var text := body_bytes.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if status < 200 or status >= 300:
		var reason := text
		if parsed is Dictionary:
			reason = str(parsed.get("reason", parsed.get("message", text)))
		return {"ok": false, "error": "HTTP %d: %s" % [status, reason]}

	return {"ok": true, "body": parsed}


func _ensure_backend() -> void:
	if backend == null:
		backend = GodotHttpBackend.new(self)


## One request to the service, answered as {ok, body} or {ok, error}. The
## endpoints that live in files of their own go through it too.
func send(method: int, path: String, body: String, authenticated: bool) -> Dictionary:
	_ensure_backend()
	var url := base_url + path
	@warning_ignore("redundant_await")
	var raw: Array = await backend.perform(method, url, headers_for(authenticated), body)
	return interpret_response(raw[0], raw[1], raw[2], base_url)
