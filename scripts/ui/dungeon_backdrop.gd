class_name DungeonBackdrop
extends Control

## The scene behind the sign-in panel: a synthetic dungeon assembled from the
## game's own dungeon data the way the server does, rendered through the real
## world renderer and scene lighting, and panned diagonally. Enemies drift in
## their rooms; a LocalPlayer rides the camera so the lighting lights the view.
## Nothing here is interactive.
##
## It renders into a private SubViewport, so it needs neither the main scene's
## camera nor its realm state and drops straight into the login CanvasLayer (and
## the capture harness) in place of the torchlit LoginBackdrop.

## Camera zoom for the backdrop. Lower than the game's WORLD_ZOOM so the sweep
## shows whole rooms rather than a tight gameplay view.
const BACKDROP_ZOOM := 1.35
## World pixels per second the view drifts along its diagonal.
const PAN_SPEED := 34.0
## Seconds to cross-fade when a new dungeon is rolled.
const FADE_SECONDS := 1.1
## How close to the dungeon's edge the camera gets before a fresh dungeon is rolled.
const REROLL_MARGIN := 7.0 * GameConstants.TILE_SIZE
## A rider id the lighting and viewport-freeze gate treat as a present viewer;
## never sent anywhere, so any non-zero value serves.
const RIDER_ID := 777000
const MINIONS_CAP := 6
## Tiles an enemy wanders from where it spawned.
const WANDER_RADIUS := 2.2 * GameConstants.TILE_SIZE
const DRIFT_MIN := 0.4   # px/tick
const DRIFT_MAX := 1.1
const IDLE_CHANCE := 0.35

var game_data: GameData
## Seconds, advanced by step(); drives the entity clock and the scroll so a
## scripted render can run a fixed number of frames deterministically.
var _elapsed_ms := 0.0
## Fixed when set (a capture pins it); 0 rolls a fresh dungeon each time.
var seed_value := 0

var _state: RealmState
var _viewport: SubViewport
var _container: SubViewportContainer
var _world: WorldRenderer
var _lighting: SceneLighting
var _camera: Camera2D
var _pan := Vector2(0.82, 0.57)
var _bounds := Rect2()
var _alpha := 1.0
var _rerolling := false
var _next_enemy_id := 1
var _rng := RandomNumberGenerator.new()
var built := false


static func can_build(content: GameData) -> bool:
	return content != null and content.ready \
		and not content.library.dungeons.is_empty() and not content.library.dungeon_rooms.is_empty()


static func attach(into: Node, content: GameData) -> DungeonBackdrop:
	var backdrop := DungeonBackdrop.new()
	backdrop.game_data = content
	into.add_child(backdrop)
	return backdrop


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)

	# The void cells of the dungeon are transparent, so a near-black fill behind the
	# viewport reads as the unlit depth beyond the rooms.
	var backing := ColorRect.new()
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	backing.color = Color(0.02, 0.02, 0.04)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)

	_container = SubViewportContainer.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_viewport)

	_state = RealmState.new(game_data, func() -> int: return int(_elapsed_ms))
	for key in ["lighting", "bloom", "animated_liquids"]:
		_state.settings.set_on(key, true)
	_state.local.id = RIDER_ID

	_world = WorldRenderer.new()
	_world.setup(_state, game_data)
	_viewport.add_child(_world)
	_lighting = SceneLighting.new()
	_lighting.setup(_state, game_data)
	_viewport.add_child(_lighting)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(BACKDROP_ZOOM, BACKDROP_ZOOM)
	_camera.position_smoothing_enabled = false
	_viewport.add_child(_camera)
	_camera.make_current()

	if is_visible_in_tree():
		build()
	else:
		set_process(false)


func _fit() -> void:
	if not get_parent() is Control:
		size = TouchScale.view_size(self)


## Rebuilds and resumes when shown; drops the dungeon and stops stepping when the
## player is in the game, so nothing renders behind a whole session.
func _notification(what: int) -> void:
	# Only react to show/hide, and not before _ready has stood the viewport and
	# state up (a visibility notification can arrive during add_child, before it).
	if what != NOTIFICATION_VISIBILITY_CHANGED or _state == null:
		return
	var shown := is_visible_in_tree()
	set_process(shown)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if shown:
		build()
	else:
		_state.reset_world()
		built = false


func _process(delta: float) -> void:
	if is_visible_in_tree():
		step(delta)


## Assembles a fresh dungeon into the shared state and seats the camera at its
## entrance. Safe to call repeatedly (a re-roll); a no-op without dungeon data.
func build() -> void:
	if not can_build(game_data):
		built = false
		return
	_rng.seed = seed_value if seed_value != 0 else randi()
	var dungeon := _pick_dungeon()
	var layout := DungeonAssembler.new(dungeon, game_data.library.dungeon_rooms, _rng.randi()).assemble()

	_state.reset_world()
	var tiles := _state.tiles
	tiles.layers = layout["layers"]
	tiles.width = layout["width"]
	tiles.height = layout["height"]
	tiles.map_id = 0
	tiles.realm_id = 1
	tiles.dungeon_id = layout["dungeon_id"]
	tiles.cleared = false
	for layer in tiles.layers.values():
		for cell in layer:
			tiles.changed_cells[cell] = true
	_bounds = _pixel_bounds(tiles, layout["tile_size"])

	_spawn_enemies(layout["placements"], layout["tile_size"])

	_pan = _random_diagonal()
	_camera.position = layout["spawn"]
	_sync_rider()
	_alpha = 1.0
	_container.modulate.a = 1.0
	built = true


## One frame: drift the view and the enemies. Split from _process so a capture
## can advance a fixed number of frames at a fixed delta.
func step(delta: float) -> void:
	_elapsed_ms += delta * 1000.0
	if not built:
		build()
		return
	if _rerolling:
		_alpha = maxf(0.0, _alpha - delta / FADE_SECONDS)
		if _alpha <= 0.0:
			build()
			_rerolling = false
	else:
		_alpha = minf(1.0, _alpha + delta / FADE_SECONDS)
		_camera.position += _pan * PAN_SPEED * delta
		_sync_rider()
		if not _bounds.grow(-REROLL_MARGIN).has_point(_camera.position):
			_rerolling = true
	_container.modulate.a = _alpha
	_drift_enemies(delta)


## Keep the rider centred on the camera so the lighting lights the view and the
## viewport-freeze gate keeps far enemies still.
func _sync_rider() -> void:
	var half := Vector2(_state.local.size, _state.local.size) * 0.5
	_state.local.position = _camera.position - half
	_state.local.previous_position = _state.local.position
	_state.local.tick_alpha = 1.0


func _pick_dungeon() -> Dictionary:
	var choices: Array = []
	for dungeon in game_data.library.dungeons.values():
		if not dungeon.get("roomIds", []).is_empty():
			choices.append(dungeon)
	if choices.is_empty():
		return game_data.library.dungeons.values()[0]
	return choices[_rng.randi_range(0, choices.size() - 1)]


func _random_diagonal() -> Vector2:
	var x := -1.0 if _rng.randf() < 0.5 else 1.0
	var y := -1.0 if _rng.randf() < 0.5 else 1.0
	return Vector2(x * 0.82, y * 0.57)


func _pixel_bounds(tiles: TileMapState, tile_size: int) -> Rect2:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for layer in tiles.layers.values():
		for cell in layer:
			lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
			hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	if hi.x < lo.x:
		return Rect2(Vector2.ZERO, Vector2(tiles.width, tiles.height) * tile_size)
	return Rect2(Vector2(lo) * tile_size, Vector2(hi - lo + Vector2i.ONE) * tile_size)


func _spawn_enemies(placements: Array, tile_size: int) -> void:
	for placement in placements:
		var room: Dictionary = placement["room"]
		var ox: int = placement["ox"]
		var oy: int = placement["oy"]
		var pool: Array = room.get("minionEnemyIds", [])
		var max_minions := int(room.get("maxMinions", 0))
		if not pool.is_empty() and max_minions > 0:
			var lo := int(room.get("minMinions", 0))
			var count := mini(MINIONS_CAP, lo + _rng.randi_range(0, maxi(0, max_minions - lo)))
			for i in count:
				var enemy_id := int(pool[_rng.randi_range(0, pool.size() - 1)])
				var centre := _random_floor(room, ox, oy, tile_size)
				if centre != Vector2.INF:
					_add_enemy(enemy_id, centre)
		for spawn in room.get("staticSpawns", []):
			var centre := Vector2(
				(ox + int(spawn.get("col", 0))) * tile_size + tile_size * 0.5,
				(oy + int(spawn.get("row", 0))) * tile_size + tile_size * 0.5)
			_add_enemy(int(spawn.get("enemyId", -1)), centre)


## A random floor cell centre in the room: base tile present, no wall over it.
func _random_floor(room: Dictionary, ox: int, oy: int, tile_size: int) -> Vector2:
	var w := int(room.get("width", 1))
	var h := int(room.get("height", 1))
	for _attempt in 8:
		var col := ox + _rng.randi_range(1, maxi(1, w - 2))
		var row := oy + _rng.randi_range(1, maxi(1, h - 2))
		var cell := Vector2i(col, row)
		if _state.tiles.layers.get(0, {}).has(cell) and not _state.tiles.layers.get(1, {}).has(cell):
			return Vector2(col * tile_size + tile_size * 0.5, row * tile_size + tile_size * 0.5)
	return Vector2.INF


func _add_enemy(enemy_id: int, centre: Vector2) -> void:
	if enemy_id < 0 or not game_data.enemies.has(enemy_id):
		return
	var size := int(game_data.enemies[enemy_id].get("size", 16))
	var enemy := _state.entities.upsert(_state.entities.enemies, _next_enemy_id, GameConstants.ENTITY_ENEMY)
	_next_enemy_id += 1
	enemy["enemy_id"] = enemy_id
	enemy["size"] = size
	var pos := centre - Vector2(size, size) * 0.5
	enemy["home"] = pos
	enemy["pos"] = pos
	enemy["vel"] = Vector2.ZERO
	enemy["retarget"] = _rng.randf_range(0.0, 2.0)
	EntitySnapshots.push(enemy, pos, Vector2.ZERO, _elapsed_ms, _state.entities.viewer.call())


func _drift_enemies(delta: float) -> void:
	var enemies: Dictionary = _state.entities.enemies
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		if not enemy.has("pos"):
			continue
		enemy["retarget"] -= delta
		if enemy["retarget"] <= 0.0:
			if _rng.randf() < IDLE_CHANCE:
				enemy["vel"] = Vector2.ZERO
			else:
				enemy["vel"] = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(DRIFT_MIN, DRIFT_MAX)
			enemy["retarget"] = _rng.randf_range(0.8, 2.6)
		var pos: Vector2 = enemy["pos"] + enemy["vel"] * GameConstants.TICK_RATE * delta
		if pos.distance_to(enemy["home"]) > WANDER_RADIUS:
			enemy["vel"] = (enemy["home"] - pos).normalized() * DRIFT_MAX
			pos = enemy["home"] + (pos - enemy["home"]).normalized() * WANDER_RADIUS
		enemy["pos"] = pos
		EntitySnapshots.push(enemy, pos, enemy["vel"], _elapsed_ms, _state.entities.viewer.call())
	RemoteAnimation.advance(enemies, delta)
