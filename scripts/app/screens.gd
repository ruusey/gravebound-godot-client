class_name Screens
extends Node

## Every overlay over the world, built in one place: each a CanvasLayer
## reading the realm state on its own, constructed here in layer order,
## and asked together whether a click belongs to a panel.

var overlay: EntityOverlay
var hud: DebugHud
var dev: DevOverlay
var chat: ChatPanel
var inventory: InventoryPanel
var skills: SkillsPanel
var masteries: MasteryPanel
var quests: QuestLogPanel
var abilities: AbilityBar
var store: ItemStorePanel
var fame: FameStorePanel
var forge: ForgePanel
var market: ExchangeMarketPanel
var prompt: InteractPrompt
var minimap: MinimapPanel
var minimap_expanded: MinimapExpanded
var player: PlayerHud
var vault: VaultPanel
var banner: RealmBanner
var dialogue: DialoguePrompt
var tutorial_exit: TutorialExitConfirm
var trade_request: TradeRequestPopup
var trade: TradePanel
var party_invite: PartyInvitePopup
var party: PartyPanel
var companions: CompanionPanel
var companion_actions: CompanionActions
var pvp_challenge: PvpChallengePopup
var guild_dialog: CreateGuildDialog
var guild_roster: GuildRosterPanel
var guild_invite: GuildInvitePopup
var nearby: NearbyPanel
var options: OptionsPanel
var leaderboard: LeaderboardWindow
var buy_fame: FamePurchasePanel
var transition: TransitionScreen
var death: DeathScreen
var arena_results: ArenaResults
var login: LoginScreen
var loading: LoadingScreen
var loot: LootWindow
var touch: TouchControls


func build(state: RealmState, game_data: GameData, client: GraveBoundClient,
		data_service: DataService, inventory_actions: InventoryActions,
		caster: AbilityCaster, shop: ShopActions, forge_actions: ForgeActions,
		world: WorldRenderer, chat_actions: ChatActions = null) -> void:
	overlay = EntityOverlay.new()
	overlay.setup(state, game_data)
	add_child(overlay)
	hud = DebugHud.new()
	hud.setup(client, state, world)
	add_child(hud)
	dev = DevOverlay.new()
	dev.setup(client)
	add_child(dev)
	if chat_actions != null:
		chat_actions.commands = ClientCommands.new(state, dev, hud, client)
	chat = ChatPanel.new()
	chat.setup(state, chat_actions)
	add_child(chat)
	inventory = InventoryPanel.new()
	inventory.setup(state, game_data, inventory_actions)
	add_child(inventory)
	loot = LootWindow.new()
	loot.setup(state, game_data, inventory_actions, inventory.beside)
	add_child(loot)
	skills = SkillsPanel.new()
	skills.setup(state, game_data, client)
	add_child(skills)
	masteries = MasteryPanel.new()
	masteries.setup(state)
	add_child(masteries)
	quests = QuestLogPanel.new()
	quests.setup(state, game_data, client)
	add_child(quests)
	abilities = AbilityBar.new()
	abilities.setup(state, game_data, caster, skills)
	add_child(abilities)
	prompt = InteractPrompt.new()
	prompt.setup(state, shop)
	add_child(prompt)
	minimap = MinimapPanel.new()
	minimap.setup(state, chat_actions)
	add_child(minimap)
	minimap_expanded = MinimapExpanded.new()
	minimap_expanded.setup(state, chat_actions)
	add_child(minimap_expanded)
	minimap.expand_requested.connect(func() -> void: minimap_expanded.open(minimap.zoom))
	player = PlayerHud.new()
	player.setup(state, game_data)
	player.below = minimap.bottom
	add_child(player)
	vault = VaultPanel.new()
	vault.setup(state, game_data, data_service)
	add_child(vault)
	banner = RealmBanner.new()
	banner.setup(state, game_data)
	add_child(banner)
	dialogue = DialoguePrompt.new()
	dialogue.setup(state, game_data)
	add_child(dialogue)
	tutorial_exit = TutorialExitConfirm.new()
	add_child(tutorial_exit)
	var trade_actions := TradeActions.new(state, client)
	trade_request = TradeRequestPopup.new()
	trade_request.setup(state, trade_actions)
	add_child(trade_request)
	trade = TradePanel.new()
	trade.setup(state, game_data, trade_actions)
	add_child(trade)
	var party_actions := PartyActions.new(state, client)
	party_invite = PartyInvitePopup.new()
	party_invite.setup(state, party_actions)
	add_child(party_invite)
	companion_actions = CompanionActions.new(client)
	party = PartyPanel.new()
	party.setup(state, game_data, party_actions, hud, companion_actions)
	add_child(party)
	companions = CompanionPanel.new()
	companions.setup(state, game_data, companion_actions)
	add_child(companions)
	pvp_challenge = PvpChallengePopup.new()
	pvp_challenge.setup(state, chat_actions)
	add_child(pvp_challenge)
	var guild_actions := GuildActions.new(state, client, data_service)
	guild_dialog = CreateGuildDialog.new()
	guild_dialog.setup(state, guild_actions)
	add_child(guild_dialog)
	guild_roster = GuildRosterPanel.new()
	guild_roster.setup(state, guild_actions)
	add_child(guild_roster)
	guild_invite = GuildInvitePopup.new()
	guild_invite.setup(state, guild_actions)
	add_child(guild_invite)
	options = OptionsPanel.new()
	options.setup(state.settings, client)
	add_child(options)
	nearby = NearbyPanel.new()
	nearby.setup(state, game_data, trade_actions, party_actions, chat_actions, guild_actions, party)
	add_child(nearby)
	inventory.below = nearby.bottom
	chat.avoid = inventory.covered
	touch = TouchControls.new()
	touch.setup(state, caster, game_data, inventory, options, abilities)
	add_child(touch)
	leaderboard = LeaderboardWindow.new(state, game_data, data_service)
	add_child(leaderboard)
	var menu_buttons := [["Character", skills.toggle], ["Skills", masteries.toggle], ["Quests", quests.toggle],
		["Leaderboard", leaderboard.toggle], ["Options", options.toggle]]
	if CompanionPanel.ENABLED:
		menu_buttons.append(["Companion", companions.toggle])
		touch.set_companion(func() -> void:
			if not companion_actions.toggle_summon(state.companions):
				companions.toggle())
	buy_fame = FamePurchasePanel.new()
	buy_fame.data_service = data_service
	add_child(buy_fame)
	touch.set_buy_fame(buy_fame.open, buy_fame.available)
	touch.link(menu_buttons, chat.toggle_line)
	party.buttons_bottom = touch.row_bottom
	store = ItemStorePanel.new()
	store.setup(state, game_data, inventory_actions, shop)
	add_child(store)
	fame = FameStorePanel.new()
	fame.setup(state, game_data, shop)
	add_child(fame)
	forge = ForgePanel.new()
	forge.setup(state, game_data, forge_actions)
	add_child(forge)
	market = ExchangeMarketPanel.new()
	market.setup(state, game_data, shop)
	add_child(market)
	transition = TransitionScreen.new()
	transition.setup(state, game_data)
	add_child(transition)
	death = DeathScreen.new()
	add_child(death)
	arena_results = ArenaResults.new()
	add_child(arena_results)
	login = LoginScreen.new(data_service, game_data)
	login.buy_fame = buy_fame.open
	login.buy_fame_shown = buy_fame.available
	add_child(login)

	loading = LoadingScreen.new()
	loading.setup(game_data)
	add_child(loading)


## A click on the bag, the bar or the sheet is a gesture on it, not a shot.
func captures_mouse() -> bool:
	return [inventory, abilities, skills, masteries, quests, store, fame, forge, minimap, minimap_expanded, market, trade,
		trade_request, party, party_invite, pvp_challenge, guild_dialog, guild_roster, guild_invite,
		nearby, options, chat, player, prompt, loot, leaderboard, touch, tutorial_exit, vault, companions,
		buy_fame].any(func(panel) -> bool: return panel.captures_mouse())

func captures_keyboard() -> bool:
	return chat.is_typing() or options.capturing() or guild_dialog.is_typing() \
		or guild_roster.is_typing() or quests.is_typing() or companions.is_typing()
