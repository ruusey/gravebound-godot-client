class_name NetFrame
extends RefCounted

## Framing and transparent compression, mirroring com.gb.net.core.PacketCompression
## and the read loop in the native client's SocketClient.
##
##   uncompressed:  [id : 1][totalLength : 4][payload ...]
##   compressed:    [id | 0x80 : 1][totalLength : 4][originalPayloadSize : 4][deflated ...]
##
## totalLength counts the 5-byte header. The compression flag is the high bit of
## the packet-id byte. Java uses new Deflater(BEST_SPEED), which emits a
## zlib-wrapped stream -- byte-compatible with Godot's COMPRESSION_DEFLATE
## (verified: both produce/accept the 0x78 zlib header).

const HEADER_SIZE := 5
const COMPRESSION_FLAG := 0x80
const COMPRESSION_THRESHOLD := 128
## Frames larger than this are rejected rather than buffered; the server's own
## per-session receive buffer is 640 KiB, so anything beyond that is a desync.
const MAX_FRAME_SIZE := 1 << 20


static func is_compressed(id_byte: int) -> bool:
	return (id_byte & COMPRESSION_FLAG) != 0


static func real_packet_id(id_byte: int) -> int:
	return id_byte & 0x7F


## Builds a complete wire frame, compressing it when it pays for itself.
static func encode(packet_id: int, payload: PackedByteArray) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true

	if payload.size() > COMPRESSION_THRESHOLD:
		var deflated := payload.compress(FileAccess.COMPRESSION_DEFLATE)
		# Java falls back to the raw frame when deflate doesn't actually shrink it.
		if deflated.size() > 0 and deflated.size() < payload.size():
			buf.put_8(packet_id | COMPRESSION_FLAG)
			buf.put_32(HEADER_SIZE + 4 + deflated.size())
			buf.put_32(payload.size())
			buf.put_data(deflated)
			return buf.data_array

	buf.put_8(packet_id)
	buf.put_32(HEADER_SIZE + payload.size())
	if payload.size() > 0:
		buf.put_data(payload)
	return buf.data_array


## Attempts to pull one frame off the front of `buffer`.
##
## Returns {} when more bytes are needed, {"error": "..."} on a malformed frame
## (the caller should drop the connection -- the stream is desynced), otherwise
## {"id": int, "payload": PackedByteArray, "consumed": int}.
static func try_decode(buffer: PackedByteArray) -> Dictionary:
	return try_decode_at(buffer, 0)


## As try_decode, but reads the frame starting at byte `start` instead of 0, so
## the drain loop can advance an offset rather than re-slicing the whole
## remaining buffer every frame (that copy was O(n^2) on a first-world burst of
## hundreds of frames). `consumed` is still the frame's own length, relative, so
## the caller accumulates it exactly as before.
static func try_decode_at(buffer: PackedByteArray, start: int) -> Dictionary:
	var available := buffer.size() - start
	if available < HEADER_SIZE:
		return {}

	var id_byte := buffer[start]
	var total_length := (buffer[start + 1] << 24) | (buffer[start + 2] << 16) \
		| (buffer[start + 3] << 8) | buffer[start + 4]

	if total_length < HEADER_SIZE or total_length > MAX_FRAME_SIZE:
		return {"error": "implausible frame length %d (id byte 0x%02x)" % [total_length, id_byte]}
	if available < total_length:
		return {}

	var payload := buffer.slice(start + HEADER_SIZE, start + total_length)

	if is_compressed(id_byte):
		if payload.size() < 4:
			return {"error": "compressed frame shorter than its size prefix"}
		var original_size := (payload[0] << 24) | (payload[1] << 16) | (payload[2] << 8) | payload[3]
		if original_size <= 0 or original_size > MAX_FRAME_SIZE:
			return {"error": "implausible decompressed size %d" % original_size}
		var deflated := payload.slice(4)
		var inflated := deflated.decompress(original_size, FileAccess.COMPRESSION_DEFLATE)
		if inflated.size() != original_size:
			return {"error": "decompression size mismatch: expected %d got %d" % [original_size, inflated.size()]}
		payload = inflated

	return {
		"id": real_packet_id(id_byte),
		"payload": payload,
		"consumed": total_length,
	}
