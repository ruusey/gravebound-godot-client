class_name GuildRosterPanel
extends CanvasLayer

## The guild hall roster: every member and their rank, with the admin controls
## the local rank is allowed -- Owner/Leader promote and demote and kick down
## their line, Officers kick Initiates, Officers and up invite. Owner alone
## disbands; everyone else leaves. Owner/Leader also open the scoped hall
## editor. The server re-checks each action, so a control shown in error just
## comes back as a SYSTEM refusal.

const LIST_HEIGHT := 300.0

var state: RealmState
var actions: GuildActions

var _root: PanelContainer
var _title: Label
var _standing: Label
var _list: VBoxContainer
var _invite_row: HBoxContainer
var _invite_input: LineEdit
var _leave: Button
var _disband: Button
var _edit_hall: Button
var _drawn := -1


func setup(realm_state: RealmState, guild_actions: GuildActions) -> void:
	state = realm_state
	actions = guild_actions


func _ready() -> void:
	layer = 14
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(440, 0)
	centre.add_child(_root)
	var column := InventoryLayout.column(_root)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	_title = InventoryLayout.heading(bar, "GUILD")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.42))
	InventoryLayout.button(bar, "Close", func() -> void: state.guild.close_roster())
	_standing = InventoryLayout.heading(column, "")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_invite_row = HBoxContainer.new()
	_invite_row.add_theme_constant_override("separation", 8)
	column.add_child(_invite_row)
	_invite_input = LineEdit.new()
	_invite_input.placeholder_text = "player name"
	_invite_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_input.text_submitted.connect(func(_t: String) -> void: _do_invite())
	_invite_row.add_child(_invite_input)
	InventoryLayout.button(_invite_row, "Invite", _do_invite)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_edit_hall = InventoryLayout.button(footer, "Edit Hall", func() -> void: if actions != null: actions.edit_hall())
	_leave = InventoryLayout.button(footer, "Leave Guild", func() -> void: if actions != null: actions.leave())
	_disband = InventoryLayout.button(footer, "Disband", func() -> void: if actions != null: actions.disband())
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	# One-shot: the server minted a hall-editor session; open it in a tab.
	if state != null:
		var token := state.guild.take_editor_token()
		if token != "" and actions != null:
			actions.open_editor(token)
	visible = state != null and state.guild.roster_open and state.guild.in_guild and state.local.is_present()
	if not visible:
		return
	PanelFit.shrink(_root)
	if state.guild.version != _drawn:
		_refresh()


func _refresh() -> void:
	_drawn = state.guild.version
	var guild := state.guild
	_title.text = guild.guild_name
	_standing.text = standing(GuildState.rank_name(guild.your_rank), guild.members.size())
	for child in _list.get_children():
		child.queue_free()
	for member in guild.members:
		var member_name := String(member["name"])
		var member_rank := int(member["rank"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var label := Label.new()
		label.text = "%s  -  %s" % [member_name, GuildState.rank_name(member_rank)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if guild.can_rank(member_rank):
			InventoryLayout.button(row, "+", func() -> void: if actions != null: actions.promote(member_name))
			InventoryLayout.button(row, "-", func() -> void: if actions != null: actions.demote(member_name))
		if guild.can_moderate(member_rank):
			InventoryLayout.button(row, "Kick", func() -> void: if actions != null: actions.kick(member_name))
	_invite_row.visible = guild.can_invite()
	_edit_hall.visible = guild.can_edit_hall
	_disband.visible = guild.is_owner()
	_leave.visible = not guild.is_owner()


## The line under the guild name: your rank and how many members there are.
static func standing(rank_name: String, member_count: int) -> String:
	return "You are %s   -   %d %s" % [rank_name, member_count, "member" if member_count == 1 else "members"]


func _do_invite() -> void:
	if actions != null and actions.invite(_invite_input.text):
		_invite_input.text = ""


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())


## Typing an invite name must not leak through as movement / hotkeys.
func is_typing() -> bool:
	return visible and _invite_input != null and _invite_input.has_focus()
