class_name TradeActions
extends RefCounted

## What the trade panels send.
##
## Requests, answers and the open trade's Cancel go on InteractionActionPacket;
## the selection packet goes whenever a slot is put on or taken off the table,
## and /confirm true seals our side.

var state: RealmState
var client: GraveBoundClient
var interactions: InteractionActions


func _init(realm_state: RealmState, net_client: GraveBoundClient) -> void:
	state = realm_state
	client = net_client
	interactions = InteractionActions.new(realm_state, net_client)


func request(player_name: String) -> bool:
	return interactions.request(Interaction.Kind.TRADE, player_name)


func accept() -> bool:
	return interactions.accept(Interaction.Kind.TRADE)


## Answers a request with no, or cancels the trade already open.
func decline() -> bool:
	if state.trade.active:
		return interactions.leave(Interaction.Kind.TRADE)
	return interactions.decline(Interaction.Kind.TRADE)


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
