class_name GameData
extends RefCounted

## Resolves wire ids into sprites and gameplay definitions: a thin facade over
## ContentLibrary (the JSON) and SpriteCache (the atlases).

const DEFAULT_TILE_SPRITE_SIZE := SpriteCache.DEFAULT_SPRITE_SIZE
const TILE_RENDER_SIZE := 32
const CRACK_CELL_HEIGHT := 16
## A tile_look entry: what the ground passes ask of a tile id, by index.
const LOOK_TEXTURE := 0
const LOOK_SIZE := 1
const LOOK_HEIGHT := 2
const LOOK_FLAGS := 3
const LOOK_WALL := 1
const LOOK_COLLISION := 2
const LOOK_SLOWS := 4
const LOOK_LIQUID := 8
const LOOK_NO_BLEND := 16
const NO_LOOK: Array = []
## StatusEffectType.SLOWED.
const SLOWED_EFFECT := 21

var library := ContentLibrary.new()
var sprites := SpriteCache.new()
## Class artwork, which is involved enough to live on its own.
var classes_art := ClassSprites.new(library, sprites)
## Per-group projectile attributes: the art's rotation offset and its spin.
var projectiles_art := ProjectileArt.new(library)
## A portal's art and name, which only its portalId carries on the wire.
var portals := PortalCatalog.new(library, sprites)
## Which map a mapId names, for the transition guards.
var maps := MapCatalog.new(library)
## What each class casts, and what a cast costs.
var abilities := AbilityCatalog.new(library, sprites)
## What experience means: level, and fame past the last level.
var levels := ExperienceLevels.new()
var ready := false
## tile id -> {color, radius in tiles, flickers}; built once from data.light,
## shared by the 2D SceneLighting and the 3D view. See light_emitters().
var _light_emitters := {}
var _light_emitters_built := false
## tile id -> true for water/lava tiles, matched by name; the animated LiquidRenderer
## draws only these. Built once, like _light_emitters.
var _liquid_tiles := {}
var _liquid_built := false
## tile id -> AtlasTexture, so the per-frame wall/tile passes skip rebuilding a
## string atlas key per cell. Populated once content is ready.
var _tex_by_id := {}
var _top_face_by_id := {}
## The same memoization for the per-bullet/per-enemy passes, which otherwise
## rebuilt a string atlas key per projectile and per enemy every frame.
var _proj_tex_by_group := {}
var _enemy_tex_by_id := {}
## tile id -> its data sub-dict, so the per-frame wall/collision/light scans stop
## re-walking library.tiles.get(id).get("data") on every cell every call.
var _data_by_id := {}
## group id -> {color: Color, radius, flickers}, the resolved projectile light the
## 2D/3D lighting scans read per bullet; the hex is parsed once here, not per frame.
var _proj_light_by_group := {}
## enemy id -> {color: Color, radius, flickers}, the resolved enemy glow (e.g. the
## cult effigies) the lighting scan reads; same shape and parse-once rule as above.
var _enemy_light_by_id := {}
## group id -> how long its shots slow a player they hit, in ms (0: they don't).
var _slow_ms_by_group := {}
## tile id -> tile_look(), read directly by the ground passes (a call per cell into
## another script costs more than the cell's draw).
var tile_looks := {}


## Content first, then every sheet it refers to. Awaited, because over HTTP
## both are requests; against the data repo on disk neither suspends, so the
## desktop path stays effectively synchronous through the same call.
func load_from(source: ContentSource) -> bool:
	var loaded: bool = await library.load_from(source)
	levels.parse(library.exp_levels)
	await sprites.preload_sheets(source, library.sheet_keys())
	ready = true
	return loaded


func summary() -> String:
	return library.summary()


## Content-load problems plus any sprite sheet that turned out to be missing.
var errors: Array[String]:
	get:
		var all: Array[String] = []
		all.append_array(library.errors)
		all.append_array(sprites.errors)
		return all

var tiles: Dictionary:
	get: return library.tiles
var enemies: Dictionary:
	get: return library.enemies
var items: Dictionary:
	get: return library.items
var projectile_groups: Dictionary:
	get: return library.projectile_groups


# --- tiles -----------------------------------------------------------------

## Everything the ground passes ask of a tile, resolved once: its texture, the
## square it draws into, its draw height and its LOOK_* flags.
func tile_look(tile_id: int) -> Array:
	var look: Array = tile_looks.get(tile_id, NO_LOOK)
	if not look.is_empty():
		return look
	var data := tile_data(tile_id)
	var flags := 0
	if int(data.get("isWall", 0)) != 0:
		flags |= LOOK_WALL
	if int(data.get("hasCollision", 0)) != 0:
		flags |= LOOK_COLLISION
	if int(data.get("slows", 0)) != 0:
		flags |= LOOK_SLOWS
	if tile_is_liquid(tile_id):
		flags |= LOOK_LIQUID
	if int(data.get("noBlend", 0)) != 0:
		flags |= LOOK_NO_BLEND
	look = [tile_texture(tile_id), tile_render_size(tile_id), tile_render_height(tile_id), flags]
	if ready:
		tile_looks[tile_id] = look
	return look


func tile_texture(tile_id: int) -> AtlasTexture:
	if _tex_by_id.has(tile_id):
		return _tex_by_id[tile_id]
	var texture := sprites.atlas_for(library.tiles.get(tile_id, {}))
	if ready:
		_tex_by_id[tile_id] = texture
	return texture


## How tall to draw this tile, in world pixels. Wall art is 8x16: the upper
## square is the top face and the lower one the front face, so it draws two
## cells tall anchored at the cell top and spills south over the floor below.
## Drawing it one cell tall shows only the top face.
func tile_render_height(tile_id: int) -> float:
	var definition: Dictionary = library.tiles.get(tile_id, {})
	var size := int(definition.get("spriteSize", DEFAULT_TILE_SPRITE_SIZE))
	var height := int(definition.get("spriteHeight", 0))
	if size <= 0 or height <= size:
		return float(TILE_RENDER_SIZE)
	return TILE_RENDER_SIZE * (float(height) / float(size))


## The square px a tile's sprite is drawn at (tiles.json `size`). Oversized decorations
## (large trees/bushes) render bigger than the 32px cell and spill over the neighbours you
## can walk under; the solid trunk stays the centre cell. Defaults to the cell, so ordinary
## tiles are unchanged.
func tile_render_size(tile_id: int) -> float:
	var definition: Dictionary = library.tiles.get(tile_id, {})
	var drawn := int(definition.get("size", TILE_RENDER_SIZE))
	return float(drawn) if drawn > 0 else float(TILE_RENDER_SIZE)


## The rect a tile's sprite is drawn into: its 32px cell, or a larger square centred on
## the cell for oversized decorations (large trees). One source of truth so every pass
## that draws the prop (billboard ring, body, bottom outline) agrees -- mismatched sizes
## were double-rendering a 32 behind the 64.
func tile_render_rect(tile_id: int, cell_rect: Rect2) -> Rect2:
	var drawn := tile_render_size(tile_id)
	if drawn <= cell_rect.size.x:
		return cell_rect
	var inset := (drawn - cell_rect.size.x) * 0.5
	return Rect2(cell_rect.position - Vector2(inset, inset), Vector2(drawn, drawn))


## The top `fraction` of a large decoration's sprite -- its canopy -- redrawn over the
## entities so a character behind/under it is covered. Null for ordinary tiles.
func tile_canopy(tile_id: int, fraction: float) -> AtlasTexture:
	return sprites.canopy_for(library.tiles.get(tile_id, {}), fraction, DEFAULT_TILE_SPRITE_SIZE)


## The square top face of a tall wall, or null for anything else. Redrawn
## above the entities so a character behind the wall is covered by it while
## one standing in front of its south-spilling face is not.
func tile_top_face(tile_id: int) -> AtlasTexture:
	if _top_face_by_id.has(tile_id):
		return _top_face_by_id[tile_id]
	var texture := sprites.top_face_for(library.tiles.get(tile_id, {}), DEFAULT_TILE_SPRITE_SIZE)
	if ready:
		_top_face_by_id[tile_id] = texture
	return texture


## A breakable wall's crack overlay for `stage` (1-3), the full 8x16 cell.
func crack_overlay(stage: int) -> AtlasTexture:
	return sprites.atlas(ContentLibrary.CRACK_SHEET, 0, stage - 1, DEFAULT_TILE_SPRITE_SIZE,
		DEFAULT_TILE_SPRITE_SIZE, CRACK_CELL_HEIGHT)


## The overlay's upper square: for square tiles, and for the wall top face redrawn over entities.
func crack_top_face(stage: int) -> AtlasTexture:
	return sprites.top_face(ContentLibrary.CRACK_SHEET, 0, stage - 1, DEFAULT_TILE_SPRITE_SIZE,
		CRACK_CELL_HEIGHT)


func tile_data(tile_id: int) -> Dictionary:
	if _data_by_id.has(tile_id):
		return _data_by_id[tile_id]
	var data: Dictionary = library.tiles.get(tile_id, {}).get("data", {})
	if ready:
		_data_by_id[tile_id] = data
	return data


func tile_has_collision(tile_id: int) -> bool:
	return int(tile_data(tile_id).get("hasCollision", 0)) != 0


func tile_slows(tile_id: int) -> bool:
	return int(tile_data(tile_id).get("slows", 0)) != 0


## Water or lava, matched by tile name -- what the animated liquid layer draws.
## Cached once the content has loaded (an empty library is never cached, so a
## lookup during the slow remote load doesn't freeze the set empty).
func tile_is_liquid(tile_id: int) -> bool:
	if not _liquid_built:
		if library.tiles.is_empty():
			return false
		_liquid_built = true
		for id in library.tiles:
			var lower := tile_name(id).to_lower()
			if "water" in lower or "lava" in lower:
				_liquid_tiles[id] = true
	return _liquid_tiles.has(tile_id)


func tile_is_wall(tile_id: int) -> bool:
	return int(tile_data(tile_id).get("isWall", 0)) != 0


func tile_name(tile_id: int) -> String:
	return library.tiles.get(tile_id, {}).get("name", "Unknown_%d" % tile_id)


## The light a tile emits, or an empty dict for the vast majority that emit
## none. {strength: reach in tiles, color: "#rrggbb", style: "flicker"|"steady"}.
func tile_light(tile_id: int) -> Dictionary:
	var light: Variant = tile_data(tile_id).get("light")
	return light if light is Dictionary else {}


## Every light-emitting tile id -> {color: Color, radius: reach in tiles,
## flickers: bool}, parsed once from data.light. The one source of truth both
## the 2D and 3D lighting scan against.
func light_emitters() -> Dictionary:
	if _light_emitters_built:
		return _light_emitters
	# Don't cache an empty map before the content has loaded, or a scan that ran
	# during the (slow, over-HTTP) load would freeze the lighting off for good.
	if library.tiles.is_empty():
		return _light_emitters
	_light_emitters_built = true
	for id in library.tiles:
		var light := tile_light(id)
		var strength := float(light.get("strength", 0.0))
		if strength <= 0.0:
			continue
		var hex := str(light.get("color", "#ffffff"))
		_light_emitters[id] = {
			"color": Color.html(hex) if Color.html_is_valid(hex) else Color.WHITE,
			"radius": strength,
			"flickers": str(light.get("style", "steady")) == "flicker",
		}
	return _light_emitters


# --- entities --------------------------------------------------------------

func enemy_texture(enemy_id: int) -> AtlasTexture:
	if _enemy_tex_by_id.has(enemy_id):
		return _enemy_tex_by_id[enemy_id]
	var texture := sprites.atlas_for(library.enemies.get(enemy_id, {}))
	if ready:
		_enemy_tex_by_id[enemy_id] = texture
	return texture


func enemy_name(enemy_id: int) -> String:
	return library.enemies.get(enemy_id, {}).get("name", "Enemy_%d" % enemy_id)


func projectile_texture(group_id: int) -> AtlasTexture:
	if _proj_tex_by_group.has(group_id):
		return _proj_tex_by_group[group_id]
	var texture := sprites.atlas_for(library.projectile_groups.get(group_id, {}))
	if ready:
		_proj_tex_by_group[group_id] = texture
	return texture


## How long a shot from this group slows the player it hits, in ms, or 0. The
## wire names a bullet's group, not which of the group's projectiles it is, so a
## group whose projectiles disagree counts as slowing only if most of them do.
func slow_ms(group_id: int) -> int:
	if _slow_ms_by_group.has(group_id):
		return _slow_ms_by_group[group_id]
	var projectiles: Array = library.projectile_groups.get(group_id, {}).get("projectiles", [])
	var slowing := 0
	var longest := 0
	for definition in projectiles:
		for effect in definition.get("effects", []):
			if int(effect.get("effectId", -1)) == SLOWED_EFFECT:
				slowing += 1
				longest = maxi(longest, int(effect.get("duration", 0)))
				break
	var result := longest if slowing * 2 > projectiles.size() else 0
	if ready:
		_slow_ms_by_group[group_id] = result
	return result


## The projectiles a group fires, with angles resolved from their string form.
func projectiles_in_group(group_id: int) -> Array:
	var out: Array = []
	for definition in library.projectile_groups.get(group_id, {}).get("projectiles", []):
		var resolved: Dictionary = definition.duplicate()
		resolved["angle"] = ProjectileAngle.parse(definition.get("angle", 0))
		out.append(resolved)
	return out


func item_projectile_group(item_id: int) -> int:
	return int(library.items.get(item_id, {}).get("damage", {}).get("projectileGroupId", 0))


## The light a projectile group emits, or an empty dict. Authored per group in
## projectile-groups.json (peer of spriteKey/fx), same {strength, color, style}
## shape as a tile's data.light -- so any projectile can glow, not just magic.
func projectile_light(group_id: int) -> Dictionary:
	var light: Variant = library.projectile_groups.get(group_id, {}).get("light")
	return light if light is Dictionary else {}


## The same light resolved to a Color + reach, parsed once per group -- what the
## per-frame lighting scans read, so they stop re-parsing the hex every bullet.
## Empty for the groups that emit none; built lazily, cached once content is ready.
func projectile_light_resolved(group_id: int) -> Dictionary:
	if _proj_light_by_group.has(group_id):
		return _proj_light_by_group[group_id]
	var light := projectile_light(group_id)
	var resolved := {}
	var strength := float(light.get("strength", 0.0))
	if strength > 0.0:
		var hex := str(light.get("color", "#ffffff"))
		resolved = {
			"color": Color.html(hex) if Color.html_is_valid(hex) else Color.WHITE,
			"radius": strength,
			"flickers": str(light.get("style", "steady")) == "flicker",
		}
	if ready:
		_proj_light_by_group[group_id] = resolved
	return resolved


## An enemy type's data.light ({strength, color, style}) resolved to {color, radius,
## flickers} -- same shape and parse-once caching as projectile_light_resolved, so the
## lighting scan can hang a travelling glow on glowing enemies (e.g. cult effigies).
func enemy_light_resolved(enemy_id: int) -> Dictionary:
	if _enemy_light_by_id.has(enemy_id):
		return _enemy_light_by_id[enemy_id]
	var light: Variant = library.enemies.get(enemy_id, {}).get("light")
	var resolved := {}
	if light is Dictionary:
		var strength := float(light.get("strength", 0.0))
		if strength > 0.0:
			var hex := str(light.get("color", "#ffffff"))
			resolved = {
				"color": Color.html(hex) if Color.html_is_valid(hex) else Color.WHITE,
				"radius": strength,
				"flickers": str(light.get("style", "steady")) == "flicker",
			}
	if ready:
		_enemy_light_by_id[enemy_id] = resolved
	return resolved


func item_name(item_id: int) -> String:
	return library.items.get(item_id, {}).get("name", "Item_%d" % item_id)


## The catalog entry behind a wire item: itemClass, archetypeId and the art
## travel by itemId, not on the item itself.
func item_definition(item_id: int) -> Dictionary:
	return library.items.get(item_id, {})


## Item art defaults to 8px cells, as the web client's `spriteSize || 8`.
func item_texture(item_id: int) -> AtlasTexture:
	return sprites.atlas_for(library.items.get(item_id, {}))


## Archetypes drive the multi-shot fan, spread, range and piercing the server
## applies, so a predicted shot has to read the same numbers.
func archetype_for_item(item_id: int) -> Dictionary:
	var archetype_id := int(library.items.get(item_id, {}).get("archetypeId", 0))
	return library.weapon_archetypes.get(archetype_id, {})
