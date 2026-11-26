class_name WorldView3D
extends Node3D

## A real-3D view of the realm, the Graphics "2.5D view" option: the ground textured
## quads (MultiMesh), the walls extruded boxes (MultiMesh), and every prop,
## player, enemy, loot, portal and projectile a sprite in 3D -- the same art the
## 2D renderer draws. Standing things (props, characters) are upright Y-billboards
## with a ground shadow; projectiles lie flat on the ground
## rotated to their heading; the ability effects are the real 2D EffectRenderer
## projected onto the floor. The pinned overlay (names, bars, damage numbers,
## bubbles, loot) is the real EntityOverlay, driven through this view's 3D camera
## rather than re-drawn -- see _update_overlay. The 2D WorldRenderer is hidden.
##
## World space is the 2D world's own pixels: 2D (x, y) is 3D (x, 0, y), y up.
## Performance: ground/walls are MultiMesh (one draw call per tile texture) built
## once per map, not per move; sprites are pooled and updated in place.
##
## A prototype: aim/movement still read the 2D camera, so they are not yet
## relative to the orbit angle.

const TILE := GameConstants.TILE_SIZE
const COLLISION_LAYER := GameConstants.COLLISION_LAYER
# Walls are perfect cubes, one tile on every edge.
const WALL_HEIGHT := float(TILE)
const ENTITY_RANGE := 900.0
const BULLET_HEIGHT := 12.0
const SHADOW_SIZE := 32
## A ground shadow is offset this fraction of the sprite's height along the sun's
## ground direction, so it reads as a cast shadow (and shows when the camera is
## behind the sprite) instead of a disc hidden under the body.
const SHADOW_CAST_FACTOR := 0.4
## Camera distance from the player. Pitch (degrees above the ground) rides the
## mouse wheel, height shift+wheel (see DESCENT_STEP); yaw rides Q/E. Sprites are full billboards, so they always face
## the camera and tilt to match whatever pitch is chosen -- no foreshortening,
## the art stays fully preserved instead of squished.
const CAM_DIST := 755.0
const PITCH_DEFAULT := 55.0
const PITCH_MIN := 25.0
const PITCH_MAX := 80.0
const PITCH_STEP := 6.0
## Orthographic vertical extent in world units (the zoom); ~720 base rows.
const CAM_ORTHO_SIZE := 720.0
const ORBIT_SPEED := 1.8
## Shift+wheel lowers the camera from the sky to the player's eye: descent 0 is the
## orthographic view above; past 0 the camera turns perspective, closing in while
## its field of view widens (so the player keeps its framing) and levelling out,
## until at 1 it sits at EYE_HEIGHT inside the head, looking along the orbit.
const DESCENT_STEP := 0.1
const DESCENT_RATE := 10.0
const EYE_HEIGHT := float(TILE)
const FOV_HIGH := 12.0
const FOV_LOW := 70.0
const PITCH_EYE := 8.0
## Bullets lie flat on the ground, edge-on to a low camera; below this pitch they
## stand up facing it instead.
const UPRIGHT_BELOW_PITCH := 30.0
## The overlay's tags are pinned by an affine fit, which drifts in perspective; below
## this the overlay places every tag and number exactly through the camera.
const OVERLAY_EXACT_DESCENT := 0.35
## Standing sprites face the camera, so looking into the sun shows their unlit
## backs. A shadowless fill light on their own light layer shines from the camera,
## as strong as the sun when the camera faces straight into it and off when the
## sun is behind the camera, so they read lit from any orbit. Ground and walls are
## not on the layer, so their light and shadows don't change.
const SPRITE_LIGHT_LAYER := 2
const FILL_MATCH := 1.0
## Nearer than this, the camera is inside the player's own sprite.
const HIDE_SELF_DISTANCE := 40.0
## Distance fog past the player, so a low camera doesn't see the floor end.
const FOG_BEGIN := 450.0
const FOG_END := 850.0
## The whole 2.5D picture's exposure; tuned apart from the flat view's lighting.
const BRIGHTNESS := 1.17
# The effect layer renders the 2D EffectRenderer into a SubViewport and projects
# it onto the ground, so its texel density (PX / REGION) is what the effects read
# at. The region is centred on the player each frame, so it only has to cover the
# visible ground -- kept tight, and the resolution high, so effects stay crisp
# instead of magnified into a blur.
const FX_REGION := 1600.0
## The effect target resolution is platform-split (see _fx_px): native renders the
## cast animations at 2048 with MSAA, so they read smooth and crisp instead of the
## coarse, aliased blur a bare 1024 gave; web stays at 1024 for the fill budget.
## The ground is the 2D TileRenderer (base tiles + feather blending) rendered into
## a SubViewport and projected onto the floor plane, so 3D gets the exact soft
## tile seams the 2D client has. Region covers the visible floor + orbit; the
## texture is re-rasterised only when the player crosses GROUND_MOVE_STEP, and the
## TileRenderer chunk-caches, so most re-centres redraw nothing.
const GROUND_REGION := 1800.0
const GROUND_VIEWPORT_PX := 2048
const GROUND_MOVE_STEP := float(TILE) * 4.0
## The world span used to fit the overlay's affine projector to the 3D camera.
const OVERLAY_PROBE := 120.0
## Exponential rate (1/s) the camera eases toward the player. The follow point is
## the 64Hz-interpolated player position, whose per-frame step is uneven at an
## unlocked native frame rate; snapping the camera straight to it showed that as
## jitter. A fast ease (~35ms half-life) filters the wobble with barely any lag.
const CAM_FOLLOW_RATE := 20.0

## Dynamic lighting (the "lighting" setting, shared data.light emitters with the
## 2D SceneLighting). Off restores the old full-bright look; on darkens the scene
## and lets torches, lava and crystals pool real 3D light the walls occlude.
## How many nearest emitters get an omni and how far out they're gathered are set
## per-platform in _max_lights / _light_range below (native lights the whole view).
const LIGHT_SCAN_EVERY := 10
## Squared-distance deadband (px^2) favouring a tile that is already lit when the
## nearest-N pool is re-ranked: it keeps its omni until a dark tile beats it by
## more than this, so emitters at the Nth-nearest boundary stop flickering on and
## off as the player moves. ~3 tiles.
const LIGHT_HYSTERESIS_SQ := (3.0 * float(TILE)) * (3.0 * float(TILE))
## How far out emitter tiles are gathered (px), wider than the entity load range
## so lava pools past the visible edge still throw light before you reach them.
const LIGHT_RANGE := ENTITY_RANGE * 1.6
## Sits at wall-top height so the light spills over the top faces too, not just
## the sides -- 3D lights are real, so height matters (unlike the flat 2D pools).
const LIGHT_HEIGHT := float(TILE) * 1.0
## 3D is lit independently of the 2D client -- real per-fragment lighting reads far
## dimmer than the 2D additive pools, so these run hotter. Tune these, not 2D's.
## High, because the pools are deliberately tight (below) -- a concentrated bright
## glow reads far better than a large dim wash, and it's what makes a lone candle
## pop against the ambient.
const TORCH_ENERGY := 80.0
## Reach multiplier on a tile's data light strength (px = strength * tile * this).
## Kept tight: a big radius smears the energy into an invisible wash AND makes
## clustered emitters (lava) overlap and blow out, so tightening it both makes a
## single candle glow and shrinks the bright-lava-vs-dim-candle gap.
const LIGHT_REACH_MUL := 1.6
## Overworld/hub ambient reads like daylight -- the scene stands on its own and the
## torches/lava are warm accents over it, not the only light. A dark base with bright
## pools reads as a cave, wrong for a town; the drama lives in dungeons (DUNGEON_DIM).
const AMBIENT_LIT := Color(0.6, 0.61, 0.67)
const AMBIENT_LIT_ENERGY := 0.9
## Inside a (non-vault) dungeon, ambient and sun drop to this fraction -- markedly
## darker than the daylit overworld, so a dungeon's torch pools carry real contrast.
const DUNGEON_DIM := 0.2
## The overworld/hub is lit too, but the full sun washed out candle/torch pools (you
## couldn't see them in the nexus), so it's pulled down ~60% -- an evening town rather
## than flat noon -- while staying a touch above DUNGEON_DIM so it still reads brighter
## than a dungeon.
const OVERWORLD_DIM := 0.4
## A daytime sun: strong enough to shade the billboards and throw crisp wall shadows.
const SUN_LIT_ENERGY := 0.6
## Wand/staff/tome bullets carry a travelling arcane glow. Kept small so a volley
## doesn't evict the candle/torch lights from the per-object light budget.
const MAX_BULLET_LIGHTS_3D := 6
const BULLET_LIGHT_COLOR := Color(0.72, 0.62, 1.0)
const BULLET_LIGHT_ENERGY := 25.0
const BULLET_LIGHT_RANGE := float(TILE) * 2.0
## Enemy types whose data.light carries a glow (cult effigies, the Heartwood) get a
## travelling omni each, like the flat view's enemy lights.
const MAX_ENEMY_LIGHTS_3D := 6
const ENEMY_LIGHT_ENERGY := 50.0
const ENEMY_LIGHT_HEIGHT := float(TILE) * 0.75

var state: RealmState
var content: GameData
## The real pinned overlay, driven through this camera while 3D is up.
var overlay: EntityOverlay
## Player input, told the orbit angle so WASD stays screen-relative.
var input: PlayerInput
## True while a chat line or an options rebind owns the keyboard, so Q/E do not
## orbit the camera out from under someone who is typing.
var keyboard_captured: Callable = func() -> bool: return false

var _camera: Camera3D
var _backdrop: MeshInstance3D
var _map_root: Node3D
var _sprite_root: Node3D
var _entities: Array[Sprite3D] = []
var _projectiles: Array[Sprite3D] = []
var _projectile_shadows: Array[Sprite3D] = []
var _entity_queue := EntityQueue.new()
var _grey_wall := StandardMaterial3D.new()
var _wall_materials := {}
var _shadow: ImageTexture
var _map_built := false
## Vector2i cell -> Array of emitter kinds (one per layer that emits there),
## built once per map in _rebuild_map_if_changed. The light scan walks this
## handful of cells instead of sweeping the whole ~150x150 reach box every call.
var _emitter_cells := {}
var _yaw := 0.0
var _pitch := PITCH_DEFAULT
var _descent := 0.0
var _descent_goal := 0.0
var _camera_distance := CAM_DIST
var _bullets_upright := false
var _fill: DirectionalLight3D

var _sun: DirectionalLight3D
## The sun's travel direction projected onto the ground, so shadows cast the way
## the sun's do; filled from the sun in _ready.
var _shadow_ground_dir := Vector2.ZERO
var _env: Environment
var _lights: Array[OmniLight3D] = []
var _bullet_lights: Array[OmniLight3D] = []
var _enemy_lights: Array[OmniLight3D] = []
var _light_frames := 0
var _light_time := 0.0
var _lit := false
var _lit_applied := false
## Whether the ambient/sun are currently dimmed for a dungeon.
var _dark := false

var _fx_viewport: SubViewport
var _fx_renderer: EffectRenderer
var _fx_camera: Camera2D
var _fx_ground: MeshInstance3D

var _ground_viewport: SubViewport
var _ground_renderer: TileRenderer
var _ground_camera: Camera2D
## GroundChunks.queued when the floor last re-rendered.
var _ground_queued := 0
var _ground_plane: MeshInstance3D
## Where the projected ground was last re-rasterised; INF forces the first render.
var _ground_centre := Vector2(INF, INF)
## Web GL-compat is far tighter than native: fewer lights, a smaller gather range
## and ground target there. Native has the headroom to light the whole viewport
## (many more emitters, gathered far past the player) and runs glows 50% brighter.
var _glow_mul := 1.0 if OS.has_feature("web") else 1.5
var _max_lights := 12 if OS.has_feature("web") else 48
var _light_range := LIGHT_RANGE if OS.has_feature("web") else 2400.0
var _ground_px := 1024 if OS.has_feature("web") else GROUND_VIEWPORT_PX
var _torch_energy := TORCH_ENERGY * (1.0 if OS.has_feature("web") else 1.5)
## Effect target: native renders the cast animations at 2048, web at 1024.
var _fx_px := 1024 if OS.has_feature("web") else 2048
## The smoothed point the camera orbits. INF until the first frame, when it snaps
## to the player; thereafter it eases toward them (see CAM_FOLLOW_RATE).
var _cam_follow := Vector2(INF, INF)
## Cells lit by the last light scan, for the hysteresis in _place_lights.
var _lit_cells := {}


func setup(realm_state: RealmState, game_data: GameData) -> void:
	state = realm_state
	content = game_data


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	_sun.light_energy = 1.1
	# The key light the walls actually cast from: directional shadows are the ones
	# the GL-compatibility (web) renderer supports, unlike positional/omni shadows.
	_sun.shadow_enabled = true
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.shadow_enabled = false
	_fill.light_cull_mask = SPRITE_LIGHT_LAYER
	_fill.light_energy = 0.0
	add_child(_fill)
	# Where the sun's rays travel across the ground -- the direction a shadow falls,
	# so the ground-shadow discs cast the same way the sun's real wall shadows do.
	var sun_forward := -_sun.transform.basis.z
	_shadow_ground_dir = Vector2(sun_forward.x, sun_forward.z)
	if _shadow_ground_dir.length() > 0.001:
		_shadow_ground_dir = _shadow_ground_dir.normalized()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 1.0
	env.tonemap_exposure = BRIGHTNESS
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = env.background_color
	env.fog_sun_scatter = 0.0
	# No glow/bloom: it blurred the bright ability effects (and pixel art in
	# general) into a fuzzy haze. Effects must read crisp like the rest of the scene.
	_env = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Orthographic, not perspective: it keeps the angled 2.5D look, but world ->
	# screen is then an exact affine, so the overlay's affine projector pins
	# names, bars, portal captions and loot precisely at any position and any
	# orbit -- perspective made a single affine drift for far entities. Shift+wheel's
	# descent turns it perspective; below OVERLAY_EXACT_DESCENT the overlay places
	# its tags and numbers through the camera exactly instead.
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAM_ORTHO_SIZE
	_camera.near = 1.0
	_camera.far = 5000.0
	_camera.current = true
	add_child(_camera)

	_backdrop = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8000.0, 8000.0)
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.albedo_color = Color(0.08, 0.08, 0.10)
	backdrop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane.material = backdrop_material
	_backdrop.mesh = plane
	add_child(_backdrop)

	_grey_wall.albedo_color = Color(0.5, 0.48, 0.54)
	_grey_wall.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_grey_wall.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow = _make_shadow()

	_map_root = Node3D.new()
	add_child(_map_root)
	_sprite_root = Node3D.new()
	add_child(_sprite_root)
	_build_effect_ground()
	_build_projected_ground()
	_build_lights()


## Leaving the 2.5D view with the camera down must not leave the flat view's tags hidden.
func _exit_tree() -> void:
	if overlay != null:
		overlay.exact = false


func _process(delta: float) -> void:
	if state == null or content == null or state.local == null:
		return
	# Q swings the view left of the player, E right -- but not while typing.
	if not keyboard_captured.call():
		if Input.is_key_pressed(KEY_Q):
			_yaw += ORBIT_SPEED * delta
		if Input.is_key_pressed(KEY_E):
			_yaw -= ORBIT_SPEED * delta
	if input != null:
		input.view_yaw = _yaw
		input.world_mouse = get_ground_point
	var centre := state.local.render_centre()
	_rebuild_map_if_changed()
	_follow_camera(centre, delta)
	_backdrop.position = Vector3(centre.x, -2.0, centre.y)
	var used := _place_entities(centre)
	for i in range(used, _entities.size()):
		_entities[i].visible = false
	_place_projectiles(centre)
	_update_effects(centre)
	_update_projected_ground(centre)
	_update_overlay(centre)
	_update_lighting(delta, centre)
	_update_fill()


## The mouse's world point on the ground (y=0) through the 3D camera, as a 2D
## (x, z), so shooting and ability casts aim where the cursor is at any orbit.
## Null off-plane.
func get_ground_point() -> Variant:
	if _camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var direction := _camera.project_ray_normal(mouse)
	if direction.y > -0.0001:
		# At or above a low camera's horizon: aim along the cursor's direction.
		var across := Vector2(direction.x, direction.z)
		if across.length() < 0.0001:
			return null
		return Vector2(origin.x, origin.z) + across.normalized() * ENTITY_RANGE
	var hit := origin + direction * (-origin.y / direction.y)
	return Vector2(hit.x, hit.z)


## Mouse wheel tilts the camera: up raises the angle toward top-down, down drops
## it toward a more acute, side-on angle. Full-billboard sprites follow suit.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var button: int = event.button_index
	if event.shift_pressed:
		# Some platforms turn shift+wheel into a sideways scroll.
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_LEFT:
			_descent_goal = clampf(_descent_goal - DESCENT_STEP, 0.0, 1.0)
		elif button == MOUSE_BUTTON_WHEEL_DOWN or button == MOUSE_BUTTON_WHEEL_RIGHT:
			_descent_goal = clampf(_descent_goal + DESCENT_STEP, 0.0, 1.0)
	elif button == MOUSE_BUTTON_WHEEL_UP:
		_pitch = clampf(_pitch + PITCH_STEP, PITCH_MIN, PITCH_MAX)
	elif button == MOUSE_BUTTON_WHEEL_DOWN:
		_pitch = clampf(_pitch - PITCH_STEP, PITCH_MIN, PITCH_MAX)


func _follow_camera(centre: Vector2, delta: float) -> void:
	# Ease the orbit point toward the player rather than snapping: the interpolated
	# follow point advances in uneven per-frame steps at an unlocked frame rate, which
	# a hard snap renders as camera jitter. Frame-rate independent; snaps on the first
	# frame (and on any zero/negative delta) so there's no slide-in from the origin.
	if _cam_follow.x == INF or delta <= 0.0:
		_cam_follow = centre
	else:
		_cam_follow = _cam_follow.lerp(centre, 1.0 - exp(-CAM_FOLLOW_RATE * delta))
	_descent = lerpf(_descent, _descent_goal, 1.0 - exp(-DESCENT_RATE * maxf(delta, 0.0)))
	if absf(_descent - _descent_goal) < 0.001:
		_descent = _descent_goal
	var pitch := deg_to_rad(lerpf(_pitch, PITCH_EYE, _descent))
	if _descent <= 0.0:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera_distance = CAM_DIST
	else:
		var fov := lerpf(FOV_HIGH, FOV_LOW, _descent)
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov
		# The distance at which this field of view frames what the orthographic view
		# shows, closing to zero at the eye.
		_camera_distance = CAM_ORTHO_SIZE / (2.0 * tan(deg_to_rad(fov) * 0.5)) * (1.0 - _descent)
	_camera.far = _camera_distance + 5000.0
	var target := Vector3(_cam_follow.x, EYE_HEIGHT * _descent, _cam_follow.y)
	var basis := Basis.from_euler(Vector3(-pitch, _yaw, 0.0))
	_camera.transform = Transform3D(basis, target + basis.z * _camera_distance)
	_bullets_upright = rad_to_deg(pitch) < UPRIGHT_BELOW_PITCH
	_env.fog_enabled = _descent > 0.0
	if _env.fog_enabled:
		_env.fog_density = clampf(_descent * 3.0, 0.0, 1.0)
		_env.fog_depth_begin = _camera_distance + FOG_BEGIN
		_env.fog_depth_end = _camera_distance + FOG_END
	if overlay != null:
		overlay.exact = _descent >= OVERLAY_EXACT_DESCENT


## Fits the overlay an affine world->screen transform to the 3D camera at the
## player's feet -- exact for points on the ground near the player, close enough
## for the tags around them -- so the real EntityOverlay (names, bars, damage
## numbers, bubbles, loot) pins to the 3D bodies. Its own _process reads these.
func _update_overlay(centre: Vector2) -> void:
	if overlay == null:
		return
	var origin_screen := _camera.unproject_position(Vector3(centre.x, 0.0, centre.y))
	var along_x := (_camera.unproject_position(Vector3(centre.x + OVERLAY_PROBE, 0.0, centre.y)) - origin_screen) / OVERLAY_PROBE
	var along_z := (_camera.unproject_position(Vector3(centre.x, 0.0, centre.y + OVERLAY_PROBE)) - origin_screen) / OVERLAY_PROBE
	overlay.world_projector = Transform2D(along_x, along_z, origin_screen - along_x * centre.x - along_z * centre.y)
	overlay.world_view = Rect2(centre - Vector2(ENTITY_RANGE, ENTITY_RANGE), Vector2(ENTITY_RANGE, ENTITY_RANGE) * 2.0)
	overlay.project_3d = true
	overlay.world_point = _world_point
	overlay.world_scale = _world_scale
	# Refresh here, after the projector is set for THIS frame, rather than letting
	# the overlay's own _process run a frame behind -- that lag is what made the
	# tags/pills lag and jitter while rotating. Its own _process is off in 3D.
	overlay.refresh()


# ── Map: ground + walls as MultiMesh, props as standing sprites ───────────────

func _rebuild_map_if_changed() -> void:
	var tiles := state.tiles
	# The change flags are NOT cleared here -- the projected ground's TileRenderer
	# owns that (its refresh() clears them). Walls just rebuild whenever they're set,
	# which streams them in the same way; the flags are consumed later in the frame.
	if _map_built and not tiles.cleared and tiles.changed_cells.is_empty():
		return
	for child in _map_root.get_children():
		child.queue_free()

	var wall_cells := {}   # texture -> Array[Vector2i]
	var wall_set := {}     # Vector2i -> true, so a face between two walls is culled
	var emitters := content.light_emitters()
	var emitter_cells := {}
	var layers := tiles.layers.keys()
	layers.sort()
	for layer in layers:
		var cells: Dictionary = tiles.layers[layer]
		for cell in cells:
			var tile_id: int = cells[cell]
			if tile_id <= 0:
				continue
			# A glowing tile is indexed for the light scan whatever layer it sits on,
			# independent of whether it is also a wall or a prop.
			var kind: Variant = emitters.get(tile_id)
			if kind != null:
				if not emitter_cells.has(cell):
					emitter_cells[cell] = []
				emitter_cells[cell].append(kind)
			if content.tile_is_wall(tile_id):
				var texture := content.tile_texture(tile_id)
				if not wall_cells.has(texture):
					wall_cells[texture] = []
				wall_cells[texture].append(cell)
				wall_set[cell] = true
			elif layer == COLLISION_LAYER:
				# Every collision-layer tile stands up as a 2.5D billboard.
				_add_prop(cell, tile_id, content.tile_texture(tile_id))
			# Floor tiles are drawn by the projected ground (_build_projected_ground).

	# Each texture's walls become one face-culled chunk mesh: a run of touching
	# walls is a single hollow shell, not a stack of overlapping cubes, so the
	# buried faces (and their overdraw + z-fighting seams) are gone.
	for texture in wall_cells:
		var instance := MeshInstance3D.new()
		instance.mesh = _build_wall_chunk(wall_cells[texture], wall_set)
		instance.material_override = _wall_material_for(texture)
		_map_root.add_child(instance)
	_emitter_cells = emitter_cells
	_map_built = true


func _add_prop(cell: Vector2i, tile_id: int, texture: Texture2D) -> void:
	if texture == null or texture.get_width() <= 0:
		return
	# Honour the tile's render size (tiles.json `size`) so a large decoration stands as
	# big in 3D as it draws in 2D, instead of every prop being clamped to one 32px cell.
	var render := content.tile_render_size(tile_id)
	var height := render * float(texture.get_height()) / float(texture.get_width())
	var sprite := _new_billboard()
	_map_root.add_child(sprite)
	_configure(sprite, texture, Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5),
		height, render, render, false, Color.WHITE)


func _wall_material_for(texture: Texture2D) -> StandardMaterial3D:
	if texture == null:
		return _grey_wall
	if _wall_materials.has(texture):
		return _wall_materials[texture]
	var material := StandardMaterial3D.new()
	_apply_atlas(material, texture)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Lit, so lights fall on the wall faces; the mesh carries generated normals.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# The cube's faces are drawn from one side each; two-sided keeps a face lit
	# even when the orbit looks at its back.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wall_materials[texture] = material
	return material


## One mesh for all of a texture's walls, keeping only the faces exposed to a
## non-wall neighbour (plus every top). A face buried between two adjacent walls
## is never seen, so dropping it removes that overdraw and the seam the
## overlapping cubes used to show. UVs split the 8x16 art the way the sprite is
## authored: top face v 0..0.5, the four sides v 0.5..1; the material's atlas
## offset/scale then maps that onto the tile's region.
func _build_wall_chunk(cells: Array, wall_set: Dictionary) -> ArrayMesh:
	var h := TILE * 0.5
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		var c := Vector3(cell.x * TILE + TILE * 0.5, WALL_HEIGHT * 0.5, cell.y * TILE + TILE * 0.5)
		# Top always shows.
		_wall_quad(builder, c + Vector3(-h, h, -h), c + Vector3(h, h, -h), c + Vector3(h, h, h), c + Vector3(-h, h, h), 0.0, 0.5)
		# Each side only when the neighbour in that direction isn't a wall.
		if not wall_set.has(Vector2i(cell.x, cell.y + 1)):
			_wall_quad(builder, c + Vector3(-h, h, h), c + Vector3(h, h, h), c + Vector3(h, -h, h), c + Vector3(-h, -h, h), 0.5, 1.0)
		if not wall_set.has(Vector2i(cell.x, cell.y - 1)):
			_wall_quad(builder, c + Vector3(h, h, -h), c + Vector3(-h, h, -h), c + Vector3(-h, -h, -h), c + Vector3(h, -h, -h), 0.5, 1.0)
		if not wall_set.has(Vector2i(cell.x + 1, cell.y)):
			_wall_quad(builder, c + Vector3(h, h, h), c + Vector3(h, h, -h), c + Vector3(h, -h, -h), c + Vector3(h, -h, h), 0.5, 1.0)
		if not wall_set.has(Vector2i(cell.x - 1, cell.y)):
			_wall_quad(builder, c + Vector3(-h, h, -h), c + Vector3(-h, h, h), c + Vector3(-h, -h, h), c + Vector3(-h, -h, -h), 0.5, 1.0)
	builder.generate_normals()
	return builder.commit()


## A quad (top-left, top-right, bottom-right, bottom-left) with u across 0..1 and
## v spanning the given band of the sprite.
func _wall_quad(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		v_top: float, v_bottom: float) -> void:
	builder.set_uv(Vector2(0.0, v_top)); builder.add_vertex(a)
	builder.set_uv(Vector2(1.0, v_top)); builder.add_vertex(b)
	builder.set_uv(Vector2(1.0, v_bottom)); builder.add_vertex(c)
	builder.set_uv(Vector2(0.0, v_top)); builder.add_vertex(a)
	builder.set_uv(Vector2(1.0, v_bottom)); builder.add_vertex(c)
	builder.set_uv(Vector2(0.0, v_bottom)); builder.add_vertex(d)


## A 3D material samples the whole atlas at UV 0..1 -- unlike Sprite2D/3D it
## ignores an AtlasTexture's region -- so the region becomes a uv1 offset/scale
## and the full sheet is bound underneath, so only the one clipped sprite shows.
func _apply_atlas(material: StandardMaterial3D, texture: Texture2D) -> void:
	if texture is AtlasTexture:
		var atlas: AtlasTexture = texture
		var sheet := atlas.atlas
		var size := sheet.get_size() if sheet != null else Vector2.ZERO
		material.albedo_texture = sheet
		if size.x > 0.0 and size.y > 0.0:
			material.uv1_offset = Vector3(atlas.region.position.x / size.x,
				atlas.region.position.y / size.y, 0.0)
			material.uv1_scale = Vector3(atlas.region.size.x / size.x,
				atlas.region.size.y / size.y, 1.0)
	else:
		material.albedo_texture = texture


# ── Standing sprites: entities and props ──────────────────────────────────────

func _place_entities(centre: Vector2) -> int:
	var view := Rect2(centre - Vector2(ENTITY_RANGE, ENTITY_RANGE),
		Vector2(ENTITY_RANGE, ENTITY_RANGE) * 2.0)
	var used := 0
	var hide_self := _camera_distance < HIDE_SELF_DISTANCE
	for item in _entity_queue.build(state, content, view):
		if hide_self and item.get("local", false):
			continue
		var texture: Texture2D = item.get("texture")
		if texture == null or texture.get_height() <= 0:
			continue
		var pos: Vector2 = item["pos"]
		var size := float(item["size"])
		var draw: Vector2 = item["draw"]
		used = _place(used, texture, Vector2(pos.x + size * 0.5, pos.y + size * 0.5),
			draw.y, draw.x, size, bool(item["flip"]), item.get("modulate", Color.WHITE),
			item.get("rotation", NAN))
	return used


func _place(index: int, texture: Texture2D, xz: Vector2, height: float, width: float,
		cell: float, flip: bool, modulate: Color, heading: float) -> int:
	while _entities.size() <= index:
		var made := _new_billboard()
		_sprite_root.add_child(made)
		_entities.append(made)
	_configure(_entities[index], texture, xz, height, width, cell, flip, modulate, heading)
	return index + 1


## A standing sprite (full billboard) with a ground shadow (child 0).
func _new_billboard() -> Sprite3D:
	var sprite := _sprite_node(BaseMaterial3D.BILLBOARD_ENABLED)
	sprite.add_child(_new_shadow())
	return sprite


## The pivot is pinned to the body's ground point -- which is exactly the
## camera's target -- so animation frames of different sizes never move it and
## jitter the sprite (the earlier per-frame position shift is what caused the
## jitter). The art is placed WITHIN the sprite by `offset`, not by moving the
## node: bottom-anchored so the feet sit on the ground, and side-anchored so a
## wide attack frame's overhang falls on the facing side.
## A `heading` (the flat view's rotation; NAN for none) instead turns a body to face
## its travel (data.rotateToMotion -- chain bosses, wyrms).
func _configure(sprite: Sprite3D, texture: Texture2D, xz: Vector2, height: float,
		width: float, cell: float, flip: bool, modulate: Color, heading := NAN) -> void:
	var tex_h := float(texture.get_height())
	var tex_w := float(texture.get_width())
	sprite.texture = texture
	sprite.pixel_size = height / tex_h if tex_h > 0.0 else 1.0
	sprite.flip_h = flip
	sprite.modulate = modulate
	sprite.visible = true
	var shadow: Sprite3D = sprite.get_child(0)
	shadow.pixel_size = width / float(SHADOW_SIZE)
	shadow.scale = Vector3.ONE
	# Cast along the sun's ground direction, so the shadow falls to the lit-away side
	# and shows even from behind the sprite.
	var cast := _shadow_ground_dir * height * SHADOW_CAST_FACTOR
	var flat_shadow := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(cast.x, 0.15, cast.y))
	if is_nan(heading):
		if sprite.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.transform = Transform3D(Basis(), Vector3(xz.x, 0.0, xz.y))
		# Body pixels within the frame; the overhang is the rest, on the facing side.
		var body_px := tex_w * cell / width if width > 0.0 else tex_w
		var side := (tex_w - body_px) * 0.5
		sprite.offset = Vector2(-side if flip else side, tex_h * 0.5)
		# Billboarding is render-only, so the node's local axes are world axes.
		shadow.transform = flat_shadow
		return
	# Face the camera, turned about the frame's centre so the art's right edge points
	# where the heading's world direction lands on screen -- the flat view's turn.
	if sprite.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var view := _camera.global_transform.basis
	var along := view.transposed() * Vector3(cos(heading), 0.0, sin(heading))
	var basis := view * Basis(Vector3.BACK, -atan2(-along.y, along.x))
	sprite.offset = Vector2.ZERO
	sprite.transform = Transform3D(basis, Vector3(xz.x, height * 0.5, xz.y))
	# The node turns now, so the shadow undoes that to lie flat where it would.
	flat_shadow.origin.y -= height * 0.5
	shadow.transform = Transform3D(basis.inverse(), Vector3.ZERO) * flat_shadow


# ── Projectiles: flat on the ground, turned to their heading ──────────────────

func _place_projectiles(centre: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var used := 0
	var visibility := BulletVisibility.of(state)
	for bullet: Projectile in state.projectiles.bullets.values():
		if visibility.hides(bullet):
			continue
		var group_id := bullet.group_id
		var texture := content.projectile_texture(group_id)
		if texture == null or texture.get_height() <= 0:
			continue
		var size := maxf(float(bullet.size), 4.0)
		var mid := bullet.pos + Vector2(size, size) * 0.5
		var angle := bullet.angle
		var offset := content.projectiles_art.angle_offset(group_id)
		var spin := content.projectiles_art.spin(group_id)
		var turn := ProjectileArt.spun(spin, now)
		var additive: bool = spin.is_empty() or spin["additive"]
		var heading := BulletRenderer.rotation_for(angle, offset, turn, additive)
		var length := bullet.length
		if length > 0.0 and ProjectileKind.has_flag(bullet, ProjectileKind.LINE_SEGMENT):
			# A wall tile points ALONG the line -- no PI/2 (that term aligns a
			# TRAVELLING bullet to its heading), exactly as the 2D _draw_wall does.
			# Reusing `heading` here turned every tile 90 degrees into a row of dashes.
			var tile_heading := -angle + offset + turn
			var axis := Vector2(cos(angle), -sin(angle))
			var half := length * 0.5
			var steps := maxi(1, int(round(length / size)))
			for s in steps + 1:
				var point := mid + axis * (-half + float(s) / float(steps) * length)
				used = _emit_projectile(used, texture, point, size, tile_heading, angle)
		elif mid.distance_to(centre) <= ENTITY_RANGE:
			used = _emit_projectile(used, texture, mid, size, heading, angle)
	for i in range(used, _projectiles.size()):
		_projectiles[i].visible = false
		_projectile_shadows[i].visible = false


func _emit_projectile(index: int, texture: Texture2D, xz: Vector2, size: float, heading: float,
		travel: float) -> int:
	while _projectiles.size() <= index:
		var made := _sprite_node(BaseMaterial3D.BILLBOARD_DISABLED)
		_sprite_root.add_child(made)
		_projectiles.append(made)
		var shade := _new_shadow()
		_sprite_root.add_child(shade)
		_projectile_shadows.append(shade)
	var tex_h := float(texture.get_height())
	var sprite := _projectiles[index]
	sprite.texture = texture
	sprite.pixel_size = size / tex_h if tex_h > 0.0 else 1.0
	sprite.modulate = Color.WHITE
	var basis: Basis
	if _bullets_upright:
		# Face the camera, turned so the art keeps the angle it has to its travel
		# in the flat view (where the travel's screen angle is -travel).
		var view := _camera.global_transform.basis
		var along := view.transposed() * Vector3(cos(travel), 0.0, -sin(travel))
		var screen_travel := atan2(-along.y, along.x)
		basis = view * Basis(Vector3.BACK, -(heading + travel + screen_travel))
	else:
		# Lay flat, then turn about the vertical to the heading. The 2D rotation is a
		# screen angle, so its sign flips for the 3D Z axis.
		basis = Basis(Vector3.UP, -heading) * Basis(Vector3.RIGHT, -PI * 0.5)
	sprite.transform = Transform3D(basis, Vector3(xz.x, BULLET_HEIGHT, xz.y))
	sprite.visible = true
	var shadow := _projectile_shadows[index]
	shadow.pixel_size = size / float(SHADOW_SIZE)
	shadow.position = Vector3(xz.x, 0.2, xz.y)
	shadow.visible = true
	return index + 1


# ── Ability effects: the 2D renderer, projected on the ground ─────────────────

func _build_effect_ground() -> void:
	_fx_viewport = SubViewport.new()
	_fx_viewport.size = Vector2i(_fx_px, _fx_px)
	_fx_viewport.transparent_bg = true
	# MSAA anti-aliases the effect renderer's vector shapes (arcs, rings, slashes) so
	# their edges read smooth instead of the jagged staircase a bare target gave -- the
	# main reason the cast animations looked coarse projected onto the 3D ground.
	_fx_viewport.msaa_2d = Viewport.MSAA_2X if OS.has_feature("web") else Viewport.MSAA_4X
	_fx_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_fx_viewport)
	_fx_camera = Camera2D.new()
	_fx_camera.zoom = Vector2(float(_fx_px) / FX_REGION, float(_fx_px) / FX_REGION)
	_fx_viewport.add_child(_fx_camera)
	_fx_renderer = EffectRenderer.new()
	_fx_renderer.state = state
	_fx_viewport.add_child(_fx_renderer)

	_fx_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FX_REGION, FX_REGION)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _fx_viewport.get_texture()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Plain linear, no mipmaps: the ground is viewed at a grazing angle, and the
	# default mipmapped filter drops to blurry, shimmering low mip levels there --
	# that was the grain. Linear keeps the anti-aliased vector effects smooth.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	plane.material = material
	_fx_ground.mesh = plane
	add_child(_fx_ground)


func _update_effects(centre: Vector2) -> void:
	# The 16 MB ground viewport is re-rendered only while there is something to show;
	# most frames have no ground effect, so this skips the whole pass then.
	var abilities := state.abilities
	var has_fx := not (abilities.effects.is_empty() and abilities.rings.is_empty()
		and abilities.casts.is_empty())
	if has_fx:
		_fx_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_fx_camera.position = centre
		_fx_ground.position = Vector3(centre.x, 1.5, centre.y)
		_fx_renderer.queue_redraw()
	elif _fx_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		# Effects just ended: one last (empty) render clears the ground, then stop.
		_fx_renderer.queue_redraw()
		_fx_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# ── Ground: the 2D TileRenderer (feather-blended) projected onto the floor ─────

## The whole ground is the real 2D tile renderer -- base tiles plus the feather
## blend pass -- drawn top-down into a SubViewport and mapped onto the floor plane,
## so 3D gets the exact soft tile seams the 2D client has, lit by the omnis/sun.
func _build_projected_ground() -> void:
	_ground_viewport = SubViewport.new()
	_ground_viewport.size = Vector2i(_ground_px, _ground_px)
	_ground_viewport.transparent_bg = true
	# Static ground: re-rendered manually on move/map-change, not every frame.
	_ground_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_ground_viewport)
	_ground_camera = Camera2D.new()
	_ground_camera.zoom = Vector2(float(_ground_px) / GROUND_REGION,
		float(_ground_px) / GROUND_REGION)
	_ground_viewport.add_child(_ground_camera)
	# The TileRenderer culls via ViewRect.of -> the SubViewport's current camera.
	_ground_renderer = TileRenderer.new()
	_ground_renderer.state = state
	_ground_renderer.content = content
	# Only the terrain -- props and walls are the 3D view's own billboards/boxes, so
	# painting them flat here too would double every sprite (flat + standing).
	_ground_renderer.ground_only = true
	_ground_renderer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground_viewport.add_child(_ground_renderer)

	_ground_plane = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_REGION, GROUND_REGION)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _ground_viewport.get_texture()
	# Lit like the old floor so the omnis/sun pool on it; nearest keeps pixel-art
	# crisp; scissor so void cells discard and the sun's wall shadows land on it.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	plane.material = material
	_ground_plane.mesh = plane
	_ground_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground_plane)


## refresh() runs every frame -- it updates the chunk cache and, crucially, owns
## clearing tiles.cleared/changed_cells (the wall rebuild reads them earlier in the
## frame). The viewport is only re-rasterised when the player crosses
## GROUND_MOVE_STEP, the tiles changed, or the cache queued chunks -- it paints a
## view a few chunks a frame, and a chunk only draws when the viewport renders.
func _update_projected_ground(centre: Vector2) -> void:
	var moved := _ground_centre.distance_to(centre) >= GROUND_MOVE_STEP
	var dirty := state.tiles.cleared or not state.tiles.changed_cells.is_empty()
	if moved:
		_ground_centre = centre
		_ground_camera.position = centre
		_ground_plane.position = Vector3(centre.x, 0.0, centre.y)
	_ground_renderer.refresh()
	var queued := _ground_renderer.chunks.queued
	if queued != _ground_queued:
		_ground_queued = queued
		dirty = true
	if moved or dirty:
		_ground_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# ── Dynamic lighting: an omni per glowing tile, plus one on the player ─────────

func _build_lights() -> void:
	for i in _max_lights:
		var light := OmniLight3D.new()
		light.shadow_enabled = false
		light.visible = false
		_lights.append(light)
		add_child(light)
	for i in MAX_BULLET_LIGHTS_3D:
		var light := OmniLight3D.new()
		light.light_color = BULLET_LIGHT_COLOR
		light.light_energy = BULLET_LIGHT_ENERGY * _glow_mul
		light.omni_range = BULLET_LIGHT_RANGE
		light.visible = false
		_bullet_lights.append(light)
		add_child(light)
	for i in MAX_ENEMY_LIGHTS_3D:
		var light := OmniLight3D.new()
		light.visible = false
		_enemy_lights.append(light)
		add_child(light)


func _update_lighting(delta: float, centre: Vector2) -> void:
	var on := state.settings.is_on("lighting")
	var dark := on and _in_dungeon()
	if not _lit_applied or on != _lit or dark != _dark:
		_lit = on
		_dark = dark
		_lit_applied = true
		_apply_lighting(on, dark)
	if not on:
		return
	_light_time += delta
	if _light_frames % LIGHT_SCAN_EVERY == 0:
		_place_lights(centre)
	_light_frames += 1
	_place_bullet_lights(centre)
	_place_enemy_lights(centre)
	for i in _lights.size():
		var light := _lights[i]
		if light.visible and light.get_meta("flickers", false):
			light.light_energy = _torch_energy \
				* (1.0 + 0.12 * sin(_light_time * 9.0 + i * 1.7) + 0.06 * sin(_light_time * 23.0 + i))


## The sprite fill: from the camera, scaled by how far the view faces into the sun.
func _update_fill() -> void:
	var view := -_camera.global_transform.basis.z
	var sun := -_sun.global_transform.basis.z
	var into_sun := -Vector2(view.x, view.z).normalized().dot(Vector2(sun.x, sun.z).normalized())
	_fill.global_transform.basis = _camera.global_transform.basis
	_fill.light_energy = _sun.light_energy * FILL_MATCH * clampf(into_sun, 0.0, 1.0)


## A world point `height` over the ground, through the camera exactly; null behind it.
func _world_point(world: Vector2, height: float) -> Variant:
	var point := Vector3(world.x, height, world.y)
	if _camera.is_position_behind(point):
		return null
	return _camera.unproject_position(point)


## Screen pixels per world unit at a point, across the view.
func _world_scale(world: Vector2, height: float) -> float:
	var point := Vector3(world.x, height, world.y)
	var across := _camera.global_transform.basis.x * float(TILE)
	return _camera.unproject_position(point).distance_to(_camera.unproject_position(point + across)) / float(TILE)


## Dark ambient and a low sun when lit; the old full-bright albedo when off. Both
## drop to OVERWORLD_DIM in the hub/overworld and further to DUNGEON_DIM inside a
## dungeon, so torch and candle pools carry contrast in either.
func _apply_lighting(on: bool, dark: bool) -> void:
	var dim := DUNGEON_DIM if dark else OVERWORLD_DIM
	_env.ambient_light_color = AMBIENT_LIT if on else Color.WHITE
	_env.ambient_light_energy = (AMBIENT_LIT_ENERGY * dim) if on else 1.0
	_sun.light_energy = (SUN_LIT_ENERGY * dim) if on else 0.0
	if not on:
		for light in _lights:
			light.visible = false
		for light in _bullet_lights:
			light.visible = false
		for light in _enemy_lights:
			light.visible = false


## In an assembled dungeon that isn't the personal vault -- where lighting dims.
func _in_dungeon() -> bool:
	return state.tiles.dungeon_id >= 0 and not content.maps.is_vault(state.tiles.map_id)


## The glowing tiles near the player, nearest first, one omni each.
func _place_lights(centre: Vector2) -> void:
	var previously_lit := _lit_cells
	_lit_cells = {}
	var tile := float(TILE)
	var reach := ceili(_light_range / tile)
	var origin := Vector2i(floori(centre.x / tile), floori(centre.y / tile))
	var found := []
	# Only the indexed emitter cells, filtered to the same square reach the grid
	# sweep used -- the candidate set is identical, the walk is over a handful of
	# cells instead of (2*reach+1)^2 x layers dictionary probes every scan.
	for cell in _emitter_cells:
		if absi(cell.x - origin.x) > reach or absi(cell.y - origin.y) > reach:
			continue
		var at := Vector2(cell.x + 0.5, cell.y + 0.5) * tile
		var d := at.distance_squared_to(centre)
		if previously_lit.has(cell):
			d -= LIGHT_HYSTERESIS_SQ
		for kind in _emitter_cells[cell]:
			found.append([d, at, kind, cell])
	found.sort_custom(_nearer)
	for i in _lights.size():
		var light := _lights[i]
		light.visible = i < found.size()
		if light.visible:
			var kind: Dictionary = found[i][2]
			var at: Vector2 = found[i][1]
			_lit_cells[found[i][3]] = true
			light.position = Vector3(at.x, LIGHT_HEIGHT, at.y)
			light.light_color = kind["color"]
			light.omni_range = float(kind["radius"]) * tile * LIGHT_REACH_MUL
			light.set_meta("flickers", kind["flickers"])
			light.light_energy = _torch_energy


## The nearest wand/staff/tome bullets in flight, one travelling omni each.
func _place_bullet_lights(centre: Vector2) -> void:
	var found := []
	var visibility := BulletVisibility.of(state)
	for bullet: Projectile in state.projectiles.bullets.values():
		# A bullet we don't draw casts no glow either (parity with the 2D path).
		if visibility.hides(bullet):
			continue
		# Resolved once per group (colour hex parsed there), not per bullet per frame.
		var light_def := content.projectile_light_resolved(bullet.group_id)
		if light_def.is_empty():
			continue
		var size := maxf(float(bullet.size), 4.0)
		var mid := bullet.pos + Vector2(size, size) * 0.5
		if mid.distance_to(centre) > ENTITY_RANGE:
			continue
		found.append([mid.distance_squared_to(centre), mid, light_def["color"], light_def["radius"]])
	found.sort_custom(_nearer)
	for i in _bullet_lights.size():
		var light := _bullet_lights[i]
		light.visible = i < found.size()
		if light.visible:
			var mid: Vector2 = found[i][1]
			light.position = Vector3(mid.x, BULLET_HEIGHT, mid.y)
			light.light_color = found[i][2]
			light.omni_range = float(found[i][3]) * float(TILE) * LIGHT_REACH_MUL


## The glowing enemies in range, one omni each (in roster order; few enemies glow).
func _place_enemy_lights(centre: Vector2) -> void:
	var shown := 0
	for id in state.entities.enemies:
		if shown >= _enemy_lights.size():
			break
		var enemy: Dictionary = state.entities.enemies[id]
		var light_def := content.enemy_light_resolved(int(enemy.get("enemy_id", -1)))
		if light_def.is_empty():
			continue
		var size := float(enemy.get("size", 16))
		var at: Vector2 = state.entities.render_position(enemy) + Vector2(size, size) * 0.5
		if at.distance_to(centre) > ENTITY_RANGE:
			continue
		var light := _enemy_lights[shown]
		light.visible = true
		light.position = Vector3(at.x, ENEMY_LIGHT_HEIGHT, at.y)
		light.light_color = light_def["color"]
		light.omni_range = float(light_def["radius"]) * float(TILE) * LIGHT_REACH_MUL
		var energy := ENEMY_LIGHT_ENERGY * _glow_mul
		if light_def.get("flickers", false):
			energy *= 1.0 + 0.12 * sin(_light_time * 9.0 + shown * 1.7) + 0.06 * sin(_light_time * 23.0 + shown)
		light.light_energy = energy
		shown += 1
	for i in range(shown, _enemy_lights.size()):
		_enemy_lights[i].visible = false


# ── Shared sprite + texture helpers ───────────────────────────────────────────

func _sprite_node(billboard: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.billboard = billboard
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# Standing bodies (billboards) take the light so they darken away from it and
	# warm up by a torch; flat projectiles stay self-bright.
	sprite.shaded = billboard == BaseMaterial3D.BILLBOARD_ENABLED
	if sprite.shaded:
		sprite.layers = 1 | SPRITE_LIGHT_LAYER
	return sprite


func _new_shadow() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _shadow
	sprite.shaded = false
	sprite.modulate = Color(0.0, 0.0, 0.0, 0.5)
	sprite.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	return sprite


## Nearest-first by the squared distance in slot 0. A static func so the two
## per-frame light scans don't each allocate a fresh closure every call.
static func _nearer(a: Array, b: Array) -> bool:
	return a[0] < b[0]


func _make_shadow() -> ImageTexture:
	var image := Image.create(SHADOW_SIZE, SHADOW_SIZE, false, Image.FORMAT_RGBA8)
	var centre := float(SHADOW_SIZE) * 0.5
	for y in SHADOW_SIZE:
		for x in SHADOW_SIZE:
			var distance := Vector2(x + 0.5 - centre, y + 0.5 - centre).length() / centre
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, clampf(1.0 - distance, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
