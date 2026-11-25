extends GutTest

## NetCodec: big-endian, Java DataOutputStream semantics, schema-driven ordering.

func _roundtrip(wire_type: String, value: Variant) -> Variant:
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, wire_type, value)
	return WireBuffer.read_primitive(WireBuffer.make_reader(writer.data_array), wire_type)


func test_writes_big_endian_int():
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "int", 0x01020304)
	assert_eq(writer.data_array, PackedByteArray([1, 2, 3, 4]), "most significant byte first")


func test_writes_big_endian_long():
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "long", 0x0102030405060708)
	assert_eq(writer.data_array, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]))


func test_writes_big_endian_short():
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "short", 0x0102)
	assert_eq(writer.data_array, PackedByteArray([1, 2]))


func test_float_is_four_byte_ieee754():
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "float", 1.0)
	assert_eq(writer.data_array, PackedByteArray([0x3F, 0x80, 0x00, 0x00]), "1.0f big-endian")


func test_signed_byte_boundaries():
	assert_eq(_roundtrip("byte", 127), 127)
	assert_eq(_roundtrip("byte", -128), -128)
	assert_eq(_roundtrip("byte", -1), -1)


func test_signed_short_boundaries():
	assert_eq(_roundtrip("short", 32767), 32767)
	assert_eq(_roundtrip("short", -32768), -32768)


func test_signed_int_boundaries():
	assert_eq(_roundtrip("int", 2147483647), 2147483647)
	assert_eq(_roundtrip("int", -2147483648), -2147483648)


func test_signed_long_boundaries():
	assert_eq(_roundtrip("long", 9223372036854775807), 9223372036854775807)
	assert_eq(_roundtrip("long", -9223372036854775808), -9223372036854775808)


func test_bool_roundtrip():
	assert_eq(_roundtrip("bool", true), true)
	assert_eq(_roundtrip("bool", false), false)


func test_string_is_utf8_byte_length_prefixed():
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "string", "hi")
	assert_eq(writer.data_array, PackedByteArray([0, 0, 0, 2, 0x68, 0x69]))


func test_string_prefix_counts_bytes_not_characters():
	# The Java writer is explicit about this: a char-count prefix desyncs the
	# stream on any multibyte character.
	var text := "☠é"
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "string", text)
	var declared := (writer.data_array[0] << 24) | (writer.data_array[1] << 16) \
		| (writer.data_array[2] << 8) | writer.data_array[3]
	assert_eq(declared, text.to_utf8_buffer().size(), "prefix is the utf-8 byte count")
	assert_eq(_roundtrip("string", text), text)


func test_empty_and_emoji_strings():
	assert_eq(_roundtrip("string", ""), "")
	assert_eq(_roundtrip("string", "\U0001f600 ok"), "\U0001f600 ok")


func test_null_values_write_as_java_defaults():
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "int", null)
	WireBuffer.write_primitive(writer, "string", null)
	WireBuffer.write_primitive(writer, "float", null)
	WireBuffer.write_primitive(writer, "bool", null)
	assert_eq(writer.data_array, PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))


func test_unknown_primitive_is_reported():
	var writer := WireBuffer.make_writer()
	WireBuffer.write_primitive(writer, "quaternion", 1)
	assert_eq(writer.data_array.size(), 0, "nothing is written for an unknown type")
	assert_null(WireBuffer.read_primitive(WireBuffer.make_reader(PackedByteArray([1, 2])), "quaternion"))


func test_packet_roundtrip_with_nested_entity():
	var value := {
		"realmId": 42, "mapId": 3, "mapWidth": 128, "mapHeight": 64,
		"tiles": [
			{"tileId": 7, "layer": 0, "xIndex": 10, "yIndex": 20},
			{"tileId": -1, "layer": 1, "xIndex": -5, "yIndex": 0},
		],
	}
	var decoded := NetCodec.decode_payload("LoadMapPacket", NetCodec.encode_payload("LoadMapPacket", value))
	assert_eq(decoded["realmId"], 42)
	assert_eq(decoded["tiles"].size(), 2)
	assert_eq(decoded["tiles"][1]["tileId"], -1)
	assert_eq(decoded["tiles"][1]["xIndex"], -5)


func test_collection_is_length_prefixed():
	var payload := NetCodec.encode_payload("UnloadPacket",
		{"players": [1, 2, 3], "bullets": [], "enemies": [], "containers": [], "portals": []})
	assert_eq(payload.slice(0, 4), PackedByteArray([0, 0, 0, 3]), "int32 count first")
	# 4 bytes count + 3 longs, then four empty collections at 4 bytes each.
	assert_eq(payload.size(), 4 + 24 + 16)


func test_empty_collections_roundtrip():
	var decoded := NetCodec.decode_payload("UnloadPacket", NetCodec.encode_payload("UnloadPacket", {}))
	for key in ["players", "bullets", "enemies", "containers", "portals"]:
		assert_eq(decoded[key], [], "%s defaults to an empty list" % key)


func test_missing_fields_write_as_defaults():
	var payload := NetCodec.encode_payload("PlayerMovePacket", {})
	var decoded := NetCodec.decode_payload("PlayerMovePacket", payload)
	assert_eq(decoded["seq"], 0)
	assert_eq(decoded["vx"], 0.0)
	assert_eq(decoded["vy"], 0.0)
	assert_false(decoded.has("entityId"), "v0.9.0 dropped it; the server takes the id from the connection")


func test_missing_nested_entity_writes_a_zeroed_struct():
	var payload := NetCodec.encode_payload("UpdatePacket", {"playerId": 1})
	var decoded := NetCodec.decode_payload("UpdatePacket", payload)
	assert_eq(decoded["stats"]["hp"], 0, "absent NetStats becomes an all-zero struct")
	assert_eq(decoded["playerName"], "")


func test_field_order_follows_the_schema():
	# seq(int) precedes vx(float) on this server build; a swap would move the
	# velocity bytes and is exactly the desync this ordering protects against.
	# v0.9.0 dropped the leading entityId -- the server takes the sender from
	# the connection -- so seq is now first on the wire.
	var payload := NetCodec.encode_payload("PlayerMovePacket", {"seq": 2, "vx": 1.0, "vy": 0.0})
	assert_eq(payload.size(), 12, "int + two floats, with no entity id")
	assert_eq(payload.slice(0, 4), PackedByteArray([0, 0, 0, 2]), "seq first")
	assert_eq(payload.slice(4, 8), PackedByteArray([0x3f, 0x80, 0, 0]), "then vx as a float")


func test_unknown_packet_name_is_reported_not_crashed():
	assert_eq(NetCodec.decode_payload("NoSuchPacket", PackedByteArray([1, 2, 3])), {})
	assert_eq(NetCodec.encode_payload("NoSuchPacket", {}).size(), 0)


func test_implausible_collection_length_is_rejected():
	# A desynced stream can present a huge count; allocating it would hang.
	var bytes := PackedByteArray([0x7F, 0xFF, 0xFF, 0xFF])
	var decoded := NetCodec.read_fields(WireBuffer.make_reader(bytes), [["ids", "long", true]], "Fake")
	assert_eq(decoded["ids"], [], "the collection is dropped rather than allocated")


func test_negative_collection_length_is_rejected():
	var bytes := PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF])
	var decoded := NetCodec.read_fields(WireBuffer.make_reader(bytes), [["ids", "long", true]], "Fake")
	assert_eq(decoded["ids"], [])


func test_read_and_write_value_dispatch_to_entities():
	var writer := WireBuffer.make_writer()
	NetCodec.write_value(writer, "NetTile", {"tileId": 3, "layer": 1, "xIndex": 4, "yIndex": 5})
	var tile: Dictionary = NetCodec.read_value(WireBuffer.make_reader(writer.data_array), "NetTile")
	assert_eq(tile["tileId"], 3)
	assert_eq(tile["yIndex"], 5)
	assert_false(tile.has("crackStage"), "an intact tile carries no crack section")


func test_cracked_tile_rides_its_masked_section():
	var writer := WireBuffer.make_writer()
	NetCodec.write_value(writer, "NetTile", {"tileId": 61, "layer": 1, "xIndex": 4, "yIndex": 5, "crackStage": 2})
	assert_eq(writer.data_array.size(), 2 + 1 + 2 + 2 + 1 + 1)
	var tile: Dictionary = NetCodec.read_value(WireBuffer.make_reader(writer.data_array), "NetTile")
	assert_eq(tile["crackStage"], 2)


func test_write_value_tolerates_a_non_dictionary_entity():
	var writer := WireBuffer.make_writer()
	NetCodec.write_value(writer, "NetTile", "not a struct")
	assert_eq(writer.data_array.size(), 2 + 1 + 2 + 2 + 1, "falls back to a zeroed NetTile")


func test_deeply_nested_entities_roundtrip():
	# NetGameItem embeds NetStats, NetDamage and NetEffect.
	var item := {
		"itemId": 3000, "uid": "u-1", "name": "Sword", "description": "d",
		"stats": {"hp": 10, "mp": 1, "def": 2, "str": 3, "spd": 4, "dex": 5, "vit": 6, "wis": 7},
		"damage": {"projectileGroupId": 9, "min": 10, "max": 20},
		"effect": {"self": true, "effectId": 4, "duration": 1000, "cooldownDuration": 500, "mpCost": 25},
		"consumable": false, "tier": 9, "targetSlot": 0, "targetClass": 1, "fameBonus": 2,
		"stackable": true, "maxStack": 99, "stackCount": 5, "category": "weapon",
		"forgeStatId": 0, "forgeSlotId": 0,
	}
	var decoded := NetCodec.decode_payload("UpdatePacket",
		NetCodec.encode_payload("UpdatePacket", {"playerId": 1, "inventory": [item]}))
	var out: Dictionary = decoded["inventory"][0]
	assert_eq(out["name"], "Sword")
	assert_eq(out["stats"]["wis"], 7)
	assert_eq(out["damage"]["max"], 20)
	assert_eq(out["effect"]["self"], true)
	assert_eq(out["effect"]["mpCost"], 25)


# --- masked sections (v0.9.0) ----------------------------------------------

func _straight_bullet() -> Dictionary:
	return {
		"id": 1, "projectileId": 7, "size": 8, "pos": {"x": 1.0, "y": 2.0},
		"dX": 0.0, "dY": 0.0, "angle": 0.5, "magnitude": 4.0, "range": 100.0,
		"damage": 3, "length": 0, "lifetimeTicks": 64, "srcEntityId": 9,
		"createdTime": 1000, "flags": [],
	}


func test_a_bullet_with_no_optional_groups_costs_one_mask_byte():
	var plain := NetCodec.encode_payload("NetBullet", _straight_bullet())
	var wavy := _straight_bullet()
	wavy["amplitude"] = 12
	wavy["frequency"] = 3
	var waved := NetCodec.encode_payload("NetBullet", wavy)
	# Both carry the mask byte; the difference is the group itself, which is
	# bool(1) + long(8) + short(2) + float(4).
	assert_eq(waved.size() - plain.size(), 15, "the wavy group rides only when asked for")


func test_absent_sections_do_not_appear_when_decoded():
	var decoded := NetCodec.decode_payload("NetBullet",
		NetCodec.encode_payload("NetBullet", _straight_bullet()))
	assert_eq(decoded["_mask"], 0)
	assert_false(decoded.has("amplitude"), "a section the mask left out never reached the wire")
	assert_false(decoded.has("orbitRadius"))
	assert_eq(decoded["angle"], 0.5, "the fields before the mask still decode")


func test_a_present_section_round_trips():
	var wavy := _straight_bullet()
	wavy["invert"] = true
	wavy["timeStep"] = 16
	wavy["amplitude"] = 12
	wavy["frequency"] = 7.0588
	var decoded := NetCodec.decode_payload("NetBullet", NetCodec.encode_payload("NetBullet", wavy))
	assert_eq(decoded["_mask"], 1, "only the wavy bit is set")
	assert_true(decoded["invert"])
	assert_eq(decoded["amplitude"], 12)
	assert_almost_eq(decoded["frequency"], 7.0588, 0.0001, "a fractional wave speed survives the wire")
	assert_eq(decoded["timeStep"], 16)


func test_each_section_sets_its_own_bit():
	var orbiting := _straight_bullet()
	orbiting["orbitRadius"] = 48.0
	var homing := _straight_bullet()
	homing["targetEntityId"] = 777
	var sprite := _straight_bullet()
	sprite["overrideSpriteKey"] = "bullets.png"

	assert_eq(NetCodec.decode_payload("NetBullet",
		NetCodec.encode_payload("NetBullet", orbiting))["_mask"], 2)
	assert_eq(NetCodec.decode_payload("NetBullet",
		NetCodec.encode_payload("NetBullet", homing))["_mask"], 4)
	assert_eq(NetCodec.decode_payload("NetBullet",
		NetCodec.encode_payload("NetBullet", sprite))["_mask"], 8)


func test_several_sections_combine_in_declaration_order():
	var both := _straight_bullet()
	both["amplitude"] = 1
	both["targetEntityId"] = 5
	var decoded := NetCodec.decode_payload("NetBullet", NetCodec.encode_payload("NetBullet", both))
	assert_eq(decoded["_mask"], 1 | 4)
	assert_eq(decoded["amplitude"], 1)
	assert_eq(decoded["targetEntityId"], 5)


func test_re_encoding_a_decoded_bullet_reproduces_the_bytes():
	# The decoded mask is carried on the dictionary, so a section that was
	# present but all-default is still written back.
	var wavy := _straight_bullet()
	wavy["timeStep"] = 16
	var original := NetCodec.encode_payload("NetBullet", wavy)
	var decoded := NetCodec.decode_payload("NetBullet", original)
	assert_eq(NetCodec.encode_payload("NetBullet", decoded), original)


func test_an_all_default_section_is_still_written_when_the_mask_says_so():
	var forced := _straight_bullet()
	forced["_mask"] = 2
	var decoded := NetCodec.decode_payload("NetBullet",
		NetCodec.encode_payload("NetBullet", forced))
	assert_eq(decoded["_mask"], 2)
	assert_eq(decoded["orbitRadius"], 0.0, "present, and zero")


func test_a_boolean_alone_is_enough_to_carry_its_section():
	# `invert` is the only non-numeric field in the wavy group, so a bullet
	# that only inverts still has to bring the group.
	var inverted := _straight_bullet()
	inverted["invert"] = true
	var decoded := NetCodec.decode_payload("NetBullet",
		NetCodec.encode_payload("NetBullet", inverted))
	assert_eq(decoded["_mask"], 1)
	assert_true(decoded["invert"])


func test_section_presence_ignores_default_values():
	var fields := [["invert", "bool", false], ["amplitude", "short", false]]
	assert_false(NetMaskedSections.has_values(fields, {}), "nothing set")
	assert_false(NetMaskedSections.has_values(fields, {"invert": false, "amplitude": 0}),
		"set, but to the values the mask exists to skip")
	assert_false(NetMaskedSections.has_values(fields, {"amplitude": null}))
	assert_true(NetMaskedSections.has_values(fields, {"amplitude": 3}))


func test_a_non_scalar_value_counts_as_present():
	# Nested entities and collections have no meaningful "default", so their
	# presence alone brings the section.
	assert_true(NetMaskedSections.has_values([["pos", "Vector2f", false]],
		{"pos": {"x": 0.0, "y": 0.0}}))
	assert_false(NetMaskedSections.has_values([["pos", "Vector2f", false]], {}))
