class_name ClientConfig
extends RefCounted

## Runtime configuration. Defaults target a local server plus the data repo
## checked out beside this repo -- gravebound-data is a separate private repo,
## so it lives next to this one rather than inside it; every value can be
## overridden from the command line, e.g.
##
##   godot -- --host=127.0.0.1 --email=me@example.com --password=pw \
##            --character=<uuid> --data-root=/path/to/resources

const DEFAULT_DATA_ROOT := "../../gravebound-data/src/main/resources"
## The route a TLS deployment reaches the game server on, which must match
## what the ingress forwards to the WebSocket listener.
##
## A TLS deployment cannot reach that listener directly: the page is https, an
## https page may not open ws://, and whatever terminated the TLS is listening
## on 443 rather than 2223. So the socket goes through the same origin as
## everything else, on a path the proxy routes.
const INGRESS_PATH := "/ws"
## grave-bound.com's nginx routes one path per game server -- /ws/useast,
## /ws/euwest, /ws/local -- straight from its setup-nginx.sh. US East is the
## one that answers today; the others are a hang and a 502.
const PRODUCTION_INGRESS_PATH := "/ws/useast"
## The game server's two listeners. It speaks the identical protocol on both.
const TCP_PORT := 2222
const WEBSOCKET_PORT := WebSocketTransport.DEFAULT_PORT

var host := "127.0.0.1"
## 0 means "whichever port the chosen transport listens on"; --port overrides.
var port := 0
## A browser cannot open a raw socket, so a web build always talks WebSocket.
## Native builds can be pointed at the same listener with --websocket, which
## is the only way to exercise that path outside an export.
var websocket := false
## Same reasoning as `websocket`, for the same reason: no filesystem either.
var content_http := false
## The proxy route to the game server, or "" to dial its listener directly.
## See INGRESS_PATH for why a TLS deployment needs one.
var socket_path := ""
## Whether the page was served over TLS. A browser will not let an https page
## open an insecure socket or fetch over plain http, so this decides both
## schemes; it is derived from the page and never guessed.
var secure := false
## The data service listens on 80 in the deployed setup (behind nginx), but a
## local container usually publishes it somewhere unprivileged.
var data_port := 8080
var email := ""
var password := ""
var character_uuid := ""
var token := ""
var data_root := DEFAULT_DATA_ROOT
var autoconnect := true
## One-way delay to add to every byte, and its jitter, for meeting a distant
## server on loopback; 0 is the real socket.
var lag_ms := 0.0
var lag_jitter_ms := 0.0
## Show the phone's sticks and buttons here, where there is no touchscreen.
var touch := false
## Render the realm in 3D (walls as boxes, entities billboarded). Prototype,
## behind --3d or the web's ?3d=1; off is the normal 2D client.
var enable_3d := false
## Where the options are kept. Empty -- a test's config -- keeps nothing.
var settings_path := ""


static func from_command_line() -> ClientConfig:
	var config := parse(OS.get_cmdline_user_args())
	config.settings_path = GameSettings.DEFAULT_PATH
	return config


## `on_web` and `origin` are parameters rather than direct queries so the
## browser's behaviour -- including which of the two wins when both name a
## host -- is reachable from a test running on the desktop. `on_app`, an
## Android build, has no page and no command line and is always what a page
## on the production domain is: grave-bound.com over TLS, socket and content
## the browser's way, since no 127.0.0.1 or data repo exists on a phone.
static func parse(args: PackedStringArray, on_web := OS.has_feature("web"),
		origin := PageOrigin.current(), on_app := OS.has_feature("android")) -> ClientConfig:
	if on_app:
		on_web = true
		origin = {"host": PageOrigin.PRODUCTION_HOST, "port": 0, "secure": true}
	# A shipped desktop build (Windows/Linux) has no page to read an origin from,
	# so it would otherwise keep the 127.0.0.1 dev default and fail to load game
	# data. Point it at prod the same way Android/web-on-grave-bound.com do (socket
	# + content over TLS through nginx). Editor and unversioned dev builds keep the
	# local default; an explicit --host still overrides below.
	elif not on_web and _is_released_build():
		on_web = true
		origin = {"host": PageOrigin.PRODUCTION_HOST, "port": 0, "secure": true}
	var config := ClientConfig.new()
	config.websocket = on_web
	config.content_http = on_web
	# Before the arguments, so an explicit --host still overrides it.
	if on_web:
		# Loud, because the fallback is the desktop default and a page that
		# fetches from 127.0.0.1 is otherwise a mystery in a browser console.
		if origin.is_empty():
			push_warning("ClientConfig: the page gave no origin; falling back to %s" % config.host)
		PageOrigin.apply(config, origin)
		# Printed on purpose: in a browser this line is the only account of
		# where the client decided to connect, and it is what to read first.
		print("[page] origin %s -> %s" % [origin, ServerAddress.data_url(config)])
		# A page served over TLS is behind a proxy by definition -- nothing
		# else could have terminated it -- so the socket needs that proxy's
		# route. A browser cannot be passed a flag, so this is the default and
		# INGRESS_PATH is the one place to change it.
		if config.secure:
			config.socket_path = PRODUCTION_INGRESS_PATH \
				if PageOrigin.is_production(config.host) else INGRESS_PATH
	for arg in args:
		var pair := arg.trim_prefix("--").split("=", true, 1)
		var key := pair[0]
		var value := pair[1] if pair.size() > 1 else ""
		match key:
			"host": config.host = value
			"port": config.port = int(value)
			"data-port": config.data_port = int(value)
			"email": config.email = value
			"password": config.password = value
			"character": config.character_uuid = value
			"token": config.token = value
			"data-root": config.data_root = value
			"websocket": config.websocket = true
			"content-http": config.content_http = true
			"socket-path": config.socket_path = value
			"no-connect": config.autoconnect = false
			"lag": config.lag_ms = float(value)
			"lag-jitter": config.lag_jitter_ms = float(value)
			"touch": config.touch = true
			"3d": config.enable_3d = true
			_:
				push_warning("ClientConfig: ignoring unknown argument '%s'" % arg)
	return config


## True for a shipped (exported) build: anything that isn't the editor. A packaged
## Windows/Linux EXE has no local data repo or server beside it, so it must target
## prod. This used to also require a CI-stamped application/config/version, but that
## proved unreliable in the export -- the EXE read no version and fell back to the
## 127.0.0.1 + src/main/resources dev defaults. Local dev runs from the editor
## (editor feature present) still keep the local default; an explicit --host on an
## exported build still overrides prod.
static func _is_released_build() -> bool:
	return not OS.has_feature("editor")


## Where content comes from. The data service in a browser, which has no
## filesystem; the data repo on disk otherwise, so local work needs nothing
## running. --content-http forces the service on the desktop, which is the
## only way to exercise the browser's path without an export.
func open_content_source(backend: HttpBackend) -> ContentSource:
	if content_http:
		return HttpContentSource.new(ServerAddress.data_url(self), backend)
	return FileContentSource.new(resolved_data_root())


## A transport for this configuration. TcpTransport on the desktop; on the web
## there is no choice, which is the whole reason for the flag. Either sits
## inside a LagTransport, passing straight through at no delay, so --lag or
## `/lag` in the chat can meet a distant server on loopback.
func open_transport() -> NetTransport:
	var transport: NetTransport = WebSocketTransport.new() if websocket else TcpTransport.new()
	return LagTransport.new(transport, lag_ms, lag_jitter_ms)


## Resolves data_root against the project directory when it is relative, so the
## default "next to the repo" layout works without an absolute path.
func resolved_data_root() -> String:
	if data_root.is_absolute_path():
		return data_root.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(data_root).simplify_path()
