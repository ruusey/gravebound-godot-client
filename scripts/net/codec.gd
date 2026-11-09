class_name NetCodec
extends RefCounted

## Reflective (schema-driven) reader/writer for the GraveBound binary protocol.
##
## The Java side walks a PacketMappingInformation[] built from @SerializableField
## annotations; this walks the equivalent table in NetSchema. Both sides are
## driven by the same ordered field list, so a wire change is picked up by
## regenerating schema.gd rather than by editing any parsing code.
##
## Scalars live in WireBuffer; this file is only the walk over the schema.
## Collections are [int32 count] followed by that many elements. A "mask"
## field is a masked-section block -- one byte, then the fields of each
## section whose bit is set, flattened into the same Dictionary as its parent.

# A set, not a list: this is tested per field of every decoded entity, so the
# membership check is an O(1) hash lookup rather than a linear scan each time.
const PRIMITIVES := {
	"byte": true, "bool": true, "short": true, "int": true,
	"long": true, "float": true, "string": true,
}


static func read_value(buf: StreamPeerBuffer, wire_type: String) -> Variant:
	if PRIMITIVES.has(wire_type):
		return WireBuffer.read_primitive(buf, wire_type)
	return read_fields(buf, NetSchema.fields_for(wire_type), wire_type)


static func write_value(buf: StreamPeerBuffer, wire_type: String, value: Variant) -> void:
	if PRIMITIVES.has(wire_type):
		WireBuffer.write_primitive(buf, wire_type, value)
	else:
		write_fields(buf, NetSchema.fields_for(wire_type), value if value is Dictionary else {})


## Reads one struct (packet body or nested entity) into a Dictionary.
static func read_fields(buf: StreamPeerBuffer, fields: Array, type_name := "") -> Dictionary:
	var out := {}
	for field in fields:
		var name: String = field[0]
		var wire_type: String = field[1]
		var is_collection: bool = field[2]
		if wire_type == "mask":
			out[name] = read_sections(buf, field[3], out, type_name)
		elif is_collection:
			var count := buf.get_32()
			if count < 0 or count > 1_000_000:
				push_error("NetCodec: implausible collection length %d for %s.%s" % [count, type_name, name])
				out[name] = []
				continue
			var items := []
			items.resize(count)
			for i in count:
				items[i] = read_value(buf, wire_type)
			out[name] = items
		else:
			out[name] = read_value(buf, wire_type)
	return out


static func write_fields(buf: StreamPeerBuffer, fields: Array, data: Dictionary) -> void:
	for field in fields:
		var name: String = field[0]
		var wire_type: String = field[1]
		var is_collection: bool = field[2]
		if wire_type == "mask":
			write_sections(buf, field[3], data, data.get(name, null))
		elif is_collection:
			var items: Array = data.get(name, [])
			buf.put_32(items.size())
			for item in items:
				write_value(buf, wire_type, item)
		else:
			write_value(buf, wire_type, data.get(name, null))


## Reads a mask byte and flattens each present section into `out`, returning
## the mask so re-encoding can reproduce it exactly.
static func read_sections(buf: StreamPeerBuffer, sections: Array, out: Dictionary,
		type_name: String) -> int:
	var mask := buf.get_8()
	for section in sections:
		if mask & int(section[0]) != 0:
			out.merge(read_fields(buf, section[1], type_name))
	return mask


static func write_sections(buf: StreamPeerBuffer, sections: Array, data: Dictionary,
		decoded_mask: Variant) -> void:
	var mask := NetMaskedSections.mask_for(sections, data, decoded_mask)
	buf.put_8(mask)
	for section in sections:
		if mask & int(section[0]) != 0:
			write_fields(buf, section[1], data)


## Decodes a packet payload (header already stripped, already decompressed).
static func decode_payload(type_name: String, payload: PackedByteArray) -> Dictionary:
	var fields := NetSchema.fields_for(type_name)
	if fields.is_empty() and not NetSchema.is_known(type_name):
		push_error("NetCodec: no schema for packet '%s'" % type_name)
		return {}
	return read_fields(WireBuffer.make_reader(payload), fields, type_name)


## Encodes a packet body (no header, no compression) from a Dictionary.
static func encode_payload(type_name: String, data: Dictionary) -> PackedByteArray:
	var fields := NetSchema.fields_for(type_name)
	if fields.is_empty() and not NetSchema.is_known(type_name):
		push_error("NetCodec: no schema for packet '%s'" % type_name)
		return PackedByteArray()
	var buf := WireBuffer.make_writer()
	write_fields(buf, fields, data)
	return buf.data_array
