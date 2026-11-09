class_name LoginScreen
extends CanvasLayer

## The account/character picker: sign in to the data service, list the
## characters, hand the chosen uuid to the game server. AccountForm is the
## sign-in side, CharacterStage the account's -- the whole panel, sized for
## a thumb; the leaderboard is on the in-game Menu. Signed in, the form
## gives way to a SignedInRow and the email is kept (LastEmail). TermsGate covers an account yet to accept the
## Terms of Use; the "?" opens How to Play (HowToPanel).

signal character_chosen(email: String, password: String, character_uuid: String)

const HOW_TO_BUTTON := int(TouchSize.ROW)
## The public game wiki, served only on the production domain. Opened in a new
## browser tab on web, the OS browser on desktop.
const WIKI_URL := "https://grave-bound.com/wiki/"
## The phone's card: as wide as a landscape phone, the logo, the server and
## the account in one header row so the form or the characters get the rest.
const PHONE_WIDTH := 800.0
const PHONE_LOGO := Vector2(264, 88)
const PHONE_FORM_WIDTH := 380.0
const PHONE_SERVER_WIDTH := 210.0

var data_service: DataService
var game_data: GameData
## Set by Main after build so the server picker can retarget the connection.
var client_config: ClientConfig
var last_email := LastEmail.new()
## Desktop auto-login: the session token of the last sign-in, reused on launch so
## the password is not retyped. Path is left empty (a no-op) on web and in tests;
## Main sets it only on desktop. See resume().
var saved_session := SavedSession.new()
## Wired by Screens: opens the Buy Fame panel, and whether fame is on sale.
var buy_fame := Callable()
var buy_fame_shown := Callable()

var _backdrop: LoginBackdrop
var _server_select: ServerSelect
var _form: AccountForm
var _account: SignedInRow
var _panel: PanelContainer
var _status: Label
var _stage: CharacterStage
var _how_to: HowToPanel
var _how_to_button: Button
var _terms: TermsGate


func _init(service: DataService = null, content: GameData = null) -> void:
	data_service = service
	game_data = content


func _ready() -> void:
	layer = 20
	_backdrop = LoginBackdrop.attach(self, game_data)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PHONE_WIDTH if PhoneLayout.on else 420.0, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Centred on a phone, shrunk to fit (PanelFit) rather than run off an edge.
	# Elsewhere a ScrollContainer, so a short window can reach the whole panel;
	# the panel still centres across the width.
	if PhoneLayout.on:
		var centre := CenterContainer.new()
		centre.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(centre)
		centre.add_child(_panel)
	else:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		var holder := VBoxContainer.new()
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		scroll.add_child(holder)
		holder.add_child(_panel)

	var column := InventoryLayout.column(_panel)

	# On a phone a row that wraps: held upright, the server and the account
	# drop under the logo.
	var header: Container = HFlowContainer.new() if PhoneLayout.on else HBoxContainer.new()
	for gap in ["separation", "h_separation", "v_separation"]:
		header.add_theme_constant_override(gap, 12)
	column.add_child(header)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(HOW_TO_BUTTON, 0)
	if not PhoneLayout.on:
		header.add_child(spacer)
	var title := TextureRect.new()
	var logo := HudWidgets.logo_texture()
	if logo != null:
		title.texture = logo
	title.custom_minimum_size = Vector2(0, 104)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if PhoneLayout.on:
		title.custom_minimum_size = PHONE_LOGO
		title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var wiki_button := InventoryLayout.button(header, "Wiki", _open_wiki)
	wiki_button.tooltip_text = "Open the game wiki"
	wiki_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_how_to_button = HowToPanel.badge(header, HOW_TO_BUTTON, func() -> void: _how_to.open())

	# Server picker above the sign-in fields; applies the choice to the config
	# the connection reads. Hides itself when /servers is empty/unreachable.
	_server_select = ServerSelect.new(data_service, _apply_server)
	column.add_child(_server_select)

	_form = AccountForm.new(data_service)
	_form.submitted.connect(_on_login_pressed)
	_form.status_changed.connect(set_status)
	column.add_child(_form)
	_account = SignedInRow.new(func() -> void:
		data_service.sign_out()
		saved_session.forget()
		forget_characters("Signed out."), func() -> void:
			if buy_fame.is_valid():
				buy_fame.call())
	column.add_child(_account)

	if PhoneLayout.on:
		_phone_header(header, spacer)

	_stage = CharacterStage.new(data_service, game_data)
	_stage.status_changed.connect(set_status)
	_stage.chosen.connect(func(uuid: String) -> void:
		character_chosen.emit(_form.email_text(), _form.password_text(), uuid))
	column.add_child(_stage)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 24.0 if PhoneLayout.on else 40.0)
	column.add_child(_status)

	_how_to = HowToPanel.new()
	add_child(_how_to)
	_terms = TermsGate.new()
	add_child(_terms)
	# Every field and button a thumb's height: a phone signs in here too.
	for part in [_form, _account, _how_to, _terms]:
		TouchSize.grow_all(part)
	if PhoneLayout.on:
		TouchSize.grow_all(_server_select)
	TouchFrame.adopt(self)


## The server and the signed-in account move up into the header beside the
## logo, the form narrows to a column under it, centred.
func _phone_header(header: Container, spacer: Control) -> void:
	_server_select.compact()
	_server_select.custom_minimum_size.x = PHONE_SERVER_WIDTH
	_server_select.reparent(header)
	header.move_child(_server_select, 1)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.move_child(spacer, 2)
	_account.reparent(header)
	header.move_child(_account, 3)
	_form.custom_minimum_size.x = PHONE_FORM_WIDTH
	_form.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _process(_delta: float) -> void:
	if not visible:
		return
	_account.show_buy_fame(buy_fame_shown.is_valid() and buy_fame_shown.call())
	_stage.refresh_fame()
	if PhoneLayout.on:
		var room := TouchScale.panel_view(_panel).x - PanelFit.MARGIN * 2.0
		_panel.custom_minimum_size.x = minf(PHONE_WIDTH, room)
		_form.custom_minimum_size.x = minf(PHONE_FORM_WIDTH, room - 24.0)
	PanelFit.shrink(_panel)   # a short window shrinks it rather than losing the bottom


func prefill(email: String, password: String) -> void:
	_form.prefill(email, password)


func forget_characters(status: String) -> void:
	_stage.forget()
	_form.visible = true
	_account.visible = false
	visible = true
	set_status(status)


## Point the connection at the picked server. On TLS web that means swapping the
## nginx wss route; on native it's the node's own host:port. Mirrors ServerAddress.
func _apply_server(server: Dictionary) -> void:
	if client_config == null:
		return
	# Direct localhost: skip the proxy route and TLS entirely. The desktop build
	# dials the game server's raw TCP listener (2222); a browser has no raw socket,
	# so there it falls back to the plain WebSocket listener (2223). Either way no
	# wss and no ingress path, which is what makes a local server reachable.
	if server.get("local", false):
		client_config.host = "127.0.0.1"
		client_config.port = 0
		client_config.secure = false
		client_config.socket_path = ""
		client_config.websocket = OS.has_feature("web")
		return
	client_config.websocket = true
	if client_config.secure:
		client_config.socket_path = str(server.get("route", client_config.socket_path))
	else:
		client_config.host = str(server.get("host", client_config.host))
		client_config.port = int(server.get("webSocketPort", client_config.port))
		client_config.socket_path = ""


## Open the wiki in a new browser tab on web (so the game is not navigated away
## from), the OS browser on desktop. Mirrors GuildActions.open_editor.
func _open_wiki() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(%s, '_blank')" % JSON.stringify(WIKI_URL))
	else:
		OS.shell_open(WIKI_URL)


func set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1, 0.5, 0.5) if is_error else Color(0.8, 0.8, 0.8))


func _on_login_pressed() -> void:
	if _form.email_text() == "":
		set_status("Enter an email address.", true)
		return
	_form.set_busy(true)
	set_status("Signing in to %s ..." % data_service.base_url)
	_listed(await AccountSignIn.sign_in(data_service, _form.email_text(), _form.password_text(),
		_terms.ask))


## Desktop auto-login: list the account's characters with the saved session token,
## no password. The data service and game server both accept the session token, so
## on success the picker opens signed in; on an expired/invalid token the saved
## session is dropped and the ordinary sign-in form is shown (prefilled email).
func resume(email: String) -> void:
	_form.prefill(email, "")
	_form.set_busy(true)
	set_status("Signing in as %s ..." % email)
	var got: Dictionary = await AccountSignIn.characters(data_service)
	if got["success"]:
		last_email.save(email)
		_listed(got)
	else:
		saved_session.forget()
		data_service.sign_out()
		_form.set_busy(false)
		_form.visible = true
		set_status("Saved sign-in expired -- please sign in.")


## Select Character on the death screen: the account again, the session
## still held, the fallen one now in the graveyard; sign in only if that fails.
func return_after_death() -> void:
	visible = true
	_form.set_busy(true)
	set_status("Loading characters ...")
	var got: Dictionary = await AccountSignIn.characters(data_service)
	if not got["success"]:
		_form.set_busy(false)
		forget_characters("Your character was lost. Sign in to choose another.")
		return
	_listed(got)


func _listed(got: Dictionary) -> void:
	_form.set_busy(false)
	if got["success"]:
		last_email.save(_form.email_text())
		# Desktop only (path is empty elsewhere): keep the token, not the password,
		# so the next launch can resume() without a sign-in.
		saved_session.save(_form.email_text(), data_service.account_guid, data_service.token)
		_form.visible = false
		_account.show_for(_form.email_text())
		_stage.game_data = game_data
		_stage.show_account(got["characters"])
	else:
		set_status(got["result"], true)
