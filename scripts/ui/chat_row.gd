class_name ChatRow
extends RichTextLabel

## One line of the chat log: a SYSTEM line in the server's colour, a player
## line with the sender's name in their chat role's colour and what they
## said after it -- the web client's `[name]` span inside a plain line.
##
## A RichTextLabel because a Label has one colour, and the name and the
## message are two. The markup is built here and the player's own text is
## escaped into it, every `[` written as `[lb]`, so nothing typed into chat
## can open a tag: "[color=red]" said in chat reads as those characters.

const FONT_SIZE := 12
const SYSTEM_COLOUR := Color(1.0, 0.85, 0.4)
const PLAYER_COLOUR := Color(0.9, 0.9, 0.95)
# A /tell private message: whole line in this blue. The server tags the direction in
# the `to` (chat-role) field -- IN is received ("From X"), OUT is the sender's echo.
const WHISPER_COLOUR := Color(0.37, 0.66, 1.0)
const WHISPER_IN := "WHISPER_IN"
const WHISPER_OUT := "WHISPER_OUT"


func _init(width: float) -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_minimum_size.x = width
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("normal_font_size", FONT_SIZE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)


func show_line(line: Dictionary) -> void:
	add_theme_color_override("default_color",
		SYSTEM_COLOUR if ChatLog.is_system(line) else PLAYER_COLOUR)
	text = markup(line)
	visible = true


## Hidden as well as emptied, so the log sits on the panel's bottom margin
## whatever its length. An empty row still has a height, and the Labels this
## replaced left a log of one line five empty rows up the screen.
func blank() -> void:
	text = ""
	visible = false


## The line as the label draws it. `to` on a player line is the sender's
## chat role (ChatLog keeps the server's field as it came).
static func markup(line: Dictionary) -> String:
	var message := escaped(String(line.get("message", "")))
	if ChatLog.is_system(line):
		return message
	var from := String(line.get("from", ""))
	var role := String(line.get("to", ""))
	# A /tell private message: the whole line in whisper blue, prefixed with the
	# direction. `from` is the other player (sender on IN, recipient on the OUT echo).
	if role == WHISPER_IN or role == WHISPER_OUT:
		var direction := "From" if role == WHISPER_IN else "To"
		return "[color=#%s]%s [lb]%s]: %s[/color]" % [
			WHISPER_COLOUR.to_html(false), direction, escaped(from), message]
	var colour := NameColours.chat_sender(from, role)
	return "[color=#%s][lb]%s][/color]: %s" % [colour.to_html(false), escaped(from), message]


static func escaped(raw: String) -> String:
	return raw.replace("[", "[lb]")
