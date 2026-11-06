class_name SceneLighting
extends Node2D

## Smooth light over pixel-art tiles: an ambient across the world canvas and a
## light at each glowing tile near the player. Which tiles glow, and in what colour
## and reach, is data -- a tile's data.light in tiles.json -- not a guess from its
## name. Walls and solid props occlude the light, so a lit room throws shadows past
## its walls. The player carries no light of their own (they don't emit) -- a
## lantern item may add one later.
##
## The UI sits on its own CanvasLayers, so none of it is darkened. Governed by
## the "lighting" graphics setting (Options > Graphics, or F3), on by default.

## Overworld/hub ambient: a daylit scene reads on its own, so this stays high and
## the tile lights are warm ACCENTS over it, not the only illumination. A dark base
## with bright pools reads as a cave -- wrong for a town. Dungeons get the drama via
## DUNGEON_DARKEN. Slight cool tint so the warm candles pop against it.
const AMBIENT := Color(0.78, 0.79, 0.85)
## How much a (non-vault) dungeon drops the ambient below the overworld -- this is
## where real darkness and light-pool contrast belong, not the hub.
const DUNGEON_DARKEN := 0.375
## Additive over the darkened world; a candle reads as a warm pool without
## blowing out the tiles around it.
const TILE_LIGHT_ENERGY := 2.0
## Projectiles whose group carries a data.light get a travelling glow; a small
## pool follows the nearest of them, coloured and sized from that data. Not
## shadow-casting -- a fast mover flickering shadows is noise, and cheaper.
const MAX_BULLET_LIGHTS := 20
## Which bullets carry the travelling lights is re-picked every this many frames;
## in between, the picked ones' lights only follow them.
const BULLET_LIGHT_RESELECT := 4
const BULLET_LIGHT_ENERGY := 1.6
## Enemy types whose data.light carries a glow (e.g. cult effigies) get a travelling
## light each, up to this many of the ones in view. Few enemies glow, so they're placed
## in iteration order rather than nearest-sorted like the bullets.
const MAX_ENEMY_LIGHTS := 12
const ENEMY_LIGHT_ENERGY := 1.5
const MAX_TILE_LIGHTS := 24
## Lava/water glow reaches farther but dimmer. The pooled tile light sat right on the
## liquid shader's own moving highlights and blew out its bright sine-wave spots up
## close; spreading the light over a wider radius at lower energy softens that overlap.
## Only lava tiles carry a data.light, so this is the lava glow and its bloom.
const LIQUID_GLOW_RANGE_MUL := 1.5
const LIQUID_GLOW_ENERGY_MUL := 0.57
## Shadow casting is per-platform (see _shadow_casters): a shadow pass runs per
## caster per frame, so web casts none and native casts from every visible light.
## The merge collapses wall runs into a handful of rects, so this cap is only ever
## approached by a huge open field; 192 covers a native viewport without leaking.
const MAX_OCCLUDERS := 192
## Penumbra width for the PCF13 filter. Wide so a shadow edge fades over many
## pixels into an organic gradient rather than a hard-lined wedge.
const SHADOW_SMOOTH := 11.0
## Shadows are drawn as a translucent WARM dark rather than opaque black, so light
## bleeds through behind an object (it never goes pitch black) and the shaded side
## reads warm and inviting instead of a cold, cut-out silhouette. Lower the alpha
## for even gentler shadows; raise it toward 1.0 for deeper ones.
const SHADOW_COLOR := Color(0.14, 0.11, 0.10, 0.5)
## Tiles do not move, so the view is rescanned every Nth frame, not every frame.
const SCAN_EVERY := 20
## Re-pick the glowing tiles the moment the player has moved this far (px), not only on
## the fixed cadence -- walking through a dense emitter field (a lava lake) otherwise
## only updates the lit set ~3x/sec and the glow steps instead of flowing.
const RESCAN_MOVE_SQ := 36.0

var _state: RealmState
var _content: GameData
var _ambient := CanvasModulate.new()
## A viewport glow that blooms only what the HDR 2D buffer lets exceed 1.0 -- the
## additive light pools -- so the candles/torches/glowing shots halo while the
## pixel art under the ambient stays crisp. Held off (environment null) until the
## lighting is live AND the bloom setting is on. (The 3D view runs its own
## glow-less environment on purpose -- full-screen glow hazed its effects.)
var _world_env := WorldEnvironment.new()
var _glow: Environment
var _bloom_active := false
var _pool: Array[PointLight2D] = []
var _bullet_lights: Array[PointLight2D] = []
var _enemy_lights: Array[PointLight2D] = []
var _enemy_lights_shown := 0
## enemy id -> its resolved data.light ({} for none), parsed once.
var _enemy_light_by_id := {}
var _enemy_energy := ENEMY_LIGHT_ENERGY
var _occluders: Array[LightOccluder2D] = []
## The rect each occluder last took, so a rescan rebuilds only the ones that moved.
var _occluder_rects: Array[Rect2i] = []
## The nearest light-emitting bullets this frame, nearest first.
var _near_distance := PackedFloat32Array()
var _near_at := PackedVector2Array()
var _near_light: Array = []
var _near_id := PackedInt64Array()
var _bullet_light_frame := 0
var _bullet_lights_shown := 0
## group id -> its resolved data.light ({} for none).
var _bullet_light_by_group := {}
## tile id -> whether it casts a wall shadow; reset with the emitters each rescan.
var _occludes_by_tile := {}
var _emitters := {}   # GameData.light_emitters(): tile id -> {color, radius, flickers}
var _frames := 0
## Player position at the last tile-light rescan, so a move past RESCAN_MOVE_SQ re-picks
## the lit set immediately for smooth glow while walking.
var _last_scan_centre := Vector2(INF, INF)
var _time := 0.0
## Whether the ambient is currently dimmed for a dungeon, so it only re-sets the
## CanvasModulate colour when that changes rather than every frame.
var _dungeon_dark := false
## Web GL-compat can't afford the 2D shadow passes, so on web every light is
## non-casting and no occluders are built (the ambient + additive pools stay).
## Native has the headroom, so it keeps shadows AND runs the glows slightly brighter.
var _web := OS.has_feature("web")
var _tile_energy := TILE_LIGHT_ENERGY
var _bullet_energy := BULLET_LIGHT_ENERGY
## The 2D scan already covers the whole viewport; this is how many of the emitters
## in it get a light. Native lights them all; web keeps the tighter cap.
var _max_tile_lights := MAX_TILE_LIGHTS if OS.has_feature("web") else 64
## How many of the nearest tile lights cast wall shadows. Web: 0 (no shadow passes
## at all). Native: the nearest handful -- each caster is its own shadow-map pass per
## frame, so lighting them all tanked crowded dungeon fights; the far candles still
## glow (they just stop throwing a wall shadow once past the nearest casters).
var _shadow_casters := 0 if OS.has_feature("web") else 16
## Native ambient runs 10% brighter (overworld and dungeon alike) than web.
var _ambient_mul := 1.0 if OS.has_feature("web") else 1.1


func setup(state: RealmState, content: GameData) -> void:
	_state = state
	_content = content
	_ambient.color = _ambient_color(false)
	add_child(_ambient)
	_glow = _glow_environment()
	add_child(_world_env)
	var glow_mul := 1.0 if _web else 1.134
	_tile_energy = TILE_LIGHT_ENERGY * glow_mul
	_bullet_energy = BULLET_LIGHT_ENERGY * glow_mul
	_enemy_energy = ENEMY_LIGHT_ENERGY * glow_mul
	var glow := _soft_texture()
	for i in _max_tile_lights:
		var light := PointLight2D.new()
		_light(light, glow, Color.WHITE, _tile_energy, 1.0)
		light.visible = false
		_pool.append(light)
	for i in MAX_BULLET_LIGHTS:
		var light := PointLight2D.new()
		_light(light, glow, Color.WHITE, _bullet_energy, 1.0)
		light.shadow_enabled = false
		light.visible = false
		_bullet_lights.append(light)
	for i in MAX_ENEMY_LIGHTS:
		var light := PointLight2D.new()
		_light(light, glow, Color.WHITE, _enemy_energy, 1.0)
		light.shadow_enabled = false
		light.visible = false
		_enemy_lights.append(light)
	_near_distance.resize(MAX_BULLET_LIGHTS)
	_near_at.resize(MAX_BULLET_LIGHTS)
	_near_light.resize(MAX_BULLET_LIGHTS)
	_near_id.resize(MAX_BULLET_LIGHTS)
	# Occluders only matter for shadow-casting lights, which web has none of.
	if not _web:
		for i in MAX_OCCLUDERS:
			var occluder := LightOccluder2D.new()
			var polygon := OccluderPolygon2D.new()
			polygon.closed = true
			occluder.occluder = polygon
			occluder.visible = false
			_occluders.append(occluder)
			_occluder_rects.append(Rect2i())
			add_child(occluder)


## A shadow-casting point light, added as a child.
func _light(light: PointLight2D, glow: GradientTexture2D, colour: Color, energy: float,
		scale: float) -> void:
	light.texture = glow
	light.color = colour
	light.energy = energy
	light.texture_scale = scale
	light.shadow_enabled = not _web
	if not _web:
		# PCF13 + a wide smooth gives a soft penumbra -- the shadow edge fades and
		# light bleeds gradually behind an object, instead of a hard black wedge. A
		# translucent warm shadow_color keeps the shaded side from going cold-black.
		light.shadow_filter = Light2D.SHADOW_FILTER_PCF13
		light.shadow_filter_smooth = SHADOW_SMOOTH
		light.shadow_color = SHADOW_COLOR
	add_child(light)


func _process(delta: float) -> void:
	var live := _state != null and _state.settings.is_on("lighting") \
		and _state.local != null and _state.tiles.width > 0
	if _ambient.visible != live:
		_ambient.visible = live
		for light in _pool:
			light.visible = false
		for light in _bullet_lights:
			light.visible = false
		_bullet_lights_shown = 0
		for light in _enemy_lights:
			light.visible = false
		_enemy_lights_shown = 0
		for occluder in _occluders:
			occluder.visible = false
		_frames = 0
	if not live:
		_set_bloom(false)
		return
	_set_bloom(_state.settings.is_on("bloom"))
	# Dungeons (not the vault) read a third darker than the overworld.
	var dark := _in_dungeon()
	if dark != _dungeon_dark:
		_dungeon_dark = dark
		_ambient.color = _ambient_color(dark)
	_time += delta
	# Rescan on the fixed cadence OR as soon as the player moves enough that the nearest
	# lit tiles would change, so the glow flows while walking instead of stepping ~3x/sec.
	var scan_centre := _state.local.render_centre()
	if _frames % SCAN_EVERY == 0 or scan_centre.distance_squared_to(_last_scan_centre) > RESCAN_MOVE_SQ:
		_rescan()
		_last_scan_centre = scan_centre
	_frames += 1
	for i in _pool.size():
		var light := _pool[i]
		if light.visible and light.get_meta("flickers", false):
			light.energy = float(light.get_meta("energy_base", _tile_energy)) \
				* (1.0 + 0.12 * sin(_time * 9.0 + i * 1.7) + 0.06 * sin(_time * 23.0 + i))
	# Bullets move every frame, so this is not on the tile scan's cadence.
	_place_bullet_lights()
	_place_enemy_lights()


## The nearest light-emitting bullets in flight, one travelling light each,
## coloured and sized from the projectile group's data.light. The nearest
## MAX_BULLET_LIGHTS are kept in a small sorted insertion list as the bullets
## are walked, rather than collecting and sorting every glowing bullet.
func _place_bullet_lights() -> void:
	# Opt-out sub-toggle of Dynamic lighting: skip the travelling bullet glows (and
	# their per-frame scan) when the player turns projectile lighting off.
	if not _state.settings.is_on("projectile_lighting"):
		if _bullet_lights_shown > 0:
			for light in _bullet_lights:
				light.visible = false
			_bullet_lights_shown = 0
		return
	_bullet_light_frame += 1
	if _bullet_light_frame % BULLET_LIGHT_RESELECT != 0:
		_follow_bullet_lights()
		return
	# A bullet we don't draw must not cast light either -- another player's shot
	# with "show other players' bullets" off, or one hidden by Blind.
	var visibility := BulletVisibility.of(_state)
	var centre := _state.local.render_centre()
	var found := 0
	var limit := _bullet_lights.size()
	for bullet: Projectile in _state.projectiles.bullets.values():
		var group_id := bullet.group_id
		var light_def: Variant = _bullet_light_by_group.get(group_id)
		if light_def == null:
			# Resolved once per group (colour hex parsed there), not per bullet per frame.
			light_def = _content.projectile_light_resolved(group_id)
			_bullet_light_by_group[group_id] = light_def
		if light_def.is_empty() or (visibility.any and visibility.hides(bullet)):
			continue
		var half := bullet.size * 0.5
		var at := bullet.pos + Vector2(half, half)
		var distance := at.distance_squared_to(centre)
		if found == limit and distance >= _near_distance[limit - 1]:
			continue
		var slot := mini(found, limit - 1)
		while slot > 0 and _near_distance[slot - 1] > distance:
			_near_distance[slot] = _near_distance[slot - 1]
			_near_at[slot] = _near_at[slot - 1]
			_near_light[slot] = _near_light[slot - 1]
			_near_id[slot] = _near_id[slot - 1]
			slot -= 1
		_near_distance[slot] = distance
		_near_at[slot] = at
		_near_light[slot] = light_def
		_near_id[slot] = bullet.id
		found = mini(found + 1, limit)
	for i in limit:
		var light := _bullet_lights[i]
		var shown := i < found
		if light.visible != shown:
			light.visible = shown
		if shown:
			var light_def: Dictionary = _near_light[i]
			light.position = _near_at[i]
			light.color = light_def["color"]
			light.texture_scale = _scale_for(light_def["radius"])
	_bullet_lights_shown = found


## Between reselections the chosen bullets' lights just follow them, and a light
## whose bullet is gone goes out.
func _follow_bullet_lights() -> void:
	var bullets: Dictionary = _state.projectiles.bullets
	for i in _bullet_lights_shown:
		var light := _bullet_lights[i]
		var bullet: Projectile = bullets.get(_near_id[i])
		if bullet == null:
			if light.visible:
				light.visible = false
			continue
		var half := bullet.size * 0.5
		light.position = bullet.pos + Vector2(half, half)


## Enemy types whose data.light carries a glow get a travelling light each (the cult
## effigies, say). Few enemies glow, so the ones in view are lit in iteration order up
## to the pool cap rather than nearest-sorted like the bullets.
func _place_enemy_lights() -> void:
	var view := ViewRect.of(self)
	var limit := _enemy_lights.size()
	var shown := 0
	for id in _state.entities.enemies:
		if shown >= limit:
			break
		var enemy: Dictionary = _state.entities.enemies[id]
		var enemy_id: int = enemy.get("enemy_id", -1)
		var light_def: Variant = _enemy_light_by_id.get(enemy_id)
		if light_def == null:
			light_def = _content.enemy_light_resolved(enemy_id)
			_enemy_light_by_id[enemy_id] = light_def
		if light_def.is_empty():
			continue
		var size := float(enemy.get("size", 16))
		var at: Vector2 = _state.entities.render_position(enemy) + Vector2(size * 0.5, size * 0.5)
		if not view.has_point(at):
			continue
		var light := _enemy_lights[shown]
		if not light.visible:
			light.visible = true
		light.position = at
		light.color = light_def["color"]
		light.texture_scale = _scale_for(light_def["radius"])
		if light_def.get("flickers", false):
			light.energy = _enemy_energy \
				* (1.0 + 0.12 * sin(_time * 9.0 + shown * 1.7) + 0.06 * sin(_time * 23.0 + shown))
		else:
			light.energy = _enemy_energy
		shown += 1
	for i in range(shown, _enemy_lights_shown):
		_enemy_lights[i].visible = false
	_enemy_lights_shown = shown


## The glowing tiles in view get a light each (nearest the player first), and the
## walls and solid props an occluder each, so those lights throw shadows.
func _rescan() -> void:
	var emitters := _content.light_emitters()
	if not is_same(emitters, _emitters):
		_emitters = emitters
		_occludes_by_tile.clear()
	var tile := float(GameConstants.TILE_SIZE)
	var solid: Dictionary = _state.tiles.layers.get(GameConstants.COLLISION_LAYER, {})
	var view := ViewRect.of(self)
	var centre := _state.local.render_centre()
	var found := []
	var walls := []
	for y in range(floori(view.position.y / tile), ceili(view.end.y / tile)):
		for x in range(floori(view.position.x / tile), ceili(view.end.x / tile)):
			var cell := Vector2i(x, y)
			for layer in _state.tiles.layers:
				var tile_id: int = _state.tiles.layers[layer].get(cell, -1)
				var kind: Variant = _emitters.get(tile_id)
				if kind != null:
					var at := Vector2(x + 0.5, y + 0.5) * tile
					found.append([at.distance_squared_to(centre), at, kind, tile_id])
			if not _web and _occludes(solid.get(cell, -1)):
				walls.append(cell)
	found.sort_custom(_nearer)
	for i in _pool.size():
		var light := _pool[i]
		light.visible = i < found.size()
		if light.visible:
			var kind: Dictionary = found[i][2]
			var liquid: bool = _content.tile_is_liquid(int(found[i][3]))
			light.position = found[i][1]
			light.color = kind["color"]
			var radius: float = float(kind["radius"]) * (LIQUID_GLOW_RANGE_MUL if liquid else 1.0)
			light.texture_scale = _scale_for(radius)
			light.set_meta("flickers", kind["flickers"])
			# Base energy (incl. the liquid dimming) is stashed so the per-frame flicker
			# loop modulates THIS value, not the raw _tile_energy.
			var energy := _tile_energy * (LIQUID_GLOW_ENERGY_MUL if liquid else 1.0)
			light.energy = energy
			light.set_meta("energy_base", energy)
			# found is distance-sorted; the nearest _shadow_casters cast (all on native).
			light.shadow_enabled = i < _shadow_casters
	var rects := _merge_wall_rects(walls)
	for i in _occluders.size():
		var occluder := _occluders[i]
		var shown := i < rects.size()
		if occluder.visible != shown:
			occluder.visible = shown
		if not shown:
			continue
		var rect: Rect2i = rects[i]
		# A polygon assignment re-uploads the occluder, so only a changed rect pays it.
		if rect == _occluder_rects[i]:
			continue
		_occluder_rects[i] = rect
		occluder.position = Vector2(rect.position) * tile
		var wide := float(rect.size.x) * tile
		var tall := float(rect.size.y) * tile
		occluder.occluder.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(wide, 0), Vector2(wide, tall), Vector2(0, tall)])


## Only WALLS cast shadows. Solid decorations (trees, bushes -- hasCollision but
## not isWall) used to occlude too, which threw hard trapezoidal wedge shadows off
## every large tree; the web client casts no object shadows and reads far smoother.
## Now a decoration just gets the soft radial bloom, while walls still block light.
## A tile that emits its own light is never made to shadow itself.
func _occludes(tile_id: int) -> bool:
	if tile_id <= 0:
		return false
	var occludes: Variant = _occludes_by_tile.get(tile_id)
	if occludes == null:
		occludes = not _emitters.has(tile_id) and _content.tile_is_wall(tile_id)
		_occludes_by_tile[tile_id] = occludes
	return occludes


## The CanvasModulate colour: the base ambient (a third darker in a dungeon),
## scaled by the platform ambient multiplier, alpha kept at 1.
func _ambient_color(dark: bool) -> Color:
	var c := AMBIENT.darkened(DUNGEON_DARKEN) if dark else AMBIENT
	return Color(c.r * _ambient_mul, c.g * _ambient_mul, c.b * _ambient_mul, 1.0)


## In an assembled dungeon that isn't the personal vault -- where the ambient dims.
func _in_dungeon() -> bool:
	return _state.tiles.dungeon_id >= 0 and not _content.maps.is_vault(_state.tiles.map_id)


## Attach or detach the glow environment; a null environment on the WorldEnvironment
## is the off state, so the glow pass only runs while bloom is wanted.
func _set_bloom(on: bool) -> void:
	if on == _bloom_active:
		return
	_bloom_active = on
	_world_env.environment = _glow if on else null


## Glow tuned to bloom only the over-bright light pools: the HDR threshold sits at
## 1.0 so nothing under the ambient (all <= 1.0) blooms, and glow_bloom stays 0 so
## there is no flat haze added to every pixel -- only what the additive lights push
## past 1.0 halos. The mid levels give a soft, wide falloff without a hard ring.
func _glow_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Threshold raised 1.0 -> 1.5: the lava SURFACE sits just over 1.0 and was blooming
	# wholesale into a yellow wash. Point lights (crystals/bullets ~1.8-2.3 energy) are
	# still above this, so their halo stays; only the broad over-bright terrain stops.
	env.glow_hdr_threshold = 1.5
	env.glow_hdr_scale = 1.4
	for level in 7:
		env.set_glow_level(level, 0.0)
	env.set_glow_level(1, 0.4)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.6)
	return env


## Distance-first comparator, hoisted so a fresh closure isn't allocated every
## scan and every bullet-light pass.
static func _nearer(a: Array, b: Array) -> bool:
	return a[0] < b[0]


## A light `radius` tiles across its bright half, on the 256px texture.
func _scale_for(radius_tiles: float) -> float:
	return radius_tiles * 2.0 * GameConstants.TILE_SIZE / 256.0


## Contiguous wall/prop cells merged into maximal rectangles, so a wall run casts
## one clean shadow rather than a stripe of per-tile ones -- and a walled room
## fits in a handful of occluders instead of blowing the pool's cap and leaking
## light through the tiles that didn't fit. Cells arrive row-major, so the first
## unclaimed one is always a rectangle's top-left.
func _merge_wall_rects(cells: Array) -> Array:
	var solid := {}
	for cell in cells:
		solid[cell] = true
	var claimed := {}
	var rects := []
	for cell in cells:
		if claimed.has(cell):
			continue
		var wide := 1
		while solid.has(Vector2i(cell.x + wide, cell.y)) \
				and not claimed.has(Vector2i(cell.x + wide, cell.y)):
			wide += 1
		var tall := 1
		while _row_solid(solid, claimed, cell, wide, tall):
			tall += 1
		for dy in tall:
			for dx in wide:
				claimed[Vector2i(cell.x + dx, cell.y + dy)] = true
		rects.append(Rect2i(cell.x, cell.y, wide, tall))
	return rects


func _row_solid(solid: Dictionary, claimed: Dictionary, origin: Vector2i, wide: int, row: int) -> bool:
	for dx in wide:
		var cell := Vector2i(origin.x + dx, origin.y + row)
		if not solid.has(cell) or claimed.has(cell):
			return false
	return true


## White at the centre to nothing at the edge, eased so the fall-off has no
## visible ring.
static func _soft_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture
