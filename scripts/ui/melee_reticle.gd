class_name MeleeReticle
extends Control

## A small marker that follows the cursor in the aim direction, clamped to the
## equipped melee weapon's maximum reach.
##
## A melee swing is an invisible server-side cone (apex at the player centre,
## length = the weapon's projectile range x the archetype's rangeMul, matching
## spawnMeleeSwing), and the swing animation doesn't show how far it reaches. The
## legacy clients drew this dot so the player can see what a swing will and won't
## hit. Hidden for ranged weapons and when there is no mouse aim.
##
## Anchored like every other overlay element: a world point pushed through the
## same `to_screen` transform (the 2D camera's, or the 3D affine projector), so it
## works in both render modes with no extra code.

## A raindrop ripple: concentric rings expanding and fading like a drop hitting
## water, over a small bright centre -- ported from the legacy web client
## (renderer.js), whose flat orange dot was hard to pick out. Sizes are world
## units scaled by the camera zoom, so the ripple reads the same at any zoom.
const BASE := 11.0
const RINGS := 3
const PERIOD := 900.0
const RING_COLOUR := Color(0.722, 0.761, 0.8)    # 0xb8c2cc
const CENTRE_COLOUR := Color(0.847, 0.878, 0.91) # 0xd8e0e8
const CENTRE_RADIUS := 1.6

## The world-to-screen scale of the last place(), so the ripple matches the zoom.
var _zoom := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	var time := float(Time.get_ticks_msec())
	var base := BASE * _zoom
	for i in RINGS:
		# Staggered phases so the three rings chase each other outward.
		var phase := fmod(time / PERIOD + float(i) / float(RINGS), 1.0)
		var colour := RING_COLOUR
		colour.a = (1.0 - phase) * 0.6
		CircleStamp.ring(self, Vector2.ZERO, base * (0.35 + phase * 0.9), maxf(1.0, _zoom), colour, 40)
	var centre := CENTRE_COLOUR
	centre.a = 0.7
	CircleStamp.disc(self, Vector2.ZERO, CENTRE_RADIUS * _zoom, centre)


## Places the marker at the melee reach in the aim direction, or hides it when the
## weapon isn't melee / there is no aim point.
func place(state: RealmState, content: GameData, to_screen: Transform2D, aim: Variant) -> void:
	if content == null or state == null or not state.local.is_present() or not (aim is Vector2):
		visible = false
		return
	var weapon: Dictionary = state.local.equipped_weapon()
	var archetype: Dictionary = content.archetype_for_item(int(weapon.get("itemId", -1)))
	if not bool(archetype.get("melee", false)):
		visible = false
		return
	var reach := reach_of(content, weapon, archetype)
	if reach <= 0.0:
		visible = false
		return
	var centre: Vector2 = state.local.render_centre()
	var direction: Vector2 = aim - centre
	if direction.length_squared() < 0.0001:
		visible = false
		return
	# Follow the cursor, clamped to the weapon's reach: the marker sits under the aim
	# point when it's within range and pins to max reach only once the cursor is past it.
	var distance := minf(direction.length(), reach)
	position = (to_screen * (centre + direction.normalized() * distance)).round()
	_zoom = maxf(0.1, absf(to_screen.get_scale().x))
	visible = true
	queue_redraw()


## Max reach in world px: the weapon's projectile range scaled by the archetype's
## rangeMul, exactly as the server sizes the melee cone.
static func reach_of(content: GameData, weapon: Dictionary, archetype: Dictionary) -> float:
	return float(cone_of(content, weapon).get("range", 0.0)) * float(archetype.get("rangeMul", 1.0))


## The weapon group's first projectile: the server's melee cone, or {}.
static func cone_of(content: GameData, weapon: Dictionary) -> Dictionary:
	var group_id := int(weapon.get("damage", {}).get("projectileGroupId", 0))
	if group_id == 0:
		group_id = content.item_projectile_group(int(weapon.get("itemId", -1)))
	if group_id == 0:
		return {}
	var definitions := content.projectiles_in_group(group_id)
	return {} if definitions.is_empty() else definitions[0]
