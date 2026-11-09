extends Node

## Renders scenarios and writes a PNG of each.
##
## Must run WITHOUT --headless: the headless display driver has no rendering
## device, so the viewport texture comes back null. A real window is required
## even though nothing interactive happens in it.
##
##   godot --path . res://tests/visual/capture.tscn -- <scenario> <out.png>
##   godot --path . res://tests/visual/capture.tscn -- --all <out_dir> <scenario>...
##
## Run as a scene, not with --script, so the autoloads (Sfx) exist.
##
## The second form is what capture-visuals.sh uses: one process and one window
## for the whole run, so the desktop is interrupted once rather than once a
## scenario. Each scenario is built under a stage of its own, captured, and
## freed before the next; the content is loaded once and only read.

const CAMERA_ZOOM := 2.0
const SETTLE_FRAMES := 6
## Arbitrary, but fixed -- see the clock note below.
const CAPTURE_TIME_MS := 250


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var jobs: Array = []
	if args.size() > 0 and args[0] == "--all":
		for scenario in args.slice(2):
			jobs.append([scenario, "%s/%s.png" % [args[1], scenario]])
	else:
		var scenario: String = args[0] if args.size() > 0 else "entities"
		jobs.append([scenario, args[1] if args.size() > 1 else "reports/visual/%s.png" % scenario])

	# CAPTURE_PHONE: a phone's canvas, device pixels over the 1.5x mobile UI at a
	# 2x pixel ratio, with the panels' TouchScale boost.
	if OS.get_environment("CAPTURE_PHONE") == "1":
		get_window().content_scale_factor = DisplayScale.MOBILE_UI
		TouchScale.panel_factor = TouchScale.panel_factor_for(2.0, DisplayScale.MOBILE_UI)
	# CAPTURE_PHONE=3 at --resolution 1688x780: an iPhone's 844x390 points (3x
	# ratio), laid out for touch.
	if OS.get_environment("CAPTURE_PHONE") == "3":
		TouchScale.panel_factor = 2.0
		PhoneLayout.on = true
		PanelFold.short_screen = true
	# CAPTURE_DPR: a phone exactly as Main sets one up -- the window its device
	# pixels, the canvas at the mobile UI scale, the panels boosted by this
	# pixel ratio over it.
	if OS.has_environment("CAPTURE_DPR"):
		DisplayScale.apply(get_window(), DisplayScale.MOBILE_UI, true)
		TouchScale.panel_factor = TouchScale.panel_factor_for(
			OS.get_environment("CAPTURE_DPR").to_float(), DisplayScale.MOBILE_UI)
		PhoneLayout.on = true
		PanelFold.short_screen = true
	# CAPTURE_FACTOR: the panels' boost for a smaller window standing in for a
	# phone, e.g. 1 at --resolution 390x844 for a phone held upright.
	if OS.has_environment("CAPTURE_FACTOR"):
		TouchScale.panel_factor = OS.get_environment("CAPTURE_FACTOR").to_float()
		PhoneLayout.on = true
		PanelFold.short_screen = true
	var config := ClientConfig.new()
	# A checkout laid out differently from the default names its data here.
	if OS.has_environment("GRAVEBOUND_DATA_ROOT"):
		config.data_root = OS.get_environment("GRAVEBOUND_DATA_ROOT")
	var content := GameData.new()
	if not await content.load_from(FileContentSource.new(config.resolved_data_root())):
		push_error("content load failed: %s" % "\n".join(content.errors))
		get_tree().quit(1)
		return

	var failed := 0
	for job in jobs:
		if not await capture(job[0], job[1], content):
			failed += 1
	get_tree().quit(1 if failed > 0 else 0)


## One scenario, built under a stage of its own so the next starts clean.
func capture(scenario: String, output: String, content: GameData) -> bool:
	# A phone scenario is laid out as a phone in any window, so the desktop run
	# has its references too; the next scenario gets the run's layout back.
	var run_layout := [PhoneLayout.on, PanelFold.short_screen, TouchScale.panel_factor]
	if scenario.begins_with("phone_"):
		PhoneLayout.on = true
		PanelFold.short_screen = true
		TouchScale.panel_factor = 2.0
	var captured: bool = await _capture(scenario, output, content)
	PhoneLayout.on = run_layout[0]
	PanelFold.short_screen = run_layout[1]
	TouchScale.panel_factor = run_layout[2]
	return captured


func _capture(scenario: String, output: String, content: GameData) -> bool:
	var stage := Node.new()
	# Deferred + a frame's wait: on some platforms the root is still setting up
	# its own children when the first scenario is built, and a direct add_child
	# then aborts ("parent busy setting up children").
	get_tree().root.add_child.call_deferred(stage)
	await get_tree().process_frame
	var state := RealmState.new(content, func() -> int: return 0)
	state.party.wall_clock = func() -> int: return VisualScenarios.PARTY_WALL_MS
	VisualScenarios.apply(scenario, state)

	var renderer := WorldRenderer.new()
	renderer.setup(state, content)
	# Spin is a function of the wall clock, so a spinning group would render
	# differently on every capture. Pin it, as RealmState's clock already is.
	# Non-zero, or a spin scenario would have nothing to show.
	renderer.bullets.clock = func() -> int: return CAPTURE_TIME_MS
	# Water and lava move on the shader's own clock, so it is held the same way.
	renderer.liquid.material.set_shader_parameter("pinned_time", CAPTURE_TIME_MS / 1000.0)
	renderer.show_collision = scenario == "collision"
	stage.add_child(renderer)

	# The names, bars, chips, bubbles and numbers: UI over the world.
	var tags := EntityOverlay.new()
	tags.setup(state, content)
	stage.add_child(tags)

	var chat := ChatPanel.new()
	chat.setup(state)
	stage.add_child(chat)

	# Invisible unless the scenario asked to leave a realm, so every other
	# capture is unaffected -- and the transition scenario shows what the
	# player actually sees during one.
	var splash := TransitionScreen.new()
	splash.setup(state, content)
	# Pinned like the bullet layer's, and for the same reason: a fade driven
	# by the frame delta lands on a different alpha every capture.
	splash.clock = func() -> int: return CAPTURE_TIME_MS
	stage.add_child(splash)

	# Driven by the session rather than by world state, so the scenario cannot
	# raise it and the capture has to.
	var grave := DeathScreen.new()
	stage.add_child(grave)

	# Up whenever there is a local player, as in the client -- which is most
	# scenarios -- so it is asked for by name instead, the way the collision
	# overlay is, and every other capture is unchanged.
	var bag := InventoryPanel.new()
	bag.setup(state, content, InventoryActions.new(state, null, content))
	bag.shown = scenario in ["inventory", "item_card", "vault"]
	stage.add_child(bag)
	chat.avoid = bag.covered
	# The chest at our feet: only for its scenario, as the bag is.
	if scenario == "vault" or scenario.begins_with("phone_loot"):
		var loot := LootWindow.new()
		loot.setup(state, content, InventoryActions.new(state, null, content), bag.beside)
		stage.add_child(loot)
	# A phone's buttons, Nexus on the potions' row: built as a phone, since a
	# capture runs on the desktop.
	if scenario == "touch_phone":
		var layer := CanvasLayer.new()
		var cluster := TouchCluster.new(true)
		layer.add_child(cluster)
		stage.add_child(layer)
		cluster.place(Vector2(get_viewport().get_visible_rect().size), Vector2(TouchCluster.MARGIN, 8.0))
		cluster.refresh(content, state)
	if scenario == "companions":
		var companions := CompanionPanel.new()
		companions.setup(state, content, CompanionActions.new(null))
		companions.shown = true
		stage.add_child(companions)
	var bar := AbilityBar.new()
	bar.setup(state, content, null)
	bar.shown = scenario == "abilities"
	stage.add_child(bar)
	# Open only when the scenario's packets opened them, and the prompt only
	# when a scenario laid an interactive tile in reach.
	var shop := ShopActions.new(state, null, content)
	var shelves := ItemStorePanel.new()
	shelves.setup(state, content, null, shop)
	stage.add_child(shelves)
	var fame := FameStorePanel.new()
	fame.setup(state, content, shop)
	stage.add_child(fame)
	var prompt := InteractPrompt.new()
	prompt.setup(state, shop)
	stage.add_child(prompt)
	var forge := ForgePanel.new()
	forge.setup(state, content, ForgeActions.new(state, null, content))
	stage.add_child(forge)
	var market := ExchangeMarketPanel.new()
	market.setup(state, content, shop)
	stage.add_child(market)
	var trade := TradePanel.new()
	trade.setup(state, content, TradeActions.new(state, null))
	stage.add_child(trade)
	var party := PartyPanel.new()
	party.setup(state, content, PartyActions.new(state, null))
	stage.add_child(party)
	var invite := PartyInvitePopup.new()
	invite.setup(state, PartyActions.new(state, null))
	stage.add_child(invite)
	var dev := DevOverlay.new()
	stage.add_child(dev)
	# Only asked for by name: its chip would otherwise be up in every scenario
	# with a player, and move every golden that has one.
	if scenario == "quests" or scenario.begins_with("phone_"):
		var log := QuestLogPanel.new()
		log.setup(state, content, null)
		log.shown = scenario == "quests"
		stage.add_child(log)
	var masteries := MasteryPanel.new()
	masteries.setup(state)
	masteries.shown = scenario == "masteries"
	stage.add_child(masteries)
	var options := OptionsPanel.new()
	options.setup(state.settings, null)
	stage.add_child(options)
	var phone := scenario.begins_with("phone_")
	var nearby := NearbyPanel.new()
	nearby.setup(state, content, TradeActions.new(state, null), PartyActions.new(state, null), null, null, party)
	nearby.shown = scenario == "nearby" or phone
	stage.add_child(nearby)
	# Named after the map, so it would be up in every scenario that has a
	# player; asked for by name instead, like the bag and the bar.
	var banner := RealmBanner.new()
	banner.setup(state, content)
	banner.shown = scenario == "portals" or phone
	stage.add_child(banner)
	# Up whenever there is a player, and asked for by name like the bag.
	var hud := PlayerHud.new()
	hud.setup(state, content)
	hud.shown = scenario == "player_hud" or phone
	stage.add_child(hud)
	# Up whenever there is a map, like the bar, and asked for by name like it.
	var map := MinimapPanel.new()
	map.setup(state, null)
	map.shown = scenario in ["minimap", "minimap_hop"] or phone
	stage.add_child(map)
	var opened_map := MinimapExpanded.new()
	opened_map.setup(state, null)
	stage.add_child(opened_map)
	# The whole phone screen: the touch layer over the HUD, as Main builds it.
	var touch: TouchControls = null
	if phone:
		touch = TouchControls.new()
		touch.setup(state, null, content, bag, null, null)
		stage.add_child(touch)
		touch.pixel_ratio = 2.0
		touch.enable(true)
		bag.shown = scenario in ["phone_bag", "phone_loot_bag"]
		var none := func() -> void: pass
		touch.link([["Character", none], ["Skills", none], ["Quests", none], ["Leaderboard", none],
			["Options", none], ["Companion", none]], chat.toggle_line)

	# The sign-in screen, torches burning: only for its own scenario, since
	# in the client it covers everything until a character is chosen.
	var login: LoginScreen = null
	if scenario.begins_with("login") or scenario in ["terms", "how_to"]:
		# A service that answers from a script: the server list, then nothing,
		# so the picker shows and nothing reaches the network.
		var service := DataService.new()
		var http := FakeHttpBackend.new()
		http.push_json(200, VisualScenarios.servers())
		service.backend = http
		stage.add_child(service)
		login = LoginScreen.new(service, content)
		stage.add_child(login)

	# The Menu's leaderboard over a realm, its entries scripted.
	var board: LeaderboardWindow = null
	if scenario == "leaderboard":
		board = LeaderboardWindow.new(state, content, null)
		board.shown = true
		stage.add_child(board)

	# Buy Fame over a realm, its packages scripted: browsing, or waiting on a checkout.
	if scenario.begins_with("buy_fame"):
		var fame_service := DataService.new()
		fame_service.backend = FakeHttpBackend.new()
		fame_service.account = {"accountFame": 12850}
		stage.add_child(fame_service)
		var buy_fame := FamePurchasePanel.new()
		buy_fame.data_service = fame_service
		buy_fame.open_url = func(_url: String) -> bool: return true
		buy_fame.show_catalogue(VisualScenarios.fame_packages())
		stage.add_child(buy_fame)
		buy_fame.open()
		if scenario == "buy_fame_waiting":
			buy_fame.phase = FamePurchasePanel.Phase.WAITING
			buy_fame.checkout_url = "https://checkout.stripe.com/c/pay/cs_test"
			buy_fame._show_waiting(true)

	var camera := Camera2D.new()
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.position = state.local.centre() if state.local.is_present() else Vector2.ZERO
	stage.add_child(camera)

	# Nothing added above has run _ready yet -- a node added from here is
	# initialised when the tree next processes it, and driving one before that
	# writes to controls that do not exist. One frame is the whole fix.
	await get_tree().process_frame
	chat.refresh()
	# The pin pulses on the clock; pinned like the bullet layer's.
	map._canvas.clock = func() -> int: return CAPTURE_TIME_MS
	# The line the player types into, open and half-typed, under the log.
	if scenario == "chat_typing":
		chat._input.open()
		chat._input.text = "on my way, hold the portal"
	if scenario == "phone_chat":
		chat.toggle_line()
		chat._input.text = "on my way, hold the portal"
	if scenario == "phone_menu":
		touch._phone_menu.open()
	if scenario == "phone_map":
		opened_map._canvas.clock = map._canvas.clock
		opened_map.open(0.5)
	if scenario == "death":
		grave.fell("Ruu")
	# The card over the second cell, pinned where a cursor would be: the bar
	# otherwise follows the real mouse every frame, which no capture can fix.
	# The card over the equipped weapon, as a hover leaves it.
	if scenario == "item_card":
		bag._process(0.0)
		bag._tooltip.show_for(state.local.inventory.item_at(0), Vector2(700, 180))
		bag.set_process(false)
	if scenario == "abilities":
		bar._process(0.0)
		bar._tooltip.show_lines(bar.describe(2), Vector2(400, 620))
		bar.set_process(false)
	# Ninety frames of fire from a seeded field on a pinned clock, then the
	# backdrop stops stepping so the settle frames change nothing. Reset
	# first -- the particles and each emitter's carried fraction: the frame
	# above stepped them once with the real frame time, which is near zero in
	# a fresh process and a whole frame after other scenarios.
	if login != null:
		login._backdrop.clock = func() -> float: return CAPTURE_TIME_MS * 0.001
		login._backdrop.field.clear()
		login._backdrop._torch_acc.clear()
		login._backdrop._candle_acc.clear()
		login._backdrop.field.rng.seed = 7
		for frame in 90:
			login._backdrop.step(1.0 / 60.0)
		login._backdrop.set_process(false)
	# Signed in, the list as it first opens.
	if scenario == "login_account":
		login.data_service.account = {"accountFame": 12450}
		login.buy_fame_shown = func() -> bool: return true
		login._listed({"success": true, "characters": VisualScenarios.account()})
	# Signed in, the second character picked and Delete pressed once.
	if scenario == "login_delete":
		login._listed({"success": true, "characters": VisualScenarios.account()})
		login._stage.picker.list.select(1)
		login._stage.ask_delete()
	# Signed in, and the first character right-clicked: its lifetime stats.
	if scenario == "login_stats":
		login._listed({"success": true, "characters": VisualScenarios.account()})
		var card := login._stage.stats_card
		card.title.text = "Barbarian - Lifetime Stats"
		card.show_report(VisualScenarios.lifetime_report())
		card.visible = true
	# The Terms of Use as an account that has not accepted them meets them:
	# from the top, I Agree still dead.
	if scenario == "terms":
		login._terms.ask()
	# How to Play as the "?" leaves it: open at the top.
	if scenario == "how_to":
		login._how_to.open()
	# The server's best, and the first row's card open where a hover would leave it.
	if scenario == "leaderboard":
		board.panel.show_entries(VisualScenarios.leaderboard_entries())
		var card := LeaderboardCard.build(VisualScenarios.leaderboard_entries()[0], content)
		card.position = Vector2(860, 560)
		board.add_child(card)
	# The options as Escape leaves them. It shows only in a realm, and a
	# capture has no client, so it is raised by hand.
	if scenario.begins_with("options"):
		options.set_process(false)
		options.visible = true
	# The /dev readout, with no client to read: raised by hand on fixed numbers
	# that land one of each colour.
	if scenario == "dev_overlay":
		dev.set_process(false)
		dev.visible = true
		dev._text.text = DevOverlay.line(42.0, 38, 4, Vector2i(1280, 960), 1.0, 1620)
	# The Controls tab mid-rebind: one button waiting for its key.
	if scenario == "options_controls":
		options.controls.get_parent().current_tab = 1
		options.controls.listen("drink_hp")
	# The menu open on a player in the list, as a click would leave it.
	if scenario == "nearby":
		nearby._process(0.0)
		nearby.open_menu(state.entities.players[2])
	# The wait as the screen sees it, then whatever the scenario says happens
	# next -- a named splash is the frame AFTER the realm lands.
	splash._process(0.0)
	VisualScenarios.advance(scenario, state)
	splash._process(0.0)
	# The second step can move the player -- an arrival puts us somewhere new
	# -- and the camera follows it every frame in the real client.
	camera.position = state.local.centre() if state.local.is_present() else Vector2.ZERO

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
		camera.make_current()

	var image := get_tree().root.get_texture().get_image()
	stage.queue_free()
	await get_tree().process_frame
	if image == null:
		push_error("viewport capture returned null -- this must run windowed, not --headless")
		return false

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var error := image.save_png(output)
	if error != OK:
		push_error("could not write %s: %s" % [output, error_string(error)])
		return false
	print("captured %s -> %s (%dx%d)" % [scenario, output, image.get_width(), image.get_height()])
	return true
