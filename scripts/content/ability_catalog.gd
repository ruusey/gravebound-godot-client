class_name AbilityCatalog
extends RefCounted

## What a class can cast, and what each cast costs.
##
## The hotbar is the class's `abilityTree.defaultHotbar`: four ids, the
## fourth unused. It is what the server seeds a player with and what it falls
## back to when a binding is zero, and nothing about a binding travels on the
## wire, so it is the whole of what the client knows about one.

const SLOTS := 3
const DEFAULT_CAP := 5
## Ultimate = the third active ability (slotHint 2); it caps at 3 points, not 5.
const ULTIMATE_SLOT_HINT := 2
const ULTIMATE_CAP := 3
## The server floors a point-reduced cooldown here, and a cast time at 150.
const MIN_COOLDOWN_MS := 500
const MIN_CAST_MS := 150
const ICON_SIZE := 16

var _library: ContentLibrary
var _sprites: SpriteCache


func _init(library: ContentLibrary, sprites: SpriteCache) -> void:
	_library = library
	_sprites = sprites


## The four bindings, zero where there is none.
func hotbar(class_id: int) -> Array:
	var out := [0, 0, 0, 0]
	var bound: Array = _tree(class_id).get("defaultHotbar", [])
	for i in mini(bound.size(), out.size()):
		out[i] = int(bound[i])
	return out


func hotbar_id(class_id: int, slot: int) -> int:
	return hotbar(class_id)[slot] if slot >= 0 and slot < 4 else 0


func ability(ability_id: int) -> Dictionary:
	return _library.abilities.get(ability_id, {})


## The class's always-on passive, drawn in the bar's first cell.
func passive(class_id: int) -> Dictionary:
	return _library.passives.get(int(_tree(class_id).get("passive", 0)), {})


func icon(ability_id: int) -> AtlasTexture:
	return _sprites.atlas_for(ability(ability_id), ICON_SIZE)


## How many points an ability takes; the content's own figure, else five.
func cap(ability_id: int) -> int:
	var definition := ability(ability_id)
	var declared := int(definition.get("maxSkillPoints", 0))
	var result := declared if declared > 0 else DEFAULT_CAP
	# Ultimates hard-cap at 3 regardless of declared max, so a mis-set ability
	# can't let the bar invest past what the server will accept.
	if int(definition.get("slotHint", -1)) == ULTIMATE_SLOT_HINT:
		result = mini(result, ULTIMATE_CAP)
	return result


## The cooldown after `invested` points, as the server computes it.
func cooldown_ms(ability_id: int, invested: int) -> int:
	var definition := ability(ability_id)
	var base := int(definition.get("baseCooldownMs", 0))
	if base <= 0:
		return 0
	return maxi(MIN_COOLDOWN_MS, base - invested * int(definition.get("cdReductionPerPointMs", 0)))


## Points also shorten a cast, at half the rate they shorten the cooldown.
func cast_ms(ability_id: int, invested: int) -> int:
	var definition := ability(ability_id)
	var base := int(definition.get("baseCastMs", 0))
	if base <= 0:
		return 0
	return maxi(MIN_CAST_MS, base - invested * int(definition.get("cdReductionPerPointMs", 0)) / 2)


## The projectile group an ability fires, or 0 for one that fires nothing.
func projectile_group(ability_id: int) -> int:
	for effect in ability(ability_id).get("effects", []):
		if str(effect.get("type", "")).to_upper() == "PROJECTILE_GROUP":
			return int(effect.get("projectileGroupId", 0))
	return 0


## Where a cast lands: pulled in to the ability's reach, or onto the caster
## for a self-cast. The server does the same before it reads the point, so
## predicting from the clamped one is what keeps a projectile on its line.
func clamp_target(ability_id: int, centre: Vector2, target: Vector2) -> Vector2:
	var reach := int(ability(ability_id).get("maxCastRange", -1))
	if reach < 0:
		return target
	if reach == 0:
		return centre
	return centre + (target - centre).limit_length(float(reach))


func _tree(class_id: int) -> Dictionary:
	return _library.classes.get(class_id, {}).get("abilityTree", {})
