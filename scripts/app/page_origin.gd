class_name PageOrigin
extends RefCounted

## The address the page itself was served from.
##
## A browser has no command line, so --host never reaches a web build and the
## desktop default would point every player at their own machine. The page's
## own origin is the one address that is right by construction: the data
## service serves the client, so it is also where the content comes from.
##
## Only the host, its scheme and its port come from here. The game server's
## WebSocket listener is a port of its own rather than the one the page
## arrived on, so the game port is left alone.
##
## One exception, and it is the whole of the production setup: a page served
## from grave-bound.com (or the legacy openrealm.net) -- the domain or any
## subdomain -- talks to that same host over TLS, whatever the build and
## whatever port the page came from. Anywhere else (localhost, an address, a
## staging box) talks to its own origin, which is what a dev setup expects.

## What a url that names no port of its own implies, per scheme.
const HTTP_PORT := 80
const HTTPS_PORT := 443
const PRODUCTION_DOMAINS := ["grave-bound.com", "openrealm.net"]
const PRODUCTION_HOST := "grave-bound.com"


## {"host", "port", "secure"}, or {} when there is no page -- which is every
## desktop run, because the bridge answers null off the web rather than
## failing. `read` answers for one field of the page's location, by the name
## `window.location` gives it: "hostname", "port", "protocol".
static func current(read := Callable()) -> Dictionary:
	if not read.is_valid():
		read = from_browser
	var host: Variant = read.call("hostname")
	if not host is String or String(host) == "":
		return {}
	var port: Variant = read.call("port")
	return {
		"host": String(host),
		# Empty whenever the url leans on the scheme's default port.
		"port": int(String(port)) if port is String and String(port) != "" else 0,
		"secure": read.call("protocol") == "https:",
	}


## The page's location through the bridge's own object interface -- the
## documented way -- and through eval only when that yields nothing. Off the
## web both come back null, which is the desktop path.
static func from_browser(field: String) -> Variant:
	var location: JavaScriptObject = JavaScriptBridge.get_interface("location")
	if location != null:
		var value: Variant = location.get(field)
		if value is String:
			return value
	return JavaScriptBridge.eval("location.%s" % field)


## Points a config at that origin, leaving it alone when there is none. Called
## before the command line is parsed, so an explicit --host still wins.
static func apply(config: ClientConfig, origin: Dictionary) -> void:
	var host := String(origin.get("host", ""))
	if host == "":
		return
	if is_production(host):
		config.host = PRODUCTION_HOST
		config.secure = true
		config.data_port = HTTPS_PORT
		return
	config.host = host
	config.secure = bool(origin.get("secure", false))
	config.data_port = int(origin.get("port", 0))
	if config.data_port <= 0:
		config.data_port = HTTPS_PORT if config.secure else HTTP_PORT


## The domain itself or a subdomain of it -- never a lookalike that merely
## ends in the same letters.
static func is_production(host: String) -> bool:
	for domain in PRODUCTION_DOMAINS:
		if host == domain or host.ends_with("." + domain):
			return true
	return false
