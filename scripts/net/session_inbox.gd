class_name SessionInbox
extends RefCounted

## Interprets decoded packets into session events.
##
## Deliberately pure: it reads packets and returns what happened, without
## touching connection state or emitting anything. That keeps the login and
## desync paths unit-testable without a socket, and leaves GraveBoundClient
## doing only state transitions and signal emission.
##
## Event kinds: "packet", "unknown", "login_ok", "login_rejected",
## "server_error", "desync".

static func process(read_result: Dictionary, stats: NetStats, now_ms: int) -> Array:
	var events: Array = []

	for packet in read_result["packets"]:
		var name: String = packet["name"]
		if name == "":
			stats.record_received("")
			events.append({"kind": "unknown", "id": packet["id"]})
			continue

		stats.record_received(name)
		var data: Dictionary = packet["data"]

		if name == "PlayerPosAckPacket":
			stats.record_ack(int(data.get("seq", -1)), now_ms)
		elif name == "HeartbeatPacket":
			stats.record_heartbeat_echo(int(data.get("timestamp", 0)), now_ms)
		elif name == "CommandPacket":
			var command := LoginHandshake.interpret(data)
			match command["kind"]:
				"login_ok":
					events.append({"kind": "login_ok", "body": command["body"]})
				"login_rejected":
					events.append({"kind": "login_rejected", "reason": command["reason"]})
				"server_error":
					events.append({"kind": "server_error", "reason": command["reason"]})

		events.append({"kind": "packet", "name": name, "data": data})

	if read_result["error"] != "":
		events.append({"kind": "desync", "reason": read_result["error"]})
	return events
