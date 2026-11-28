class_name SocialActions
extends RefCounted

## What the friends and guild directory and the player menu do to another
## player. Friend requests, summons and trades ride InteractionActionPacket;
## a visit is the /visit command, and a message opens the chat line on a /tell.
## The server decides who may do what, so a refusal comes back as a notice.

var interactions: InteractionActions
var chat: ChatActions
## Opens the chat line with the given text in it.
var open_line: Callable


func _init(interaction_actions: InteractionActions, chat_actions: ChatActions,
		open_chat_line: Callable = Callable()) -> void:
	interactions = interaction_actions
	chat = chat_actions
	open_line = open_chat_line


func add_friend(player_name: String) -> bool:
	return interactions != null and interactions.request(Interaction.Kind.FRIEND, player_name)


func remove_friend(player_name: String) -> bool:
	return interactions != null and interactions.kick(Interaction.Kind.FRIEND, player_name)


func summon(player_name: String) -> bool:
	return interactions != null and interactions.request(Interaction.Kind.SUMMON, player_name)


func trade(player_name: String) -> bool:
	return interactions != null and interactions.request(Interaction.Kind.TRADE, player_name)


func visit(player_name: String) -> bool:
	var name := player_name.strip_edges()
	return name != "" and chat != null and chat.say("/visit %s" % name)


func message(player_name: String) -> bool:
	var name := player_name.strip_edges()
	if name == "" or not open_line.is_valid():
		return false
	open_line.call("/tell %s " % name)
	return true
