class_name PortalInput
extends RefCounted

## The three ways out of a realm: the portal under your feet, the nexus, and
## the vault.
##
## The sequence is the one both references follow and neither improvises:
## send UsePortalPacket, tear the realm down locally, then send LoginAckPacket
## -- which is what asks the server for the next map's tiles. Acking every
## LoadMapPacket instead looks equivalent and is not; LoadMap also fires once
## per tile-stream chunk.

## The flags are bytes and the server tests them against -1, not 0
## (`isToVault()` is `toVault != -1`), so "no" has to be spelled -1 or every
## portal enters the vault.
const OFF := -1
const ON := 1
## Portal id 2 is the vault, and it MUST travel as the toVault variant: that
## is the only branch on the server that sets the chests up. Sent as an
## ordinary portal it routes by toRealmId and lands you somewhere empty.
const VAULT_PORTAL := 2
## How close counts as standing on it, in world pixels. The web client's 64;
## the native takes 32, which is stricter than the server requires.
const REACH_PX := 64.0
## The native's PORTAL_COOLDOWN_MS, so a held key cannot fire again into the
## realm still being streamed to us.
const COOLDOWN := 1.0

var state: RealmState
var client: GraveBoundClient
var content: GameData

var _cooldown := 0.0
## Whether the chat line has the keyboard; a key then is a letter.
var keyboard_captured: Callable = func() -> bool: return false
## Asked before an exit that leaves the tutorial with quests still open. Given
## a callback it answers with true (go) or false (stay); the default just goes.
var confirm_exit: Callable = func(on_result: Callable) -> void: on_result.call(true)

var _held := {}
var _awaiting_confirm := false


func _init(realm_state: RealmState, net_client: GraveBoundClient, game_data: GameData) -> void:
	state = realm_state
	client = net_client
	content = game_data


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if keyboard_captured.call():
		_held.clear()
		return
	if _pressed("use_portal"):
		use_nearest()
	if _pressed("go_nexus"):
		to_nexus()
	if _pressed("go_vault"):
		to_vault()


## The portal in reach, or nothing. Measured top-left to top-left, as both
## references do -- the wire position is the sprite's corner, and comparing a
## centre against a corner biases the reach by half a tile.
func nearest() -> Dictionary:
	var found := {}
	var closest := REACH_PX
	for id in state.entities.portals:
		var portal: Dictionary = state.entities.portals[id]
		var distance := state.local.position.distance_to(
			state.entities.render_position(portal))
		if distance < closest:
			closest = distance
			found = portal
	return found


func use_nearest() -> void:
	var portal := nearest()
	if portal.is_empty():
		return
	if int(portal.get("portal_id", -1)) == VAULT_PORTAL:
		to_vault()
		return
	_transition(int(portal.get("id", 0)), OFF, OFF,
		content.portals.name(int(portal.get("portal_id", -1))), float(portal.get("difficulty", 0.0)))


## Escape to the nexus from anywhere. No portal id: the server picks the
## destination, which is why this one works while a realm is collapsing.
func to_nexus() -> void:
	if content.maps.is_nexus(state.tiles.map_id):
		return
	_transition(-1, OFF, ON, "the nexus")


func to_vault() -> void:
	if content.maps.is_vault(state.tiles.map_id):
		return
	_transition(-1, ON, OFF, "the vault")


func _transition(portal_id: int, to_vault_flag: int, to_nexus_flag: int,
		what: String, difficulty := 0.0) -> void:
	if _cooldown > 0.0 or not client.is_in_game() or _awaiting_confirm:
		return
	if _needs_tutorial_warning():
		_awaiting_confirm = true
		confirm_exit.call(func(exit_anyway: bool) -> void:
			_awaiting_confirm = false
			if exit_anyway:
				_do_transition(portal_id, to_vault_flag, to_nexus_flag, what, difficulty))
		return
	_do_transition(portal_id, to_vault_flag, to_nexus_flag, what, difficulty)


func _do_transition(portal_id: int, to_vault_flag: int, to_nexus_flag: int,
		what: String, difficulty: float) -> void:
	_cooldown = COOLDOWN
	print("[realm] entering %s" % what)
	client.send("UsePortalPacket", {
		"portalId": portal_id,
		"fromRealmId": state.tiles.realm_id,
		"toVault": to_vault_flag,
		"toNexus": to_nexus_flag,
	})
	state.begin_transition(difficulty)
	client.send("LoginAckPacket", {})


## True while standing in the tutorial map with an onboarding (TUTORIAL-category)
## quest still unfinished.
func _needs_tutorial_warning() -> bool:
	if state == null or content == null or not content.maps.is_tutorial(state.tiles.map_id):
		return false
	for quest in state.progress.quests:
		if String(quest.get("cat", "")).to_upper() == "TUTORIAL" \
				and AccountProgress.status_of(quest) != AccountProgress.COMPLETE:
			return true
	return false


## True on the frame the key goes down, not while it is held. Tracked here
## rather than through Input.is_action_just_pressed, which is scoped to the
## engine's frame and would repeat for a second tick() in the same one.
func _pressed(action: String) -> bool:
	var down := Input.is_action_pressed(action)
	var edge: bool = down and not _held.get(action, false)
	_held[action] = down
	return edge
