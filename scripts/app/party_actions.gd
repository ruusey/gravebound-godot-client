class_name PartyActions
extends RefCounted

## What the party panel and the invite prompt send.
##
## The server drives parties by command -- /party invite, accept, decline,
## leave and kick, the same lines the chat could send -- and answers on
## PartyUpdatePacket and SYSTEM text. Accept and decline drop the prompt
## at once rather than waiting for the reply, as both references do.

var state: RealmState
var client: GraveBoundClient


func _init(realm_state: RealmState, net_client: GraveBoundClient) -> void:
	state = realm_state
	client = net_client


func invite(player_name: String) -> bool:
	var name := player_name.strip_edges()
	return name != "" and _command("/party invite %s" % name)


func accept() -> bool:
	return _answer("accept")


func decline() -> bool:
	return _answer("decline")


func leave() -> bool:
	return state.party.in_party() and _command("/party leave")


## Leader only, as the server insists; sending otherwise is refused here.
func kick(player_name: String) -> bool:
	var name := player_name.strip_edges()
	return name != "" and state.party.is_leader(state.local.id) and _command("/party kick %s" % name)


func _answer(word: String) -> bool:
	if state.party.invite_from == "" or not _command("/party %s" % word):
		return false
	state.party.invite_from = ""
	return true


func _command(line: String) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send_server_command(line)
	return true
