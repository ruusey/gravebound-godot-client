class_name ServerSelect
extends VBoxContainer

## Server picker for the login screen. Fetches the registered game servers from
## the data service (GET /servers), lists them in a dropdown with a measured
## latency next to each, and applies the chosen one to the ClientConfig so the
## next connect dials it. Hidden (a no-op) when /servers is empty or unreachable,
## so the client falls back to its compiled-in default route.
##
## Latency is each server's HTTP ping round trip (ServerPing): one request on
## a warm connection, never the connect, TLS or socket upgrade.

## A direct-to-localhost entry pinned to the bottom of the list, so a locally
## run server is reachable without a /servers registry. `local` tells the login
## screen to dial the raw listener directly (no proxy route, no TLS) rather than
## the wss ingress path the registered nodes use.
const LOCAL_SERVER := {"name": "Local (127.0.0.1)", "host": "127.0.0.1", "webSocketPort": 2223, "local": true}

var data_service: DataService
## Called with the chosen server Dictionary when the selection changes (and once
## for the default on load). The screen uses it to mutate its ClientConfig.
var apply_server: Callable

var _dropdown: OptionButton
var _heading: Label
var _servers: Array = []
# Parallel to _servers: a ServerPing each, null once it has been shown.
var _pings: Array = []


func _init(service: DataService, on_apply: Callable) -> void:
	data_service = service
	apply_server = on_apply


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_heading = HudWidgets.label("Server", 12, PlayerHud.GOLD)
	add_child(_heading)
	_dropdown = OptionButton.new()
	_dropdown.item_selected.connect(_on_selected)
	add_child(_dropdown)
	visible = false
	set_process(false)
	_load()



## The dropdown alone: its entries already say they are servers.
func compact() -> void:
	_heading.visible = false

func _load() -> void:
	var response: Dictionary = await data_service.send(HTTPClient.METHOD_GET, "/servers", "", false)
	var fetched: Array = []
	if response.get("ok", false) and response.get("body") is Array:
		fetched = response.get("body")
	# Always offer the direct localhost connection at the bottom, even when the
	# registry is empty/unreachable (a purely local server has no /servers list).
	_servers = fetched.duplicate()
	_servers.append(LOCAL_SERVER)
	_dropdown.clear()
	_pings.clear()
	for server in _servers:
		_dropdown.add_item(_label(server, "..."))
		_pings.append(null)
	visible = true
	_dropdown.select(0)
	# Only auto-apply when a registered server leads the list; if the fetch failed
	# and Local is the only entry, leave the compiled-in default route in place
	# until the player picks Local themselves.
	if not fetched.is_empty():
		_on_selected(0)
	_start_pings()


func _on_selected(index: int) -> void:
	if index >= 0 and index < _servers.size() and apply_server.is_valid():
		apply_server.call(_servers[index])


func _start_pings() -> void:
	for i in _servers.size():
		var ping := ServerPing.new()
		ping.start(ServerPing.url(_servers[i], data_service.base_url))
		_pings[i] = ping
	set_process(true)


func _process(_delta: float) -> void:
	var pending := 0
	for i in _pings.size():
		var ping: ServerPing = _pings[i]
		if ping == null:
			continue
		var ms := ping.result()
		if ms == ServerPing.PENDING:
			pending += 1
			continue
		_pings[i] = null
		_dropdown.set_item_text(i, _label(_servers[i], "%d ms" % ms if ms >= 0 else "offline"))
	if pending == 0:
		set_process(false)


func _label(server: Dictionary, latency: String) -> String:
	var display := str(server.get("name", "server"))
	return "%s  -  %s" % [display, latency] if latency != "" else display
