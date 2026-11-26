extends GutTest

## Where the login screen's server picker pings each server.

const USEAST := {"name": "us-east", "slug": "useast", "host": "100.55.103.226", "route": "/ws/useast"}


func test_natively_the_node_is_pinged_on_its_own_admin_port():
	assert_eq(ServerPing.url(USEAST, "https://grave-bound.com"), "http://100.55.103.226:8088/admin/ping")


func test_a_local_server_is_pinged_on_localhost():
	assert_eq(ServerPing.url({"local": true, "host": "127.0.0.1"}, "https://grave-bound.com"),
		"http://127.0.0.1:8088/admin/ping")
