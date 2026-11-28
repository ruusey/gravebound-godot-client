class_name RealmState
extends RefCounted

## The client's model of the realm, and the router that feeds it. Each
## component handles its own wire mapping; adding a packet is one line here.
##
##   tiles, entities       terrain and collision; players, enemies, loot, portals
##   local, movement       the player we control, its prediction and reconciliation
##   projectiles, particles  bullets (simulated, never streamed) and their trails
##   texts, chat, bubbles  combat numbers, the chat log, what floats over heads
##   abilities, progress   skill points, cooldowns, casts; masteries, quests
##   store, fame, forge, market, minimap, trade, party  the tile panels, the map, a trade, the party

const TICK_DELTA := GameConstants.TICK_DELTA
const TILE_SIZE := GameConstants.TILE_SIZE
const PLAYER_SIZE := GameConstants.PLAYER_SIZE

var tiles: TileMapState
var entities: EntityRegistry
var local: LocalPlayer
var movement: MovementPredictor
var projectiles: ProjectileSystem
var particles: ParticleField
## Pixel chips sprayed off whatever a shot hits; driven by the hit packet below.
var hit_burst: HitBurst
var texts: DamageText
var chat: ChatLog
var bubbles: ChatBubbles
var abilities: AbilityState
var store: ItemStore
var fame: FameStore
var forge: ForgeBench
var market: ExchangeMarket
var minimap: MinimapState
var trade: TradeSession
var party: PartyState
## Trade/party/PvP requests waiting on us, and what became of ours.
var interactions: InteractionState
var transition: RealmTransition
## The difficulty of the realm being entered, when a portal said so.
var transition_difficulty := 0.0
## What the player has switched on and off; every view reads it from here.
var settings := GameSettings.new()
var progress := AccountProgress.new()   # masteries, quests, stars: kept across realms
var guild := GuildState.new()           # account-wide guild: roster, dialog, invite
var social := SocialState.new()         # account-wide friends and guild directory
var companions := CompanionState.new()  # account-wide AI party roster: kept across realms
## The frame's clock: remote entities and the frame's delta both read it (begin_frame).
var pacer := FramePacer.new()
var _frame := -1
var _frame_ms := 0.0

var transition_pending: bool:
	get: return transition.pending


## Without a clock of its own the realm runs on the wall clock, and remote
## entities interpolate on a sub-millisecond one with packets snapped to the
## server's send grid; a scripted clock drives everything exactly as given.
## The entities' clock is read once per frame, at its start, so the sprite, its
## tag and every lookup in between agree on where an entity is.
func _init(content: GameData = null, clock: Callable = Callable()) -> void:
	if clock.is_valid():
		entities = EntityRegistry.new(clock)
	else:
		clock = func() -> int: return Time.get_ticks_msec()
		entities = EntityRegistry.new(_frame_clock)
		entities.packet_clock = PacketClock.new()
	tiles = TileMapState.new(content)
	local = LocalPlayer.new()
	entities.viewer = func() -> Vector2: return local.centre() if local.is_present() else Vector2.INF
	movement = MovementPredictor.new(local, tiles)
	projectiles = ProjectileSystem.new(local, content, clock, entities, tiles)
	movement.slow_probe = projectiles.slowing_hit_ms
	particles = ParticleField.new(null if content == null else content.projectiles_art)
	hit_burst = HitBurst.new(content)
	texts = DamageText.new()
	chat = ChatLog.new(clock)
	bubbles = ChatBubbles.new(clock)
	abilities = AbilityState.new(clock)
	store = ItemStore.new()
	fame = FameStore.new()
	forge = ForgeBench.new()
	market = ExchangeMarket.new()
	minimap = MinimapState.new(content, clock)
	trade = TradeSession.new(clock)
	party = PartyState.new()
	interactions = InteractionState.new(clock)
	transition = RealmTransition.new(self, clock)


## Starts a frame on the paced clock and returns the delta everything advances by.
## Called once, first thing in the frame; without it (or with the pacer off) the
## realm runs on the engine's delta and a clock read at first use.
func begin_frame(engine_delta: float, synced: bool) -> float:
	if not pacer.enabled:
		return engine_delta
	return pacer.tick(Time.get_ticks_usec() * 0.001, engine_delta * 1000.0, synced)


func _frame_clock() -> float:
	if pacer.enabled and pacer.pacing:
		return pacer.now_ms
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_frame_ms = Time.get_ticks_usec() * 0.001
	return _frame_ms


func apply_packet(name: String, data: Dictionary) -> void:
	match name:
		"LoadMapPacket":
			transition.apply_load_map(data)
		"LoadPacket":
			if entities.apply_load(data) > 0:
				Sfx.event("loot_untiered")
			projectiles.apply_load(data)
			PlayerSync.local_class(self)
		"UnloadPacket":
			entities.apply_unload(data)
			projectiles.apply_unload(data)
		"ObjectMovePacket":
			entities.apply_object_move(data)
			transition.snap_local(data)
		"CompactMovePacket":
			entities.apply_compact_move(data)
		"UpdatePacket":
			PlayerSync.update(self, data)
		"PlayerStatePacket":
			PlayerSync.player_state(self, data)
		"PlayerPosAckPacket":
			movement.apply_position_ack(data)
		"TextEffectPacket":
			texts.apply_text_effect(data, entities, projectiles, local)
			hit_burst.consider(data, entities, projectiles, local, settings)
		"TextPacket":
			for listener in [chat, bubbles, transition, minimap]:
				listener.apply_text(data)
		"GlobalPlayerPositionPacket":
			minimap.apply_global_positions(data)
		"RealmPurificationPacket":
			minimap.apply_purification(data)
		"AbilityCastStartPacket":
			abilities.apply_cast_start(data, entities, local.id)
		"AbilityCooldownPacket":
			abilities.apply_cooldown(data)
		"CreateEffectPacket":
			abilities.apply_effect(data, entities, local)
		"OpenItemStorePacket":
			store.apply_open(data, local.id)
		"ItemStoreUpdatePacket":
			store.apply_update(data, local.id)
		"OpenFameStorePacket":
			fame.apply_open(data, local.id)
		"OpenForgePacket":
			forge.apply_open(data, local.id)
		"OpenExchangeMarketPacket":
			market.apply_open(data, local.id)
		"InteractionPacket":
			interactions.apply(data)
		"AcceptTradeRequestPacket", "UpdateTradePacket", \
				"UpdatePlayerTradeSelectionPacket":
			trade.apply(name, data, local.id)
		"SkillsPacket", "QuestStatePacket":
			progress.apply(name, data, local.id)
		"PartyUpdatePacket":
			party.apply_update(data)
		"PartyVitalsPacket":
			party.apply_vitals(data)
		"OpenCreateGuildDialogPacket":
			guild.apply_create_dialog(data, local.id)
		"GuildInfoPacket":
			guild.apply_info(data, local.id)
		"OpenGuildEditorPacket":
			guild.apply_editor(data)
		"CompanionRosterPacket":
			companions.apply_roster(data)
		"SocialStatusPacket":
			social.apply(data)


func advance(delta: float, input: Vector2, latency_ms: float) -> Array:
	projectiles.latency_ms = latency_ms
	transition.expire()
	local.decay_smoothing(delta)
	var to_send := movement.predict(delta, input)
	local.walk.advance(movement.pace_px, delta)
	local.attack.tick(delta)
	RemoteAnimation.advance(entities.players, delta)
	RemoteAnimation.advance(entities.enemies, delta)
	projectiles.advance(delta)
	# Trails/impacts follow the same visibility rule as the bullet sprite + glow:
	# a shot we don't draw (another player's/companion's with "show other players'
	# bullets" off, or one hidden by Blind) spawns no particles either.
	particles.advance(delta, projectiles.bullets, BulletVisibility.of(self))
	hit_burst.advance(delta)
	texts.advance(delta)
	abilities.expire()
	minimap.expire()
	trade.expire()
	interactions.expire()
	return to_send


func reset_world() -> void:
	for component in [tiles, entities, projectiles, particles, hit_burst, texts, chat, bubbles,
			abilities, minimap, party, interactions]:
		component.clear()
	close_interactions()


## Shut and RESET every open tile/region dialogue (vault/potion store, fame store,
## forge, exchange market, trade, guild) whenever the player leaves a region -- a
## portal, the nexus, the vault, or a disconnect. Uses clear() (not close()) so the
## bound tile/container is wiped, not merely hidden: a panel from the old realm can't
## linger on screen or be acted on in the new one.
func close_interactions() -> void:
	store.clear()
	fame.clear()
	forge.clear()
	market.clear()
	trade.clear()
	guild.close_create()
	guild.close_roster()


func begin_transition(difficulty := 0.0) -> void:
	transition.begin()
	transition_difficulty = difficulty
