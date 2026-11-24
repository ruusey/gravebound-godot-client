class_name EffectRenderer
extends Node2D

## What a cast leaves on the ground, and who is still casting.
##
## Drawn between the bullets and the labels: over the entities, under the
## names. Each effect type is drawn by its own file under render/effects,
## found through Fx.for_type by the wire's `effectType`; anything without
## one gets FxGeneric, the native client's generic form in the hue its
## table gives the type.
## Both references draw all sixty-odd types by hand (the web client in one
## switch, the native in one 3,500-line class); here a new type is one file
## and one line in Fx. A drawer takes the canvas, the effect, its progress
## in 0..1, its tier colour and its age in ms, and draws in world space.

## The web client's TIER_COLORS, T0 silver through T6 purple.
const TIER_COLOURS := [Color("c0c0c0"), Color("60c0ff"), Color("60ff80"), Color("ffd040"),
	Color("ff8040"), Color("ff4060"), Color("c060ff")]
const RING_COLOUR := Color("66ccff")
const CAST_BAR := Vector2(28.0, 3.0)
const CAST_BACK := Color(0.0, 0.0, 0.0, 0.6)
const CAST_FILL := Color(0.6, 0.85, 1.0)
## Effects drawn round their owner wherever they move, not where they began.
const FOLLOWS_OWNER := [EffectType.QUEST_COMPLETE]

var state: RealmState
var drawn := 0


func _draw() -> void:
	if state == null:
		return
	drawn = paint(self, state, ViewRect.of(self))


## What an effect can reach: its radius around where it stands, and along
## to its far end when it has one -- a boss's beam, a dash, a thrown lob.
## An area effect sends no target (the server writes 0,0), so a zero one
## is not a point to reach, or every effect would stretch to the origin.
static func bounds(fx: Dictionary) -> Rect2:
	var box := Rect2(fx["pos"], Vector2.ZERO)
	if fx["target"] != Vector2.ZERO:
		box = box.expand(fx["target"])
	return box.grow(fx["radius"])


## "Play ability animations" off hides every effect; "Show other players'
## ability effects" off hides those another player cast, as the web
## client's CREATE_EFFECT handler does. What enemies cast always shows --
## a boss's beam warning is how you know to move.
static func shown(realm: RealmState, fx: Dictionary) -> bool:
	if not realm.settings.is_on("ability_animations"):
		return false
	var owner := int(fx.get("owner", 0))
	return realm.settings.is_on("show_ally_effects") or owner == realm.local.id \
		or not realm.entities.players.has(owner)


## Re-centres `fx` on its owner, the local player included; left where it
## was when the owner is gone.
static func follow_owner(realm: RealmState, fx: Dictionary) -> void:
	var owner := int(fx.get("owner", 0))
	if owner != 0 and owner == realm.local.id:
		fx["pos"] = realm.local.centre()
		return
	var player: Dictionary = realm.entities.players.get(owner, {})
	if not player.is_empty():
		fx["pos"] = realm.entities.render_position(player) + Vector2.ONE * float(player.get("size", 0)) * 0.5


func paint(canvas: CanvasItem, realm: RealmState, view: Rect2) -> int:
	var abilities := realm.abilities
	var now := abilities.now()
	var count := 0
	for fx in abilities.effects:
		if fx["type"] in FOLLOWS_OWNER:
			follow_owner(realm, fx)
		if not view.intersects(bounds(fx)) or not shown(realm, fx):
			continue
		var progress := clampf(float(now - fx["started"]) / maxf(float(fx["duration_ms"]), 1.0), 0.0, 1.0)
		var colour: Color = TIER_COLOURS[clampi(fx["tier"], 0, TIER_COLOURS.size() - 1)]
		var drawer := Fx.for_type(fx["type"])
		if not drawer.is_valid():
			drawer = FxGeneric.draw
		drawer.call(canvas, fx, progress, colour, now - fx["started"])
		count += 1
	for ring in abilities.rings:
		var alpha := 1.0 - clampf(float(now - ring["started"]) / float(AbilityState.RING_MS), 0.0, 1.0)
		CircleStamp.ring(canvas, ring["pos"], ring["radius"], 2.0, Color(RING_COLOUR, alpha * 0.75), 64)
		count += 1
	for id in abilities.casts:
		var player: Dictionary = realm.entities.players.get(id, {})
		if player.is_empty():
			continue
		var top := realm.entities.render_position(player) + Vector2(float(player.get("size", 0)) * 0.5, -8.0)
		var origin := top - Vector2(CAST_BAR.x * 0.5, 0.0)
		canvas.draw_rect(Rect2(origin, CAST_BAR), CAST_BACK)
		canvas.draw_rect(Rect2(origin, Vector2(CAST_BAR.x * abilities.cast_progress(id), CAST_BAR.y)), CAST_FILL)
		count += 1
	return count
