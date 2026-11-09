extends GutTest

## Where a web build gets its server address.
##
## A browser has no command line, so --host never arrives and the desktop
## default would send every player at their own machine. Reading the origin is
## one JavaScriptBridge call; everything it implies is decided here, which is
## why it can be tested without a browser.


## Stands in for the browser's `location`, field by field.
func _page(hostname: String, port := "", protocol := "http:") -> Callable:
	return func(field: String):
		match field:
			"hostname": return hostname
			"port": return port
			"protocol": return protocol
		return null


# --- reading the page -------------------------------------------------------

func test_a_plain_page_on_its_default_port():
	assert_eq(PageOrigin.current(_page("play.example")),
		{"host": "play.example", "port": 0, "secure": false})


func test_a_page_that_names_a_port():
	assert_eq(PageOrigin.current(_page("127.0.0.1", "8080")),
		{"host": "127.0.0.1", "port": 8080, "secure": false})


func test_a_page_served_over_tls():
	var origin := PageOrigin.current(_page("play.example", "", "https:"))
	assert_true(origin["secure"])


func test_there_is_no_page_on_the_desktop():
	# The bridge answers null off the web rather than failing, so this is the
	# path every desktop run takes -- through the object interface and the
	# eval fallback both.
	assert_eq(PageOrigin.current(), {})
	assert_null(PageOrigin.from_browser("hostname"))


func test_a_read_that_answers_nothing_is_no_page():
	var mute := func(_field: String): return null
	assert_eq(PageOrigin.current(mute), {})


func test_a_page_with_no_hostname_is_no_page():
	assert_eq(PageOrigin.current(_page("")), {})


# --- what it implies --------------------------------------------------------

func test_a_plain_page_points_the_client_at_itself():
	var config := ClientConfig.new()
	PageOrigin.apply(config, PageOrigin.current(_page("play.example")))
	assert_eq(config.host, "play.example")
	assert_eq(ServerAddress.data_url(config), "http://play.example",
		"the implied port is not spelled out")


func test_a_tls_page_fetches_over_tls():
	# A browser refuses to fetch plain http from an https page, so guessing
	# the scheme rather than deriving it would break every request.
	var config := ClientConfig.new()
	PageOrigin.apply(config, PageOrigin.current(_page("play.example", "", "https:")))
	assert_eq(ServerAddress.data_url(config), "https://play.example")
	assert_eq(config.data_port, PageOrigin.HTTPS_PORT)


func test_a_page_on_an_unusual_port_keeps_it():
	var config := ClientConfig.new()
	PageOrigin.apply(config, PageOrigin.current(_page("127.0.0.1", "8080")))
	assert_eq(ServerAddress.data_url(config), "http://127.0.0.1:8080")


func test_no_page_changes_nothing():
	var config := ClientConfig.new()
	PageOrigin.apply(config, {})
	assert_eq(config.host, "127.0.0.1")
	assert_eq(config.data_port, 8080)


# --- and what it means for the socket ---------------------------------------

func test_a_tls_page_opens_a_secure_socket():
	# A browser will not let an https page open ws://, so this has to follow
	# the page rather than a flag.
	var config := ClientConfig.parse(PackedStringArray([]), true,
		PageOrigin.current(_page("play.example", "", "https:")))
	# Through the ingress route, not the server's own listener: whatever
	# terminated the TLS is on 443, and 2223 is not reachable from an https
	# page at all.
	assert_eq(ServerAddress.game_host(config), "wss://play.example/ws")
	assert_eq(WebSocketTransport.url_for(ServerAddress.game_host(config),
		ServerAddress.game_port(config)), "wss://play.example/ws",
		"the port is not appended after the path")


func test_a_plain_page_opens_a_plain_socket():
	var config := ClientConfig.parse(PackedStringArray([]), true,
		PageOrigin.current(_page("play.example")))
	assert_eq(ServerAddress.game_host(config), "ws://play.example")


func test_tcp_dials_a_bare_host():
	# There is no scheme in a raw socket address.
	var config := ClientConfig.parse(PackedStringArray([]), false)
	assert_eq(ServerAddress.game_host(config), "127.0.0.1")


func test_a_host_written_with_its_own_scheme_is_left_alone():
	var config := ClientConfig.parse(PackedStringArray(
		["--websocket", "--host=wss://play.example"]), false)
	assert_eq(ServerAddress.game_host(config), "wss://play.example", "not ws://wss://...")


func test_the_page_supplies_the_host_when_nothing_else_does():
	var config := ClientConfig.parse(PackedStringArray([]), true,
		PageOrigin.current(_page("play.example")))
	assert_eq(config.host, "play.example")
	assert_eq(ServerAddress.data_url(config), "http://play.example")


func test_an_explicit_host_beats_the_page():
	# The origin is applied before the arguments precisely so this works --
	# it is how a page served from one host is pointed at another server.
	var config := ClientConfig.parse(PackedStringArray(["--host=elsewhere"]), true,
		PageOrigin.current(_page("play.example")))
	assert_eq(config.host, "elsewhere")


func test_a_desktop_build_ignores_a_page_entirely():
	var config := ClientConfig.parse(PackedStringArray([]), false,
		PageOrigin.current(_page("play.example")))
	assert_eq(config.host, "127.0.0.1")


# --- reaching the server through a proxy ------------------------------------

func test_a_proxied_socket_uses_the_page_port_not_the_listener():
	# Whatever terminated the TLS is listening on 443. The game server's own
	# 2223 is not reachable from an https page at all, so the route replaces
	# the listener rather than being added to it.
	var config := ClientConfig.parse(PackedStringArray([]), true,
	    PageOrigin.current(_page("play.example", "", "https:")))
	assert_eq(ServerAddress.game_host(config), "wss://play.example/ws")
	assert_eq(config.socket_path, ClientConfig.INGRESS_PATH)


func test_a_plain_page_dials_the_listener_directly():
	# No TLS means no proxy to route through, so there is nothing to path to.
	var config := ClientConfig.parse(PackedStringArray([]), true,
	    PageOrigin.current(_page("127.0.0.1", "8080")))
	assert_eq(config.socket_path, "")
	assert_eq(WebSocketTransport.url_for(ServerAddress.game_host(config),
	    ServerAddress.game_port(config)), "ws://127.0.0.1:2223")


func test_a_proxy_on_a_nonstandard_port_keeps_it():
	var config := ClientConfig.new()
	config.websocket = true
	config.host = "localhost"
	config.data_port = 8443
	config.socket_path = "/ws"
	assert_eq(ServerAddress.game_host(config), "ws://localhost:8443/ws")


func test_the_route_can_be_set_by_hand():
	var config := ClientConfig.parse(PackedStringArray(
	    ["--websocket", "--socket-path=/game"]), false)
	assert_eq(ServerAddress.game_host(config), "ws://127.0.0.1:8080/game")


func test_a_port_is_never_appended_after_a_path():
	# wss://play.example/ws:2223 resolves to nothing at all.
	assert_eq(WebSocketTransport.url_for("wss://play.example/ws", 2223),
	    "wss://play.example/ws")
	assert_eq(WebSocketTransport.url_for("wss://play.example", 2223),
	    "wss://play.example:2223", "but a bare authority still takes one")


# --- production --------------------------------------------------------------

func test_a_page_on_openrealm_talks_to_openrealm_over_tls():
	# A page on any openrealm.net host talks to the servers there. One rule,
	# no build variants.
	var config := ClientConfig.parse(PackedStringArray([]), true,
		PageOrigin.current(_page("play.openrealm.net", "", "https:")))
	assert_eq(config.host, "openrealm.net")
	assert_eq(ServerAddress.data_url(config), "https://grave-bound.com")
	# The route openrealm.net actually proxies: one per game server, and
	# US East is the one that answers. A bare /ws is a 404 there.
	assert_eq(ServerAddress.game_host(config), "wss://openrealm.net/ws/useast")


func test_the_production_domains_whatever_the_page_scheme_or_port():
	# A plain-http or oddly-ported page on the domain still goes to the real
	# servers over TLS: production is a place, not a scheme.
	for host in ["openrealm.net", "www.openrealm.net", "play.openrealm.net"]:
		var config := ClientConfig.new()
		PageOrigin.apply(config, PageOrigin.current(_page(host, "8080")))
		assert_eq(config.host, "openrealm.net", host)
		assert_eq(ServerAddress.data_url(config), "https://grave-bound.com", host)
		assert_true(config.secure, host)


func test_anywhere_else_still_talks_to_its_own_origin():
	for host in ["localhost", "127.0.0.1", "staging.example", "notopenrealm.net",
			"openrealm.net.evil.example"]:
		var config := ClientConfig.new()
		PageOrigin.apply(config, PageOrigin.current(_page(host, "8080")))
		assert_eq(config.host, host, host)
		assert_false(config.secure, host)


func test_an_explicit_host_still_beats_the_page():
	var config := ClientConfig.parse(PackedStringArray(["--host=127.0.0.1"]), true,
		PageOrigin.current(_page("play.openrealm.net", "", "https:")))
	assert_eq(config.host, "127.0.0.1")
