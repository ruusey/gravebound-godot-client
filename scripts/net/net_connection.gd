class_name NetConnection
extends RefCounted

## Socket plus framing: bytes in, decoded packets out.
##
## Everything here is about moving frames. What those frames *mean* -- login,
## heartbeats, the session state machine -- belongs to GraveBoundClient, which
## owns one of these.

var transport: NetTransport = TcpTransport.new()
var stats := NetStats.new()

var _stream := PacketStream.new()


func open(host: String, port: int) -> Error:
	# A socket that is still open refuses a fresh connect, so any retry --
	# a reconnect, or a second attempt after a failed login -- has to close
	# the previous one first or it fails permanently with ERR_ALREADY_IN_USE.
	transport.disconnect_from_host()
	_stream.clear()
	stats.reset()
	var err := transport.connect_to_host(host, port)
	if err == OK:
		transport.set_no_delay(true)
	return err


func close() -> void:
	transport.disconnect_from_host()
	_stream.clear()


func poll() -> void:
	transport.poll()


func status() -> int:
	return transport.get_status()


func is_open() -> bool:
	return transport.get_status() == StreamPeerTCP.STATUS_CONNECTED


## Encodes and writes one packet. Returns OK, or the write error.
func send(packet_name: String, data: Dictionary) -> Error:
	if not NetSchema.PACKET_IDS.has(packet_name):
		push_error("NetConnection: no packet id for '%s'" % packet_name)
		return ERR_INVALID_PARAMETER
	if not is_open():
		return ERR_UNAVAILABLE

	var frame := NetFrame.encode(NetSchema.PACKET_IDS[packet_name],
		NetCodec.encode_payload(packet_name, data))
	var err := transport.put_data(frame)
	if err == OK:
		stats.record_sent(frame.size())
	return err


## Reads whatever the socket has and decodes it.
##
## Returns {"packets": [{id, name, data}], "error": String}. A non-empty error
## means the stream desynced or the read failed; the connection should be
## dropped rather than resynchronised.
func read() -> Dictionary:
	var available := transport.get_available_bytes()
	if available > 0:
		var result := transport.get_data(available)
		if result[0] != OK:
			return {"packets": [], "error": "read failed: %s" % error_string(result[0])}
		var chunk: PackedByteArray = result[1]
		stats.bytes_in += chunk.size()
		_stream.feed(chunk)
	return _stream.drain()
