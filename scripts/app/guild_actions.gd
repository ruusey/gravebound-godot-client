class_name GuildActions
extends RefCounted

## What the guild dialog, roster panel and invite popup send. Dedicated guild
## packets (not chat commands): create, a roster action by ordinal, and an
## invite answer. The scoped hall editor opens in a browser tab against the
## data service's own origin, carrying the one-shot token the server minted.

enum Action { OPEN_ROSTER, INVITE, KICK, PROMOTE, DEMOTE, LEAVE, DISBAND, EDIT_HALL }

var state: RealmState
var client: GraveBoundClient
var data_service: DataService


func _init(realm_state: RealmState, net_client: GraveBoundClient, service: DataService) -> void:
	state = realm_state
	client = net_client
	data_service = service


func create_guild(guild_name: String) -> bool:
	var name := guild_name.strip_edges()
	if name == "":
		return false
	return _send("CreateGuildPacket", { "guildName": name })


func open_roster() -> bool:
	return _action(Action.OPEN_ROSTER)


func invite(player_name: String) -> bool:
	var name := player_name.strip_edges()
	return name != "" and _action(Action.INVITE, name)


func kick(player_name: String) -> bool:
	return _action(Action.KICK, player_name)


func promote(player_name: String) -> bool:
	return _action(Action.PROMOTE, player_name)


func demote(player_name: String) -> bool:
	return _action(Action.DEMOTE, player_name)


func leave() -> bool:
	return _action(Action.LEAVE)


func disband() -> bool:
	return _action(Action.DISBAND)


func edit_hall() -> bool:
	return _action(Action.EDIT_HALL)


func respond_invite(accept: bool) -> bool:
	var guild_id := state.guild.invite_guild_id
	state.guild.clear_invite()
	return _send("GuildInviteResponsePacket", { "guildId": guild_id, "accept": accept })


## Open the scoped guild-hall editor in a new browser tab (web build only).
func open_editor(token: String) -> void:
	if token == "":
		return
	var url := data_service.base_url + "/game-data/editor/index.html?guildHall=" + token
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(%s, '_blank')" % JSON.stringify(url))
	else:
		OS.shell_open(url)


func _action(action: int, target: String = "") -> bool:
	return _send("GuildActionPacket", { "action": action, "targetName": target })


func _send(packet: String, data: Dictionary) -> bool:
	if client == null or not client.is_in_game():
		return false
	client.send(packet, data)
	return true
