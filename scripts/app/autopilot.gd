class_name Autopilot
extends RefCounted

## Plays the character unattended, for soak tests and hitch captures: walks the
## nexus to a realm portal (by the nexus map's static portal coordinates, as the
## server's loadtest bots do, since a portal across the room is not streamed yet),
## then heads inland and circles the nearest enemy at range, firing at it and
## backing off when health runs low. It only supplies the stick and
## the aim point that PlayerInput would read from the keys and mouse, so every
## packet, prediction and shot goes through the normal client path.
##
## On a load-test bot account it first sends /loadout, as the server's off-box bots
## do: max-level gear and permanent invincibility, so a long capture survives.
##
## Behind --autopilot only; nothing a player can switch on.

const ENGAGE_PX := 14.0 * GameConstants.TILE_SIZE
const FIRE_PX := 8.0 * GameConstants.TILE_SIZE
const ORBIT_PX := 4.5 * GameConstants.TILE_SIZE
## Below this fraction of max health it backs away instead of circling.
const RETREAT_HEALTH := 0.4
const STUCK_SECONDS := 0.6
const STUCK_PX := 2.0
## Seconds a portal attempt is given before trying again.
const PORTAL_RETRY_SECONDS := 4.0
## How long a wedged walk detours sideways before steering at the goal again.
const DETOUR_SECONDS := 0.8
## A stick is held at least this long, as a hand would; re-aiming every frame
## flips the eight-way direction constantly and reads as the camera jerking.
const HOLD_SECONDS := 0.25

var state: RealmState
var client: GraveBoundClient
var portals: PortalInput
var content: GameData
## Which nexus portal to take: a piece of its label or its target node id.
var realm := "beach-hard"

var _heading := Vector2.RIGHT
var _orbit_sign := 1.0
var _stuck_for := 0.0
var _last_position := Vector2.INF
var _portal_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _move := Vector2.ZERO
var _aim := Vector2.ZERO
var _detour_for := 0.0
var _detour := Vector2.ZERO
var _loadout_sent := false
var _held := Vector2.ZERO
var _held_for := 0.0


func _init(realm_state: RealmState, net_client: GraveBoundClient, portal_input: PortalInput,
		game_data: GameData) -> void:
	state = realm_state
	client = net_client
	portals = portal_input
	content = game_data
	_rng.randomize()
	_heading = Vector2.from_angle(_rng.randf() * TAU)


## The stick for this frame, read by PlayerInput.
func movement() -> Variant:
	return _held


## Where to shoot, or ZERO for no shot (PlayerInput's touch-aim convention).
func aim() -> Vector2:
	return _aim


func tick(delta: float) -> void:
	_steer(delta)
	_held_for = maxf(_held_for - delta, 0.0)
	if _held_for <= 0.0 or (_move == Vector2.ZERO) != (_held == Vector2.ZERO):
		_held = _move
		_held_for = HOLD_SECONDS


func _steer(delta: float) -> void:
	_move = Vector2.ZERO
	_aim = Vector2.ZERO
	if not state.local.is_present() or state.transition_pending:
		return
	if not _loadout_sent:
		_loadout_sent = true
		client.send_server_command("/loadout")
	_portal_cooldown = maxf(_portal_cooldown - delta, 0.0)
	_detour_for = maxf(_detour_for - delta, 0.0)
	_track_stuck(delta)
	if content.maps.is_nexus(state.tiles.map_id):
		_head_for_realm_portal()
		return
	var target := _nearest_enemy()
	if target.is_empty():
		# The enemies are inland; the spawn is on the shore.
		var middle := Vector2(state.tiles.width, state.tiles.height) * GameConstants.TILE_SIZE * 0.5
		_steer_to(middle if state.local.centre().distance_to(middle) > ENGAGE_PX else state.local.centre() + _heading)
		return
	var centre := state.local.centre()
	var enemy_centre := _enemy_centre(target)
	var offset := enemy_centre - centre
	var distance := offset.length()
	if distance <= FIRE_PX:
		_aim = enemy_centre
	if _low_health():
		_move = -offset.normalized()
		return
	var radial := offset.normalized() * clampf((distance - ORBIT_PX) / GameConstants.TILE_SIZE, -1.0, 1.0)
	_move = (radial + offset.normalized().orthogonal() * _orbit_sign).normalized()


func _head_for_realm_portal() -> void:
	var goal: Variant = _portal_goal()
	if goal == null:
		_move = _heading
		return
	_steer_to(goal)
	var near := portals.nearest()
	if _portal_cooldown <= 0.0 and not near.is_empty() and _wanted(near):
		_portal_cooldown = PORTAL_RETRY_SECONDS
		portals.use_nearest()


## Where the wanted portal is: the streamed portal once it is in view, else its
## static coordinate on the nexus map.
func _portal_goal() -> Variant:
	for id in state.entities.portals:
		var portal: Dictionary = state.entities.portals[id]
		if _wanted(portal):
			return state.entities.render_position(portal)
	var definition: Dictionary = content.library.maps.get(state.tiles.map_id, {})
	for placed: Dictionary in definition.get("staticPortals", []):
		var label := String(placed.get("label", "")).to_lower()
		var node := String(placed.get("targetNodeId", "")).to_lower()
		if label.contains(realm.to_lower()) or node == realm.to_lower():
			return Vector2(float(placed.get("x", 0.0)), float(placed.get("y", 0.0)))
	return null


func _wanted(portal: Dictionary) -> bool:
	return String(portal.get("label", "")).to_lower().contains(realm.to_lower()) \
		or _label_for_node(realm) != "" and String(portal.get("label", "")) == _label_for_node(realm)


## The nexus label of the portal leading to `node`, so a node id like beach-hard
## matches the streamed portal, which carries only the label.
func _label_for_node(node: String) -> String:
	var definition: Dictionary = content.library.maps.get(state.tiles.map_id, {})
	for placed: Dictionary in definition.get("staticPortals", []):
		if String(placed.get("targetNodeId", "")).to_lower() == node.to_lower():
			return String(placed.get("label", ""))
	return ""


## Straight at `goal`, or sideways for a moment when a wall has us wedged.
func _steer_to(goal: Vector2) -> void:
	if _detour_for > 0.0:
		_move = _detour
		return
	_move = (goal - state.local.centre()).normalized()


func _nearest_enemy() -> Dictionary:
	var centre := state.local.centre()
	var best := {}
	var best_distance := ENGAGE_PX
	for id in state.entities.enemies:
		var enemy: Dictionary = state.entities.enemies[id]
		var distance := centre.distance_to(_enemy_centre(enemy))
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _enemy_centre(enemy: Dictionary) -> Vector2:
	var size := float(enemy.get("size", GameConstants.TILE_SIZE))
	return state.entities.render_position(enemy) + Vector2(size, size) * 0.5


func _low_health() -> bool:
	var max_health := int(state.local.stats.get("hp", 0))
	return max_health > 0 and state.local.health < max_health * RETREAT_HEALTH


## A wall or the shore stops the walk; pick a new heading and circle the other way.
func _track_stuck(delta: float) -> void:
	var position := state.local.position
	if _last_position != Vector2.INF and position.distance_to(_last_position) < STUCK_PX * delta * 60.0:
		_stuck_for += delta
	else:
		_stuck_for = 0.0
	_last_position = position
	if _stuck_for >= STUCK_SECONDS:
		_stuck_for = 0.0
		_heading = Vector2.from_angle(_rng.randf() * TAU)
		_orbit_sign = -_orbit_sign
		_detour = (_move.orthogonal() * _orbit_sign if _move != Vector2.ZERO else _heading).normalized()
		_detour_for = DETOUR_SECONDS
