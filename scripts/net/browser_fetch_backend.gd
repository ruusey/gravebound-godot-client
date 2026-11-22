class_name BrowserFetchBackend
extends HttpBackend

## Whole-body GETs through the browser's own fetch(), for the web build's
## content (the JSON and the sprite sheets).
##
## HTTPRequest on the web reads its response stream one chunk per frame, and
## with many requests sharing the connection each chunk is a few KB: prod's
## maps.json took ~1000 frames to drain after its bytes had already arrived.
## fetch().arrayBuffer() hands the whole body over in one copy. The browser
## also inflates gzip itself, which HTTPRequest would then try to inflate a
## second time, so this is what lets the data service compress the content.

signal landed

const HELPER := """
window.gbFetchBytes = function (url, id, done) {
	fetch(url).then(function (response) {
		return response.arrayBuffer().then(function (body) {
			done(id, response.status, new Uint8Array(body));
		});
	}).catch(function () { done(id, 0, null); });
};
"""

var _window: JavaScriptObject
var _on_done: JavaScriptObject
var _results := {}   # request id -> [result, status, body] once landed
var _next_id := 0


func _init() -> void:
	JavaScriptBridge.eval(HELPER, true)
	_window = JavaScriptBridge.get_interface("window")
	# Held for the backend's lifetime: a collected callback can no longer be called.
	_on_done = JavaScriptBridge.create_callback(_done)


func perform(method: int, url: String, _headers: PackedStringArray, _body: String) -> Array:
	if method != HTTPClient.METHOD_GET:
		return [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray()]
	var id := _next_id
	_next_id += 1
	_results[id] = []
	_window.gbFetchBytes(url, id, _on_done)
	while _results[id].is_empty():
		await landed
	var result: Array = _results[id]
	_results.erase(id)
	return result


func _done(args: Array) -> void:
	var id := int(args[0])
	var status := int(args[1])
	if status <= 0:
		_results[id] = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray()]
	else:
		_results[id] = [HTTPRequest.RESULT_SUCCESS, status, JavaScriptBridge.js_buffer_to_packed_byte_array(args[2])]
	landed.emit()
