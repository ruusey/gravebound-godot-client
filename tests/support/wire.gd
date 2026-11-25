class_name WireHelper
extends RefCounted

## Builds server->client frames the way the Java side would, for tests that
## need to feed a client rather than assert on bytes.

static func frame(packet_name: String, data: Dictionary) -> PackedByteArray:
	return NetFrame.encode(NetSchema.PACKET_IDS[packet_name], NetCodec.encode_payload(packet_name, data))


static func login_response(player_id: int, class_id: int, spawn: Vector2, success := true) -> PackedByteArray:
	return frame("CommandPacket", {
		"playerId": player_id,
		"commandId": LoginHandshake.LOGIN_RESPONSE,
		"command": JSON.stringify({
			"playerId": player_id,
			"classId": class_id,
			"success": success,
			"spawnX": spawn.x,
			"spawnY": spawn.y,
			"token": "tok",
			"chatRole": "player",
		}),
	})


## `x` is the column and `y` the row, packed the way the server packs them:
## xIndex carries the row and yIndex the column (TileManager builds
## `new NetTile(id, layer, y, x)`). Mimicking that here is the point -- a
## helper that packed them at face value would hide a transpose.
static func tile(tile_id: int, layer: int, x: int, y: int) -> Dictionary:
	return {"tileId": tile_id, "layer": layer, "xIndex": y, "yIndex": x}


static func player(id: int, name: String, position: Vector2, short_id := 0, class_id := 0) -> Dictionary:
	return {
		"id": id, "name": name, "accountUuid": "", "characterUuid": "",
		"classId": class_id, "size": 28, "pos": {"x": position.x, "y": position.y},
		"dX": 0.0, "dY": 0.0, "shortId": short_id, "chatRole": "", "dyeId": 0,
	}


static func enemy(id: int, enemy_id: int, position: Vector2, short_id := 0, health := 100) -> Dictionary:
	return {
		"id": id, "enemyId": enemy_id, "weaponId": 0, "size": 16,
		"pos": {"x": position.x, "y": position.y}, "dX": 0.0, "dY": 0.0,
		"difficulty": 1.0, "health": health, "maxHealth": 100, "shortId": short_id,
	}


static func portal(id: int, portal_id: int, position: Vector2, label := "",
		tier := 0) -> Dictionary:
	return {
		"id": id, "portalId": portal_id, "fromRealmId": 0, "toRealmId": 0,
		"expires": 0, "pos": {"x": position.x, "y": position.y},
		"targetLabel": label, "targetDifficulty": 0.0, "targetPlayerCount": 0,
		"targetPurificationProgress": 0, "targetPurificationGoal": 0,
		"targetTier": tier, "targetModifiers": "",
	}


## An InteractionPacket as the server sends it.
static func interaction(kind: int, event: int, other_name := "", detail := "", duration_ms := 0) -> Dictionary:
	return {"kind": kind, "event": event, "otherName": other_name, "detail": detail, "durationMs": duration_ms}


## Each InteractionActionPacket sent, as "KIND ACTION target" (e.g. "PARTY KICK Mingau").
static func interaction_actions(transport: FakeTransport) -> Array:
	return transport.sent_packets().filter(func(p: Dictionary) -> bool: return p["name"] == "InteractionActionPacket") \
		.map(func(p: Dictionary) -> String:
			var data: Dictionary = p["data"]
			var line := "%s %s" % [Interaction.Kind.keys()[int(data["kind"])], Interaction.Action.keys()[int(data["action"])]]
			return line + (" " + String(data["targetName"]) if String(data["targetName"]) != "" else ""))
