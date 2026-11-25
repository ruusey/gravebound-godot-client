class_name InteractionActions
extends RefCounted

## Asks another player to trade, party up or fight, and answers their asks, on
## InteractionActionPacket. An answer takes its prompt down at once rather than
## waiting for the server's CLOSED.

var state: RealmState
var client: GraveBoundClient


func _init(realm_state: RealmState, net_client: GraveBoundClient) -> void:
	state = realm_state
	client = net_client


func request(kind: int, player_name: String) -> bool:
	var name := player_name.strip_edges()
	return name != "" and _send(kind, Interaction.Action.REQUEST, name)


func accept(kind: int) -> bool:
	return _answer(kind, Interaction.Action.ACCEPT)


func decline(kind: int) -> bool:
	return _answer(kind, Interaction.Action.DECLINE)


## Leaves the party, cancels the open trade or forfeits the PvP match.
func leave(kind: int) -> bool:
	return _send(kind, Interaction.Action.LEAVE, "")


func kick(kind: int, player_name: String) -> bool:
	var name := player_name.strip_edges()
	return name != "" and _send(kind, Interaction.Action.KICK, name)


func _answer(kind: int, action: int) -> bool:
	if state != null:
		state.interactions.answered(kind)
	return _send(kind, action, "")


func _send(kind: int, action: int, target_name: String) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send("InteractionActionPacket", {"kind": kind, "action": action, "targetName": target_name})
	return true
