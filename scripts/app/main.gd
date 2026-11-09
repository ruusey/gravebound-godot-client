extends Node

## Entry point: builds the stack and runs the frame loop.
##
## Construction and per-frame ordering only -- the session flow lives in
## SessionController, gameplay input in PlayerInput, the realm transitions in
## PortalInput, and the screens over the world in Screens.

const CAMERA_ZOOM := DisplayScale.WORLD_ZOOM

var config: ClientConfig
var game_data: GameData
var client: GraveBoundClient
var state: RealmState
var session: SessionController
var input: PlayerInput
var portals: PortalInput
var inventory_actions: InventoryActions
var inventory_input: InventoryInput
var caster: AbilityCaster
var shop: ShopActions
var forge_actions: ForgeActions
var chat_actions: ChatActions
var ability_input: AbilityInput
var screens: Screens
var trace := MotionTrace.new()

var _world: WorldRenderer
var _lighting: SceneLighting
var _camera: Camera2D
var _view_3d: WorldView3D
var _data_service: DataService
var _http: HttpBackend


func _ready() -> void:
	# Assigned ahead of _ready by tests; otherwise taken from the command line.
	if config == null:
		config = ClientConfig.from_command_line()
	if OS.has_feature("web"):
		_hide_web_input_caret()
	var display := DisplayScale.new()
	var mobile := OS.has_feature("web") or OS.has_feature("android")
	display.device_scale = DisplayScale.pixel_ratio(OS.has_feature("web"), JavaScriptBridge.eval,
		OS.has_feature("android"), DisplayServer.screen_get_dpi())
	add_child(display)
	# Short by the screen's own rows: a phone in landscape, or a small window.
	# Not under a headless display, whose 64-row window the unit suite shares:
	# the default is process-wide, and one Main would fold every panel after it.
	if DisplayServer.get_name() != "headless":
		PanelFold.short_screen = PanelFold.default_folded(float(get_window().size.y) / display.device_scale)
	# A phone's sticks, or --touch to try them here with the mouse as a finger;
	# decided before the screens are built, which lay out for them.
	var touchscreen := DisplayServer.is_touchscreen_available()
	var pixel_ratio := display.device_scale if mobile else DisplayServer.screen_get_scale()
	var touch_on := TouchControls.wanted(config.touch, touchscreen, OS.has_feature)
	PhoneLayout.on = touch_on
	if touch_on:
		TouchScale.panel_factor = TouchScale.panel_factor_for(pixel_ratio, display.default_ui())

	game_data = GameData.new()
	state = RealmState.new(game_data)
	state.settings.load_from(config.settings_path)
	display.follow(state.settings)
	client = GraveBoundClient.new()
	client.connection.transport = config.open_transport()
	client.name = "GraveBoundClient"
	add_child(client)
	# Stepped from _process below, at the frame's start, not by the engine.
	client.set_process(false)

	_data_service = DataService.new()
	_data_service.base_url = ServerAddress.data_url(config)
	add_child(_data_service)
	_http = GodotHttpBackend.new(self)

	_world = WorldRenderer.new()
	_world.setup(state, game_data)
	add_child(_world)

	# A sibling over the same world canvas: its ambient and point lights darken
	# and relight the tiles, not the UI (which is on CanvasLayers of its own).
	_lighting = SceneLighting.new()
	_lighting.setup(state, game_data)
	add_child(_lighting)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	_camera.position_smoothing_enabled = false
	add_child(_camera)
	_camera.make_current()
	# Positional SFX (other players' shots) are heard from the camera, which rides
	# the player; without a listener 2D audio attenuates from the screen origin.
	var listener := AudioListener2D.new()
	_camera.add_child(listener)
	listener.make_current()
	display.camera = _camera   # the world's zoom, apart from the UI's

	inventory_actions = InventoryActions.new(state, client, game_data)
	caster = AbilityCaster.new(state, client, game_data, _world)
	shop = ShopActions.new(state, client, game_data)
	inventory_actions.shop = shop
	forge_actions = ForgeActions.new(state, client, game_data)
	chat_actions = ChatActions.new(state, client)
	screens = Screens.new()
	screens.build(state, game_data, client, _data_service, inventory_actions, caster, shop,
		forge_actions, _world, chat_actions)
	add_child(screens)
	screens.login.client_config = config   # lets the server picker retarget the connection
	screens.death.dismissed.connect(screens.login.return_after_death)
	screens.death.quit.connect(screens.login.forget_characters.bind("Signed out."))
	screens.login.last_email.path = LastEmail.DEFAULT_PATH if config.settings_path != "" else ""
	# Desktop only: keep the session token for auto-login next launch. Empty (a
	# no-op) on web -- a shared browser -- and in tests (no settings path).
	screens.login.saved_session.path = SavedSession.DEFAULT_PATH \
		if config.settings_path != "" and not OS.has_feature("web") else ""
	screens.login.prefill(config.email if config.email != "" else screens.login.last_email.read(), config.password)

	session = SessionController.new(client, state, screens.login, config)
	session.data_service = _data_service   # the handshake prefers the live session token
	session.entered_realm.connect(_on_entered_realm)
	session.died.connect(screens.death.fell)
	input = PlayerInput.new(state, client, _world, game_data)
	portals = PortalInput.new(state, client, game_data)
	inventory_input = InventoryInput.new(client, inventory_actions, screens.inventory)
	inventory_input.shop = shop
	inventory_input.companion_actions = screens.companion_actions
	inventory_input.companions = state.companions
	ability_input = AbilityInput.new(client, caster, screens.skills)
	# A click on a panel is not a shot at, or a cast into, the world behind it.
	input.mouse_captured = screens.captures_mouse
	ability_input.mouse_captured = screens.captures_mouse
	# The melee-reach reticle aims where a shot would: the 3D ground raycast when
	# that's live (set on input by WorldView3D), else the 2D world mouse.
	screens.overlay.world_aim = func() -> Variant:
		var aimed: Variant = input.world_mouse.call()
		return aimed if aimed is Vector2 else _world.get_global_mouse_position()
	# And a key typed into the chat line is a letter, not a move or a cast.
	for ticker in [input, portals, inventory_input, ability_input]:
		ticker.keyboard_captured = screens.captures_keyboard
	screens.touch.pixel_ratio = pixel_ratio
	screens.touch.enable(touch_on, not touchscreen)
	# The on-screen Nexus button escapes to safety -- a phone has no portal to stand on.
	screens.touch.set_escape(portals.to_nexus)
	input.touch_aim = screens.touch.aim_point
	caster.aim_point = screens.touch.cast_point
	# Leaving the tutorial with onboarding quests still open asks first.
	portals.confirm_exit = screens.tutorial_exit.request
	# The prompt over the bar is the phone's F and Space.
	screens.prompt.portals = portals
	screens.prompt.touch = screens.touch.enabled

	if OS.has_feature("web") and _url_wants_3d():
		config.enable_3d = true
	if config.enable_3d:
		_enable_3d_view()

	# The moment before the frame is drawn, for the motion trace: the
	# transform the world is about to be drawn with, against the player.
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	# Desktop-only self-update against the GitHub releases page; no-ops on web/dev.
	var updater := UpdateChecker.new()
	add_child(updater)
	updater.check()
	_load_content()


## The web virtual keyboard rides on a transparent DOM <input> Godot overlays
## on the focused LineEdit; on a scaled canvas the browser draws that element's
## own caret offset from Godot's -- a stray marker below-left of the field.
## Make the DOM element's caret and text invisible so only Godot's own caret,
## drawn in the canvas, shows. Godot's are the only text inputs on the page.
func _hide_web_input_caret() -> void:
	JavaScriptBridge.eval("""
		(function () {
			if (document.getElementById('or-input-caret-fix')) return;
			var style = document.createElement('style');
			style.id = 'or-input-caret-fix';
			style.textContent = 'input, textarea { caret-color: transparent !important; color: transparent !important; -webkit-text-fill-color: transparent !important; }';
			document.head.appendChild(style);
		})();
	""", true)


## The web page's ?3d=1 (or &3d=1) query, so the prototype can be reached on a
## phone without a command line.
func _url_wants_3d() -> bool:
	var search: Variant = JavaScriptBridge.eval("location.search")
	return search is String and "3d=1" in search


## Swaps the 2D world for the 3D one: hide and stop the flat renderer so it is
## not the sole consumer of the tile-change flags, and stand the 3D view up in
## the same viewport, under the HUD.
func _enable_3d_view() -> void:
	_world.hide()
	_world.set_process(false)
	# The 2D lights have nothing to light once the flat world is hidden.
	_lighting.hide()
	_lighting.set_process(false)
	_view_3d = WorldView3D.new()
	_view_3d.setup(state, game_data)
	# The overlay (names, bars, damage numbers, bubbles, loot) keeps drawing, but
	# through the 3D camera: the view fits it an affine projector and refreshes it
	# each frame. Its own _process is stopped so it never runs a frame stale.
	screens.overlay.set_process(false)
	_view_3d.overlay = screens.overlay
	# So WASD turns with the orbit -- screen-up is always forward.
	_view_3d.input = input
	_view_3d.keyboard_captured = screens.captures_keyboard
	# Abilities aim at the ground point under the cursor through the 3D camera,
	# the same unprojection shooting already uses -- not the flat 2D mouse.
	caster.world_mouse = _view_3d.get_ground_point
	add_child(_view_3d)


func _on_pre_draw() -> void:
	if client.is_in_game():
		trace.sample_draw(get_viewport().get_canvas_transform(), state.local.render_centre(),
			get_viewport().get_visible_rect().size)


## Fetched rather than read, in a browser, so this cannot block the first
## frame. Everything built above holds the GameData object and reads through
## it, so the UI is already up while it fills; against the data repo on disk
## nothing suspends and it is finished before _ready returns.
func _load_content() -> void:
	var source := config.open_content_source(_http)
	if await game_data.load_from(source):
		print("[content] %s from %s" % [game_data.summary(), source.describe()])
	else:
		push_error("Content failed to load from %s:\n  %s" % [
			source.describe(), "\n  ".join(game_data.errors)])
	if not game_data.errors.is_empty():
		screens.login.set_status("Content warnings:\n  %s" % "\n  ".join(game_data.errors.slice(0, 3)), true)

	# The sound map and its oggs load through the same source as the rest; done
	# here so a data-only change to sounds.json needs no client release. Not
	# awaited -- the oggs stream in while the player logs in, and every trigger
	# no-ops until they have landed.
	Sfx.configure(game_data, state.settings, source)

	if session.can_autoconnect():
		session.begin(config.email, config.password, config.character_uuid)
	elif not screens.login.saved_session.read().is_empty():
		await _resume_saved_session()


## Desktop auto-login: reuse the kept session token to list the account's
## characters without the password. Runs after content loads so the picker shows
## class names, not ids; an expired token falls back to the sign-in form (resume).
func _resume_saved_session() -> void:
	var saved: Dictionary = screens.login.saved_session.read()
	_data_service.token = saved["token"]
	_data_service.account_guid = saved["account_guid"]
	config.token = saved["token"]
	await screens.login.resume(saved["email"])


## Snap rather than ease, so the first frame in a realm is already framed on
## the player instead of panning in from the origin.
func _on_entered_realm(_response: Dictionary) -> void:
	PixelSnap.camera(_camera, state.local.render_centre(), state.local.render_position())


## The character is gone from the account, so the list we hold is stale and
## the picker has to be filled again from the data service.
## The order is the frame's consistency. The network first, so every ack
## has been reconciled before prediction runs; then prediction; then the
## camera on the result, applied at once rather than at the camera's own
## step, so the world, the camera and the tags over it are drawn from one
## state. Doing the network after the camera drew the sprite up to 3px off
## the camera's centre on every correction frame.
func _process(delta: float) -> void:
	client.tick(delta)
	input.tick(delta)
	portals.tick(delta)
	inventory_input.tick(delta)
	ability_input.tick(delta)
	if client.is_in_game():
		# While slowed the player creeps sub-pixel per tick, where the pixel grid's
		# whole-pixel camera steps round unevenly and read as jitter; scroll the ground
		# smoothly then (sprites stay snapped/crisp). Normal speed keeps the crisp grid.
		if state.movement.is_slowed():
			PixelSnap.smooth(_camera, state.local.render_centre())
		else:
			PixelSnap.camera(_camera, state.local.render_centre(), state.local.render_position())
		trace.observe(delta, state)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	# A key typed into the chat line (or being rebound in the options) is text, not
	# a command; only ESC still gets through, to close the panel it opened.
	if event.keycode != KEY_ESCAPE and screens.captures_keyboard():
		return
	match event.keycode:
		KEY_F1:
			print("\n[packet mix]\n%s" % client.stats.mix())
		KEY_F2:
			_world.show_collision = not _world.show_collision
		KEY_F3:
			state.settings.set_on("lighting", not state.settings.is_on("lighting"))
		# Tilde rather than an F key: on a Mac the F row is brightness and
		# volume unless fn is held, which is not something to do mid-fight.
		KEY_QUOTELEFT:
			var where := Screenshot.take(get_viewport())
			print("[screenshot] %s" % (where if where != "" else "nothing to capture"))
			# And the motion of the next second, which no screenshot can show.
			trace.start(state.movement.corrections)
		KEY_ESCAPE:
			if client.is_in_game():
				screens.options.toggle()
