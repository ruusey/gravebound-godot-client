class_name AbilityCaster
extends RefCounted

## Casts a hotbar ability at a point in the world.
##
## The gates are the web client's `tryUseAbility`, and every one is there
## because the server refuses silently: a global second between casts, the
## slot's own cooldown, the mana cost, and the ability's reach, which pulls
## the point in before it is sent -- the server clamps the same way, so a
## projectile predicted from the clamped point is the one that arrives.
##
## Mana is taken optimistically. The server's PlayerStatePacket restores it
## on a refusal, and without the deduction a spammed key sends a cast the
## server will drop for every frame the key is down.

## The web client's ABILITY_COOLDOWN_MS, between any two casts.
const GLOBAL_COOLDOWN_MS := 1000

var state: RealmState
var client: GraveBoundClient
var content: GameData
## Supplies the aim point; any Node2D in the world will do.
var aim_source: Node2D
## The touch controls' point to cast at, when they are on; INF, or unset,
## leaves it to the mouse.
var aim_point: Callable = Callable()
## In 3D, the mouse's world point on the ground through the orbited camera; the
## 2D camera's get_global_mouse_position is wrong there. Returns a Vector2, or
## null to fall back to the 2D mouse. Mirrors PlayerInput.world_mouse.
var world_mouse: Callable = func() -> Variant: return null


func _init(realm_state: RealmState, net_client: GraveBoundClient, game_data: GameData,
		source: Node2D) -> void:
	state = realm_state
	client = net_client
	content = game_data
	aim_source = source


func cast_at_cursor(slot: int) -> bool:
	var at: Vector2 = aim_point.call() if aim_point.is_valid() else Vector2.INF
	if at == Vector2.INF:
		var world: Variant = world_mouse.call()
		at = world if world is Vector2 else aim_source.get_global_mouse_position()
	return cast(slot, at)


func cast(slot: int, target: Vector2) -> bool:
	if content == null or not client.is_in_game() or slot < 0 or slot >= AbilityCatalog.SLOTS:
		return false
	var abilities := state.abilities
	var now := abilities.now()
	if now < abilities.global_until or abilities.on_cooldown(slot):
		return false
	var id := content.abilities.hotbar_id(state.local.class_id, slot)
	var definition := content.abilities.ability(id)
	if definition.is_empty():
		return false
	var cost := int(definition.get("mpCost", 0))
	if cost > 0 and state.local.mana < cost:
		return false

	var centre := state.local.centre()
	target = content.abilities.clamp_target(id, centre, target)
	client.send("UseAbilityPacket", {"posX": target.x, "posY": target.y, "abilityIndex": slot})
	Sfx.ability(definition)

	# The cast pose, aimed where the cast went; a self-cast faces front.
	state.local.face_toward(target - centre)
	state.local.attack.begin(target - centre)
	abilities.global_until = now + GLOBAL_COOLDOWN_MS
	abilities.start_cooldown(slot, content.abilities.cooldown_ms(id, abilities.invested[slot]))
	state.local.mana = maxi(0, state.local.mana - cost)
	var reach := int(definition.get("maxCastRange", 0))
	if reach > 0:
		abilities.show_ring(centre, float(reach))
	_predict(id, centre, target)
	return true


## The projectiles the cast fires, drawn now rather than a round trip later.
## The server's two spawn rules: a TARGET_PLAYER projectile leaves the caster
## aimed at the point, anything else spawns at the point on its own preset
## heading. A homing shot is left to the server, whose copy would otherwise
## snap and flip the prediction the moment it arrived.
func _predict(ability_id: int, centre: Vector2, target: Vector2) -> void:
	var group_id := content.abilities.projectile_group(ability_id)
	if group_id == 0:
		return
	var definitions := content.projectiles_in_group(group_id)
	if definitions.is_empty():
		return
	var shot := state.projectiles.claim_shot_number()
	var aimed := ProjectileAngle.aim(centre, target)
	var half := Vector2.ONE * GameConstants.PLAYER_SIZE * 0.5
	var now := state.abilities.now()
	for i in definitions.size():
		var definition: Dictionary = definitions[i]
		# A JSON flag is a float, and `in` is type-strict.
		if ProjectileKind.HOMING in Array(definition.get("flags", [])).map(func(flag: Variant) -> int: return int(flag)):
			continue
		var at_caster := int(definition.get("positionMode", 0)) == 0
		var origin := state.local.position if at_caster else target - half
		var angle := float(definition.get("angle", 0.0)) + (aimed if at_caster else 0.0)
		var local_id := -(shot * 100 + i)
		state.projectiles.add_prediction(local_id, Projectile.predicted_shot(local_id, group_id, origin,
			angle, definition, now))
