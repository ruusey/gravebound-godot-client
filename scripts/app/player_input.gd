class_name PlayerInput
extends RefCounted

## Turns held keys and mouse into predicted movement and shots.
##
## Driven explicitly from Main's frame loop rather than its own _process, so
## the order of prediction, simulation and camera follow is not left to node
## ordering.

var state: RealmState
var client: GraveBoundClient
## Supplies the aim point; any Node2D in the world will do.
var aim_source: Node2D
## Resolves the equipped weapon's archetype, which sets the fire rate.
var content: GameData
## Read rather than accumulated: the server gates shots on an absolute clock,
## and both references use the wall clock here to match it.
var clock: Callable = func() -> int: return Time.get_ticks_msec()

## Whether something on screen owns the mouse right now -- the bag, or an
## item being dragged out of it. Wired by Main; a click there is not a shot.
var mouse_captured: Callable = func() -> bool: return false
## Whether the chat line has the keyboard: held keys are letters then, and
## the player stands still -- still stepping, so the stop is sent.
var keyboard_captured: Callable = func() -> bool: return false
## Where the aim stick points, when there is one: INF for no touch controls
## (the mouse decides), ZERO for a stick at rest (no shot), else the point.
var touch_aim: Callable = func() -> Vector2: return Vector2.INF

## The 3D view's orbit angle, so WASD stays relative to the screen when the
## camera is turned (W is always "up" on screen). 0 in the plain 2D client.
var view_yaw := 0.0
## In 3D, the mouse's world point on the ground through the 3D camera; the 2D
## camera's get_global_mouse_position is wrong there. Returns a Vector2, or null
## to fall back to the 2D mouse (the plain client).
var world_mouse: Callable = func() -> Variant: return null

var _next_shot_ms := 0
## The stick made digital, as the keys are: eight directions, full speed.
var _direction := StickDirection.new()


func _init(realm_state: RealmState, net_client: GraveBoundClient, source: Node2D,
		game_data: GameData = null) -> void:
	state = realm_state
	client = net_client
	aim_source = source
	content = game_data


func tick(delta: float) -> void:
	if not client.is_in_game():
		return

	# Raw, no deadzone of the actions' own: StickDirection has the thresholds.
	var movement := Vector2.ZERO if keyboard_captured.call() \
		else _direction.filter(Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.0))
	# Turn the keys into the camera's frame, so screen-up is always forward.
	# Camera offset is (sin yaw, cos yaw), so screen-up on the ground is
	# (-sin yaw, -cos yaw); mapping WASD onto that works out to rotate by -yaw.
	if view_yaw != 0.0:
		movement = movement.rotated(-view_yaw)
	for packet in state.advance(delta, movement, client.stats.round_trip_ms()):
		client.send_move(packet["seq"], packet["vx"], packet["vy"])

	# The lock-on ring is the phone's: it shows what Attack will auto-aim at.
	# A mouse aims where it points, so the desktop draws none -- and clears
	# one left over from touch controls switched off.
	if touch_aim.call() == Vector2.INF:
		state.entities.lock_on = -1
	_fire(delta)


func _fire(_delta: float) -> void:
	if mouse_captured.call() or keyboard_captured.call():
		return
	var target: Vector2 = touch_aim.call()
	if target == Vector2.ZERO:
		return
	if target == Vector2.INF:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		var world: Variant = world_mouse.call()
		target = world if world is Vector2 else aim_source.get_global_mouse_position()
	# Stunned, the server refuses the shot outright -- and predicting a bullet
	# it will never spawn is worse than not firing.
	if AttackRate.blocked(state.local.effects) or clock.call() < _next_shot_ms:
		return

	var shot: Dictionary = state.projectiles.fire_basic_attack(target)
	if shot.is_empty():
		return
	_next_shot_ms = clock.call() + int(interval() * 1000.0)
	client.send("PlayerShootPacket", shot)
	_play_attack_sound()


## The swing sound for the weapon in hand, by its archetype.
func _play_attack_sound() -> void:
	if content == null:
		return
	var weapon: Dictionary = state.local.equipped_weapon()
	var archetype: Dictionary = content.archetype_for_item(int(weapon.get("itemId", -1)))
	Sfx.attack(int(archetype.get("id", 0)))


## How long this weapon makes us wait, with whatever is on us right now.
func interval() -> float:
	var weapon: Dictionary = state.local.equipped_weapon()
	var archetype: Dictionary = {} if content == null \
		else content.archetype_for_item(int(weapon.get("itemId", -1)))
	return AttackRate.interval(
		int(state.local.stats.get("dex", AttackRate.DEFAULT_DEX)),
		float(archetype.get("attackSpeedMul", 1.0)),
		state.local.effects)
