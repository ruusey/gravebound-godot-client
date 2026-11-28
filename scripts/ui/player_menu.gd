class_name PlayerMenu
extends PanelContainer

## What you can do to a player you clicked: the web client's context
## menu, in Godot's own controls -- the name as a header in its role
## colour, then Trade, Teleport, Invite to Party, Challenge to PvP, when
## your guild rank allows it Invite to Guild, and Add Friend for a non-friend. Opens where it was asked to and
## closes on any choice or on a press anywhere else.

const INVITE_COLOUR := Color("fff0a0")
const GUILD_COLOUR := Color("a0d8ff")
const PVP_COLOUR := Color("ff8a8a")
const FRIEND_COLOUR := NameColours.FRIEND

var player_name := ""

var _header: Label
var _actions: Dictionary   # "trade" / "teleport" / "invite" / "guild" -> Callable
## Shown only when the local player's rank can invite to their guild; the
## server re-checks, so this is UX, not the authority.
var _guild_button: Button
var _can_guild_invite: Callable
## Hidden for someone who is already a friend.
var _friend_button: Button
var _is_friend: Callable


func _init(on_trade: Callable, on_teleport: Callable, on_invite: Callable,
		on_guild_invite: Callable, can_guild_invite: Callable, on_pvp: Callable,
		on_friend: Callable = Callable(), is_friend: Callable = Callable()) -> void:
	_actions = {"trade": on_trade, "teleport": on_teleport, "invite": on_invite,
		"guild": on_guild_invite, "pvp": on_pvp}
	if on_friend.is_valid():
		_actions["friend"] = on_friend
	_can_guild_invite = can_guild_invite
	_is_friend = is_friend
	visible = false
	var column := InventoryLayout.column(self)
	_header = InventoryLayout.heading(column, "")
	_option(column, "trade", "Trade", Color.WHITE)
	_option(column, "teleport", "Teleport", Color.WHITE)
	_option(column, "invite", "Invite to Party", INVITE_COLOUR)
	_option(column, "pvp", "Challenge to PvP", PVP_COLOUR)
	_guild_button = _option(column, "guild", "Invite to Guild", GUILD_COLOUR)
	_friend_button = _option(column, "friend", "Add Friend", FRIEND_COLOUR)


func open_for(name: String, colour: Color, at: Vector2) -> void:
	player_name = name
	_header.text = name
	_header.add_theme_color_override("font_color", colour)
	_guild_button.visible = _can_guild_invite.is_valid() and _can_guild_invite.call()
	_friend_button.visible = _actions.has("friend") and not (_is_friend.is_valid() and _is_friend.call(name))
	position = at
	visible = true


func close() -> void:
	visible = false
	player_name = ""


## A choice: the action for the player the menu is open on, then closed.
func choose(action: String) -> bool:
	if not visible or not _actions.has(action):
		return false
	var name := player_name
	close()
	return _actions[action].call(name)


func _option(into: Container, action: String, text: String, colour: Color) -> Button:
	var button := InventoryLayout.button(into, text, func() -> void: choose(action))
	button.add_theme_color_override("font_color", colour)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button
