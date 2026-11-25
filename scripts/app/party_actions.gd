class_name PartyActions
extends RefCounted

## What the party panel and the invite prompt send: invites, answers, leave and
## kick all go on InteractionActionPacket, and the server answers on
## PartyUpdatePacket and InteractionPacket.

var state: RealmState
var interactions: InteractionActions


func _init(realm_state: RealmState, net_client: GraveBoundClient) -> void:
	state = realm_state
	interactions = InteractionActions.new(realm_state, net_client)


func invite(player_name: String) -> bool:
	return interactions.request(Interaction.Kind.PARTY, player_name)


func accept() -> bool:
	return _pending() and interactions.accept(Interaction.Kind.PARTY)


func decline() -> bool:
	return _pending() and interactions.decline(Interaction.Kind.PARTY)


func leave() -> bool:
	return state.party.in_party() and interactions.leave(Interaction.Kind.PARTY)


## Leader only, as the server insists; sending otherwise is refused here.
func kick(player_name: String) -> bool:
	return state.party.is_leader(state.local.id) and interactions.kick(Interaction.Kind.PARTY, player_name)


func _pending() -> bool:
	return state.interactions.request_from(Interaction.Kind.PARTY) != ""
