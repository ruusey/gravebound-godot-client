class_name ChatActions
extends RefCounted

## What the player says, as packets.
##
## A line that starts with "/" is a server command -- CommandPacket, the
## same envelope the login uses, with the command name and its arguments
## split out the way ServerCommandMessage.parseFromInput does -- and
## anything else is a TextPacket. The server ignores the `from` and `to` we
## write and rebroadcasts under our name and chat role; they are filled in
## as the web client fills them, so a packet capture reads the same.

var state: RealmState
var client: GraveBoundClient
## The commands the client answers itself (/dev, /debug, /clear), asked
## first; never sent.
var commands: ClientCommands


func _init(realm_state: RealmState, net_client: GraveBoundClient) -> void:
	state = realm_state
	client = net_client


## Returns whether the line was taken -- sent, or answered by the client
## itself: nothing is, for a blank line or outside a realm.
func say(text: String) -> bool:
	var line := text.strip_edges()
	if line == "" or client == null or not client.is_in_game():
		return false
	if line.begins_with("/"):
		if commands == null or not commands.run(line):
			client.send_server_command(line)
	else:
		client.send("TextPacket", {"from": state.local.name, "to": "Player", "message": line})
	return true
