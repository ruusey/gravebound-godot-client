class_name TerrainReveal
extends Node2D

## Dissolves terrain in as walking uncovers it, instead of letting it pop.
##
## Each cell a LoadMap reveals in view starts covered in the void's black,
## which breaks up on the art's pixel grid over DURATION_S. Within one packet
## the cells uncover outward from the player, so a walked strip sweeps in from
## its near edge. Drawn over both map layers, the liquids and the bodies (an
## enemy standing on new ground arrives with it), under bullets and effects.
## A wall's cover runs its full art height, over the face it hangs south.
## SceneLighting dims a revealed tile's light by shown().
##
## Arriving somewhere is never faded. A new map shows at once; so does ground
## landing off screen (it scrolls in drawn); and when the player jumps more than
## TELEPORT_PX in a frame, every cover is lifted and the next ARRIVAL_GRACE_S of
## ground shows at once, since the tiles can land a frame before the position.
##
## With an edge_band, the same dissolve also runs around the view's border: each
## cell within the band is covered by how near the edge it sits, so a panning view
## materializes terrain as it scrolls in and breaks it up as it scrolls out.

const SHADER := preload("res://scripts/render/shaders/terrain_reveal.gdshader")
const TILE_SIZE := GameConstants.TILE_SIZE
const DURATION_S := 0.35
## Extra wait per tile of distance past the packet's nearest cell.
const STAGGER_S := 0.03
const MAX_STAGGER_S := 0.45
## Further than walking covers in one frame at any speed.
const TELEPORT_PX := 3.0 * TILE_SIZE
const ARRIVAL_GRACE_S := 0.3

var state: RealmState
var content: GameData
## Dissolve on the art's pixel grid (true) or fade the black smoothly.
var dither := true
## Tiles in from the view's edge that the border dissolve spans; 0 for none.
var edge_band := 0.0
## Seconds; a capture pins it to freeze the fade.
var clock := func() -> float: return Time.get_ticks_msec() / 1000.0
## Cell -> [start_s, cover_height_px].
var _active := {}
var _material := ShaderMaterial.new()
var _was_drawing := false
var _last_position := Vector2.INF
var _arrived_at := -INF


func _ready() -> void:
	_material.shader = SHADER
	material = _material


## Each frame, from WorldRenderer before the ground (which resets tiles.cleared).
func refresh() -> void:
	if state == null:
		return
	var tiles := state.tiles
	var revealed := tiles.revealed_cells
	var now: float = clock.call()
	# Every frame, not short-circuited by a clear, or the next frame sees a jump.
	var jumped := _jumped()
	if tiles.cleared or jumped:
		_active.clear()
		_arrived_at = now
	if not revealed.is_empty() and now - _arrived_at >= ARRIVAL_GRACE_S \
			and state.settings.is_on("terrain_fade_in"):
		_admit(revealed, now)
	revealed.clear()
	_material.set_shader_parameter("dither", dither)
	var drawing := not _active.is_empty() or edge_band > 0.0
	if drawing or _was_drawing:
		queue_redraw()
	_was_drawing = drawing


func is_fading() -> bool:
	return not _active.is_empty() or edge_band > 0.0


## How much of `cell` shows, 0 (covered) to 1.
func shown(cell: Vector2i) -> float:
	var cover := _edge_cover(cell, ViewRect.of(self)) if edge_band > 0.0 else 0.0
	var entry: Variant = _active.get(cell)
	if entry != null:
		cover = maxf(cover, _cover(entry[0], clock.call()))
	return 1.0 - cover


func active_count() -> int:
	return _active.size()


func _jumped() -> bool:
	if not state.local.is_present():
		_last_position = Vector2.INF
		return false
	var here := state.local.position
	var jumped := _last_position != Vector2.INF and here.distance_to(_last_position) > TELEPORT_PX
	_last_position = here
	return jumped


func _admit(revealed: Dictionary, now: float) -> void:
	var view := ViewRect.of(self)
	var first := Vector2i(floori(view.position.x / TILE_SIZE), floori(view.position.y / TILE_SIZE))
	var last := Vector2i(floori(view.end.x / TILE_SIZE), floori(view.end.y / TILE_SIZE))
	var origin := state.local.position / TILE_SIZE if state.local.is_present() \
		else view.get_center() / TILE_SIZE
	var cells: Array[Vector2i] = []
	var nearest := INF
	for cell: Vector2i in revealed:
		if cell.x < first.x or cell.y < first.y or cell.x > last.x or cell.y > last.y:
			continue
		cells.append(cell)
		nearest = minf(nearest, origin.distance_to(Vector2(cell) + Vector2(0.5, 0.5)))
	for cell in cells:
		var distance := origin.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) - nearest
		_active[cell] = [now + minf(distance * STAGGER_S, MAX_STAGGER_S), _cover_height(cell)]


## The tallest art drawn from `cell` on any layer: a wall's face hangs south of it.
func _cover_height(cell: Vector2i) -> float:
	var height := float(TILE_SIZE)
	if content == null:
		return height
	for layer in state.tiles.layers:
		var tile_id := int(state.tiles.layers[layer].get(cell, 0))
		if tile_id != 0:
			height = maxf(height, content.tile_render_height(tile_id))
	return height


## How covered `cell` is by the border dissolve: fully at the view's edge, not at
## all edge_band tiles in.
func _edge_cover(cell: Vector2i, view: Rect2) -> float:
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * TILE_SIZE
	var inset := minf(minf(centre.x - view.position.x, view.end.x - centre.x),
		minf(centre.y - view.position.y, view.end.y - centre.y)) / TILE_SIZE
	return 1.0 - smoothstep(0.0, 1.0, clampf(inset / edge_band, 0.0, 1.0))


static func _cover(start: float, now: float) -> float:
	var progress := (now - start) / DURATION_S
	return 1.0 - smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))


func _draw() -> void:
	var now: float = clock.call()
	var border := _border_covers()
	var done: Array[Vector2i] = []
	for cell: Vector2i in _active:
		var entry: Array = _active[cell]
		var cover := _cover(entry[0], now)
		if cover <= 0.0:
			done.append(cell)
			continue
		cover = maxf(cover, border.get(cell, 0.0))
		border.erase(cell)
		draw_rect(Rect2(Vector2(cell) * TILE_SIZE, Vector2(TILE_SIZE, entry[1])), Color(0, 0, 0, cover))
	for cell in done:
		_active.erase(cell)
	for cell: Vector2i in border:
		draw_rect(Rect2(Vector2(cell) * TILE_SIZE, Vector2(TILE_SIZE, _cover_height(cell))),
			Color(0, 0, 0, border[cell]))


## Cell -> cover for every drawn cell inside the border band (and just past the
## edge, so a wall face hanging into view is covered too).
func _border_covers() -> Dictionary:
	var covers := {}
	if edge_band <= 0.0 or state == null:
		return covers
	var view := ViewRect.of(self)
	var first := Vector2i(floori(view.position.x / TILE_SIZE) - 1, floori(view.position.y / TILE_SIZE) - 3)
	var last := Vector2i(floori(view.end.x / TILE_SIZE) + 1, floori(view.end.y / TILE_SIZE) + 1)
	var layers: Dictionary = state.tiles.layers
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var cell := Vector2i(x, y)
			var cover := _edge_cover(cell, view)
			if cover <= 0.0:
				continue
			for layer in layers.values():
				if layer.has(cell):
					covers[cell] = cover
					break
	return covers
