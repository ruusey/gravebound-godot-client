class_name NameColours
extends RefCounted

## What colour a player's name is, by chat role, wherever it is written.
##
## The web client keeps two tables, and they disagree on one entry. Over a
## head and in the nearby list a name with no role is off-white
## (renderer.js getNameColorHex, main.js getNameColorCSS); in the chat log
## it is blue (main.js getNameColor's DEFAULT_NAME_COLOR), and a couple of
## senders that are not players at all have a colour of their own by name
## (CHAT_NAME_COLORS). The roles themselves are the same five everywhere,
## and the native client's roleColorFor uses the same five.
##
## The role is whatever the server calls it: NetPlayer.chatRole on the
## roster, and on a player's chat line the TextPacket's `to`, which the
## server fills with the sender's role (ServerGameLogic's rebroadcast).

const ROLES := {
	"sysadmin": Color("ff4040"), "admin": Color("4080e0"), "mod": Color("40c040"),
	"editor": Color("a040c0"), "demo": Color("cccccc"),
}
## A name with no role, over a head or in a list.
const PLAIN := Color("eeeeee")
## A sender with no role, in the chat log.
const CHAT_PLAIN := Color("4080e0")
## A friend's name in the nearby list and the directory.
const FRIEND := Color("ffd34d")
## A guild member's name there, the green of guild chat.
const GUILDMATE := Color(0.4, 0.9, 0.4)
## Senders coloured by who they are rather than what role they hold.
const CHAT_NAMED := {"SYSTEM": Color("c8a86e"), "Overseer": Color("e8c840")}


static func role(chat_role: String) -> Color:
	return ROLES.get(chat_role, PLAIN)


## The sender's name on a chat line: a named sender first, then the role,
## then the log's own default -- getNameColor's order.
static func chat_sender(from: String, chat_role: String) -> Color:
	if CHAT_NAMED.has(from):
		return CHAT_NAMED[from]
	return ROLES.get(chat_role, CHAT_PLAIN)


## The name over a character. The local player keeps its own green -- how
## you pick yourself out of a crowd -- until it holds a role, and then it is
## the role's colour, as the web client shows it: its own comment says an
## admin has to see their own colour on their own character.
static func over_head(chat_role: String, is_local: bool, local_colour: Color) -> Color:
	if is_local and not ROLES.has(chat_role):
		return local_colour
	return role(chat_role)
