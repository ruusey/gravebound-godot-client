extends GutTest

## ClientConfig defaults and command-line overrides.

func test_defaults_target_a_local_server():
	var config := ClientConfig.new()
	assert_eq(config.host, "127.0.0.1")
	assert_eq(ServerAddress.game_port(config), ClientConfig.TCP_PORT,
		"the game server's native TCP port")
	assert_true(config.autoconnect)
	assert_eq(config.data_root, ClientConfig.DEFAULT_DATA_ROOT)


func test_relative_data_root_resolves_against_the_project():
	var config := ClientConfig.new()
	config.data_root = "../somewhere/resources"
	var resolved := config.resolved_data_root()
	assert_true(resolved.is_absolute_path(), "resolved to an absolute path")
	assert_string_contains(resolved, "somewhere/resources")
	assert_false(resolved.contains(".."), "the path is simplified")


func test_absolute_data_root_is_left_alone():
	var config := ClientConfig.new()
	config.data_root = "/opt/openrealm/resources"
	assert_eq(config.resolved_data_root(), "/opt/openrealm/resources")


func test_parses_every_supported_flag():
	var config := ClientConfig.parse(PackedStringArray([
		"--host=game.example", "--port=9999", "--email=me@example.com",
		"--password=pw", "--character=uuid-1", "--token=tok",
		"--data-root=/tmp/content", "--no-connect",
	]))
	assert_eq(config.host, "game.example")
	assert_eq(ServerAddress.game_port(config), 9999)
	assert_eq(config.email, "me@example.com")
	assert_eq(config.password, "pw")
	assert_eq(config.character_uuid, "uuid-1")
	assert_eq(config.token, "tok")
	assert_eq(config.data_root, "/tmp/content")
	assert_false(config.autoconnect)


func test_values_may_contain_equals_signs():
	var config := ClientConfig.parse(PackedStringArray(["--password=a=b=c"]))
	assert_eq(config.password, "a=b=c", "only the first separator splits")


func test_empty_arguments_leave_defaults():
	var config := ClientConfig.parse(PackedStringArray([]))
	assert_eq(config.host, "127.0.0.1")


func test_unknown_flags_are_ignored():
	var config := ClientConfig.parse(PackedStringArray(["--nonsense=1", "--host=h"]))
	assert_eq(config.host, "h", "a bad flag does not abort parsing")


func test_from_command_line_uses_the_real_args():
	var config := ClientConfig.from_command_line()
	assert_not_null(config)


func test_data_base_url_omits_the_default_port():
	var config := ClientConfig.new()
	config.host = "openrealm.net"
	# Pinned rather than inherited: the default targets a local container,
	# which publishes the service on an unprivileged port.
	config.data_port = 80
	assert_eq(ServerAddress.data_url(config), "http://grave-bound.com",
		"the deployed service sits on 80 behind nginx")


func test_data_base_url_includes_a_custom_port():
	var config := ClientConfig.parse(PackedStringArray(["--host=127.0.0.1", "--data-port=8080"]))
	assert_eq(config.data_port, 8080)
	assert_eq(ServerAddress.data_url(config), "http://127.0.0.1:8080")


# --- transport --------------------------------------------------------------

func test_a_desktop_build_talks_tcp():
	var config := ClientConfig.parse(PackedStringArray([]), false)
	assert_false(config.websocket)
	assert_eq(ServerAddress.game_port(config), ClientConfig.TCP_PORT)
	assert_true(config.open_transport().inner is TcpTransport, "inside a delay line at no delay")


func test_a_web_build_talks_websocket_without_being_asked():
	# There is no raw socket in a browser, so this cannot be left to a flag
	# the page has no way to pass.
	var config := ClientConfig.parse(PackedStringArray([]), true)
	assert_true(config.websocket)
	assert_eq(ServerAddress.game_port(config), ClientConfig.WEBSOCKET_PORT)
	assert_true(config.open_transport().inner is WebSocketTransport)


func test_a_desktop_build_can_ask_for_websocket():
	# The only way to exercise the browser's path without an export.
	var config := ClientConfig.parse(PackedStringArray(["--websocket"]), false)
	assert_true(config.websocket)
	assert_eq(ServerAddress.game_port(config), ClientConfig.WEBSOCKET_PORT)


func test_an_explicit_port_wins_over_the_transport_default():
	var config := ClientConfig.parse(PackedStringArray(["--websocket", "--port=7000"]), false)
	assert_eq(ServerAddress.game_port(config), 7000)


func test_the_two_listeners_are_different_ports():
	assert_ne(ClientConfig.TCP_PORT, ClientConfig.WEBSOCKET_PORT)


func test_a_desktop_build_reads_content_from_disk():
	var config := ClientConfig.parse(PackedStringArray([]), false)
	assert_false(config.content_http)
	assert_true(config.open_content_source(null) is FileContentSource)


func test_a_web_build_fetches_content_without_being_asked():
	# There is no filesystem in a browser, and nothing to pass a flag.
	var config := ClientConfig.parse(PackedStringArray([]), true)
	assert_true(config.content_http)
	var source := config.open_content_source(FakeHttpBackend.new())
	assert_true(source is HttpContentSource)
	assert_string_contains(source.describe(), "/game-data/")


func test_a_desktop_build_can_ask_for_http_content():
	var config := ClientConfig.parse(PackedStringArray(
		["--content-http", "--host=d", "--data-port=9000"]), false)
	assert_eq(config.open_content_source(FakeHttpBackend.new()).describe(),
		"http://d:9000/game-data/")
