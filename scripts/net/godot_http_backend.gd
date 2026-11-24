class_name GodotHttpBackend
extends HttpBackend

## Production backend: a pool of HTTPRequest nodes, so several requests can
## be in flight at once.
##
## One node serves one request at a time. A request takes an idle node or
## adds one, up to MAX_IN_FLIGHT; past that it waits for a node to free.
## The sheet preload is what needs this -- 70-odd fetches started together.
## Over HTTP/2 the browser multiplexes them all on one connection, so a low cap
## only queued them into back-to-back rounds of round trips.

const MAX_IN_FLIGHT := 32
## HTTPRequest reads one chunk of a response body per frame, so at the default
## 64 KiB a multi-megabyte content file took seconds of frames to arrive no
## matter how fast the connection was.
const DOWNLOAD_CHUNK_BYTES := 1 << 22

signal freed

var _host: Node
var _idle: Array[HTTPRequest] = []
var _in_flight := 0


func _init(host: Node) -> void:
	_host = host


func perform(method: int, url: String, headers: PackedStringArray, body: String) -> Array:
	while _in_flight >= MAX_IN_FLIGHT:
		await freed
	var request: HTTPRequest = _idle.pop_back() if not _idle.is_empty() else _spawn()
	_in_flight += 1
	var result: Array
	if request.request(url, headers, method, body) != OK:
		result = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray()]
	else:
		var done: Array = await request.request_completed
		result = [done[0], done[1], done[3]]
	_idle.append(request)
	_in_flight -= 1
	freed.emit()
	return result


func _spawn() -> HTTPRequest:
	var request := HTTPRequest.new()
	# Not on the web, where HTTPClientWeb keeps a read buffer of this size per
	# request; content there goes through BrowserFetchBackend instead.
	if not OS.has_feature("web"):
		request.download_chunk_size = DOWNLOAD_CHUNK_BYTES
		# Polled per frame, each step of the TLS handshake and each ~16 KB TLS
		# record read waits for the next frame: prod's 4 MB of content took 12 s
		# at 60 fps. On a thread it drains as fast as the socket does (~1.6 s).
		request.use_threads = true
	# In a browser, fetch() has already inflated a gzipped body but the
	# Content-Encoding header survives, and HTTPRequest would inflate it again.
	request.accept_gzip = not OS.has_feature("web")
	_host.add_child(request)
	return request


## How many nodes the pool has grown to: the most that were ever in flight.
func pool_size() -> int:
	return _idle.size() + _in_flight
