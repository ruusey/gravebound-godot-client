class_name TradeActions
extends RefCounted

## What the trade panels send.
##
## The server drives trading by command -- /trade, /accept, /decline and
## /confirm true, the same commands the chat line could send -- and by one
## packet, the selection, which goes whenever a slot is put on or taken
## off the table. Cancel is /decline: the server's decline handler ends a
## pending request and an open trade alike.

var state: RealmState
var client: GraveBoundClient


func _init(realm_state: RealmState, net_client: GraveBoundClient) -> void:
	state = realm_state
	client = net_client


func request(player_name: String) -> bool:
	return _command("/trade %s" % player_name) if player_name.strip_edges() != "" else false


func accept() -> bool:
	return _command("/accept")


func decline() -> bool:
	return _command("/decline")


func confirm() -> bool:
	return state.trade.active and _command("/confirm true")


## Flips a page slot on the table and tells the server.
func toggle(slot_index: int) -> bool:
	if client == null or not client.is_in_game() or not state.trade.toggle(slot_index):
		return false
	client.send("UpdatePlayerTradeSelectionPacket", TradeStatus.selection_packet(state.local.id, state.trade.my_selected))
	return true


func _command(line: String) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send_server_command(line)
	return true
