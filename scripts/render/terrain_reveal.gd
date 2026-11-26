class_name TerrainReveal
extends Node2D

## Fades freshly streamed terrain in instead of letting it pop.
##
## Each cell a LoadMap reveals in view starts covered in the void's black and
## uncovers over DURATION_S. Within one packet the cells uncover outward from
## the player, so a whole realm entry ripples in and a walked strip sweeps in
## from its nearest edge. Drawn over the ground, walls and bodies (an enemy
## standing on new ground arrives with it), under bullets and effects.

const SHADER := preload("res://scripts/render/shaders/terrain_reveal.gdshader")
const TILE_SIZE := GameConstants.TILE_SIZE
const DURATION_S := 0.35
## Extra wait per tile of distance past the packet's nearest cell.
const STAGGER_S := 0.03
const MAX_STAGGER_S := 0.45

var state: RealmState
## Dissolve on the art's pixel grid instead of fading the black.
var dither := false
## Seconds; a capture pins it to freeze the fade.
var clock := func() -> float: return Time.get_ticks_msec() / 1000.0
## Cell -> [start_s, cover]; cover is only cached for the draw.
var _active := {}
var _material := ShaderMaterial.new()
var _was_drawing := false


func _ready() -> void:
	_material.shader = SHADER
	material = _material


## Each frame, from WorldRenderer: takes the cells the last packets revealed.
func refresh() -> void:
	if state == null:
		return
	var tiles := state.tiles
	if tiles.cleared:
		_active.clear()
	var revealed := tiles.revealed_cells
	if not revealed.is_empty():
		if state.settings.is_on("terrain_fade_in"):
			_admit(revealed)
		revealed.clear()
	_material.set_shader_parameter("dither", dither)
	var drawing := not _active.is_empty()
	if drawing or _was_drawing:
		queue_redraw()
	_was_drawing = drawing


func _admit(revealed: Dictionary) -> void:
	var view := ViewRect.of(self)
	var first := Vector2i(floori(view.position.x / TILE_SIZE), floori(view.position.y / TILE_SIZE))
	var last := Vector2i(floori(view.end.x / TILE_SIZE), floori(view.end.y / TILE_SIZE))
	var origin := state.local.position / TILE_SIZE if state.local.is_present() else Vector2(view.get_center() / TILE_SIZE)
	var now: float = clock.call()
	# Cells outside the view scroll in already drawn, so they need no fade.
	var cells: Array[Vector2i] = []
	var nearest := INF
	for cell: Vector2i in revealed:
		if cell.x < first.x or cell.y < first.y or cell.x > last.x or cell.y > last.y:
			continue
		cells.append(cell)
		nearest = minf(nearest, origin.distance_to(Vector2(cell) + Vector2(0.5, 0.5)))
	for cell in cells:
		var distance := origin.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) - nearest
		_active[cell] = [now + minf(distance * STAGGER_S, MAX_STAGGER_S), 1.0]


func _draw() -> void:
	var now: float = clock.call()
	var done: Array[Vector2i] = []
	var size := Vector2(TILE_SIZE, TILE_SIZE)
	for cell: Vector2i in _active:
		var progress := (now - float(_active[cell][0])) / DURATION_S
		if progress >= 1.0:
			done.append(cell)
			continue
		var cover := 1.0 - smoothstep(0.0, 1.0, maxf(progress, 0.0))
		draw_rect(Rect2(Vector2(cell) * TILE_SIZE, size), Color(0, 0, 0, cover))
	for cell in done:
		_active.erase(cell)


func active_count() -> int:
	return _active.size()

