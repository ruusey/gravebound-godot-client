class_name ServerPing
extends RefCounted

## How far away a game server is: the HTTP round trip of its /admin/ping, the
## fastest of a few on one warm connection, so connecting and TLS are never
## counted. Timed where the request runs -- the browser's own fetch on web, a
## thread spinning on HTTPClient natively -- never by frame polling, which
## would add up to a frame to every reading.
##
## Web goes through the page's origin (/ping/<slug> on nginx, as the game's
## wss does; a TLS page cannot fetch plain http). Native goes straight to the
## node's admin port, as its game socket does.

const ADMIN_PORT := 8088
const ADMIN_PATH := "/admin/ping"
const PROBES := 4
const TIMEOUT_MS := 4000
## What a probe reads before it has an answer, and when it has failed.
const PENDING := -2
const FAILED := -1

var _key := ""
var _thread: Thread
var _result := PENDING


## Where `server` is pinged from a client whose data service is at `base_url`.
static func url(server: Dictionary, base_url: String) -> String:
	if server.get("local", false):
		return "http://127.0.0.1:%d%s" % [ADMIN_PORT, ADMIN_PATH]
	if OS.has_feature("web") and base_url.begins_with("https"):
		var authority := base_url.substr(base_url.find("://") + 3)
		return "https://%s/ping/%s" % [authority, str(server.get("slug", ""))]
	return "http://%s:%d%s" % [str(server.get("host", "")), ADMIN_PORT, ADMIN_PATH]


func start(target: String) -> void:
	if OS.has_feature("web"):
		_key = "p%d" % get_instance_id()
		JavaScriptBridge.eval(_web_probe(_key, target), true)
	else:
		_thread = Thread.new()
		_thread.start(_native_probe.bind(target))


## The best round trip in ms, PENDING while still measuring, or FAILED.
func result() -> int:
	if _result != PENDING:
		return _result
	if OS.has_feature("web"):
		var got: Variant = JavaScriptBridge.eval("window.__gbPing && window.__gbPing['%s']" % _key, true)
		if got is float or got is int:
			_result = int(got)
	elif _thread != null and not _thread.is_alive():
		_result = _thread.wait_to_finish()
		_thread = null
	return _result


## A no-cors fetch so a node on another origin (local) still answers; its
## opaque reply counts, but an error status from our own nginx does not.
static func _web_probe(key: String, target: String) -> String:
	return """(async (key, url) => {
	window.__gbPing = window.__gbPing || {};
	let best = -1;
	for (let i = 0; i < %d; i++) {
		const ctl = new AbortController();
		const timer = setTimeout(() => ctl.abort(), %d);
		const t = performance.now();
		try {
			const r = await fetch(url, {mode: 'no-cors', cache: 'no-store', signal: ctl.signal});
			if (r.type !== 'opaque' && !r.ok) { best = -1; break; }
		} catch (e) { best = -1; break; } finally { clearTimeout(timer); }
		const ms = performance.now() - t;
		best = best < 0 ? ms : Math.min(best, ms);
	}
	window.__gbPing[key] = Math.round(best);
})(%s, %s);""" % [PROBES, TIMEOUT_MS, JSON.stringify(key), JSON.stringify(target)]


static func _native_probe(target: String) -> int:
	var rest := target.substr(target.find("://") + 3)
	var slash := rest.find("/")
	var path := rest.substr(slash) if slash >= 0 else "/"
	var authority := rest.substr(0, slash) if slash >= 0 else rest
	var colon := authority.rfind(":")
	var host := authority.substr(0, colon) if colon >= 0 else authority
	var port := int(authority.substr(colon + 1)) if colon >= 0 else 80
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	var http := HTTPClient.new()
	var best := FAILED
	for i in PROBES:
		if http.get_status() != HTTPClient.STATUS_CONNECTED and not _connect(http, host, port, deadline):
			break
		var start := Time.get_ticks_usec()
		if http.request(HTTPClient.METHOD_GET, path, []) != OK:
			break
		while http.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
			http.poll()
			OS.delay_usec(50)
		var ms := (Time.get_ticks_usec() - start) / 1000
		if not http.has_response() or http.get_response_code() != 200:
			break
		best = ms if best < 0 else mini(best, ms)
		while http.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
			http.poll()
			http.read_response_body_chunk()
	http.close()
	return best


static func _connect(http: HTTPClient, host: String, port: int, deadline: int) -> bool:
	http.close()
	if http.connect_to_host(host, port) != OK:
		return false
	while http.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING] \
			and Time.get_ticks_msec() < deadline:
		http.poll()
		OS.delay_usec(200)
	return http.get_status() == HTTPClient.STATUS_CONNECTED
