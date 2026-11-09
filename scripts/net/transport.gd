class_name NetTransport
extends RefCounted

## Byte-stream seam between GraveBoundClient and the socket.
##
## The client's interesting behaviour -- frame reassembly across split reads,
## desync detection, handshake sequencing, disconnect handling -- is all
## reachable only by controlling exactly which bytes arrive when. Going through
## this interface lets tests drive that directly instead of standing up a
## server and hoping for the right packet boundaries.
##
## Status values mirror StreamPeerTCP.Status so the real implementation is a
## thin pass-through.

func connect_to_host(_host: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


func poll() -> void:
	pass


func get_status() -> int:
	return StreamPeerTCP.STATUS_NONE


func get_available_bytes() -> int:
	return 0


## Returns [Error, PackedByteArray], matching StreamPeer.get_data.
func get_data(_count: int) -> Array:
	return [ERR_UNAVAILABLE, PackedByteArray()]


func put_data(_bytes: PackedByteArray) -> Error:
	return ERR_UNAVAILABLE


func disconnect_from_host() -> void:
	pass


func set_no_delay(_enabled: bool) -> void:
	pass
