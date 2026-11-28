class_name LoginHandshake
extends RefCounted

## The CommandPacket layer: login and command traffic is JSON carried inside
## packet id 7, multiplexed by an inner commandId.

const LOGIN_REQUEST := 1
const LOGIN_RESPONSE := 2
const SERVER_COMMAND := 3
const SERVER_ERROR := 4
const PLAYER_ACCOUNT := 5
## The server's answer to a client build older than the one /play serves.
const CLIENT_OUTDATED := 426


static func login_request(email: String, password: String, character_uuid: String,
		token := "") -> Dictionary:
	return {
		"playerId": 0,
		"commandId": LOGIN_REQUEST,
		"command": JSON.stringify({
			"email": email,
			"password": password,
			"characterUuid": character_uuid,
			# The Java DTO expects an absent token as null, not "".
			"token": token if token != "" else null,
			"clientVersion": client_version(),
		}),
	}


## This build's version, stamped into the project from the release tag when
## it is built ("dev" from a source checkout). The server turns older ones away.
static func client_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


## The body is a ServerCommandMessage: the word after the slash and the
## rest as arguments, split exactly as its parseFromInput splits a line --
## everything up to the first "/" is dropped, and a line with no slash is
## taken whole.
static func server_command(player_id: int, text: String) -> Dictionary:
	var words := text.substr(text.find("/") + 1).split(" ")
	return {
		"playerId": player_id,
		"commandId": SERVER_COMMAND,
		"command": JSON.stringify({"command": words[0], "args": Array(words.slice(1))}),
	}


## Interprets an inbound CommandPacket.
##
## Returns {"kind": "login_ok"|"login_rejected"|"update_required"|"server_error"|"ignored",
##          "body": Variant, "reason": String}.
static func interpret(data: Dictionary) -> Dictionary:
	var raw: String = data.get("command", "")
	var body = JSON.parse_string(raw)
	if body == null:
		return {"kind": "ignored", "body": null, "reason": ""}
	# playerId is a 64-bit id and JSON numbers arrive as floats, so it has to
	# be re-read from the text or the value is silently rounded.
	body = JsonInt64.repair(raw, body, ["playerId"])

	match int(data.get("commandId", 0)):
		LOGIN_RESPONSE:
			if body is Dictionary and body.get("success", false):
				return {"kind": "login_ok", "body": body, "reason": ""}
			return {"kind": "login_rejected", "body": body, "reason": "server rejected the login"}
		SERVER_ERROR:
			var reason := str(body.get("message", body)) if body is Dictionary else str(body)
			if body is Dictionary and int(body.get("code", 0)) == CLIENT_OUTDATED:
				return {"kind": "update_required", "body": body, "reason": reason}
			return {"kind": "server_error", "body": body, "reason": reason}
	return {"kind": "ignored", "body": body, "reason": ""}
