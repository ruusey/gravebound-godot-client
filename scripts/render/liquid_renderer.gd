class_name LiquidRenderer
extends TileRenderer

## Water and lava in their own chunk-cached layer, animated entirely by a shader.
##
## A subclass of TileRenderer so it inherits the ground's chunk caching and camera
## culling -- the cells are drawn ONCE and kept, and the GPU animates them from TIME
## (see liquid.gdshader), so an ocean or a lava lake shimmers and flows with no
## per-frame CPU redraw. It paints only the base-layer tiles the ground skips
## (GameData.tile_is_liquid), sits UNDER the ground layer, and the ground leaves
## those cells transparent -- so a prop or wall standing on a liquid cell still
## draws over it.

const LIQUID_SHADER := preload("res://scripts/render/shaders/liquid.gdshader")
## The neighbours whose land makes a shore, in liquid.gdshader's bit order:
## sides north, south, west, east, then corners north-west, north-east,
## south-west, south-east.
const SIDES := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const CORNERS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
## SIDES and CORNERS as [dy0..dy3, dx0..dx3], for stepping through paint_cells' grid.
const SIDE_STEPS := [-1, 1, 0, 0, 0, 0, -1, 1]
const CORNER_STEPS := [-1, -1, 1, 1, -1, 1, -1, 1]
const LAND := 1
const LIQUID := 2

## A shoreless liquid cell (no land neighbours, or any lava cell). The shader's shore
## branch is gated on the red/green mask, which is zero here, so blue/alpha are free --
## alpha carries the water(0)/lava(1) flag that drives the animation from data.liquid.
const NO_SHORE_WATER := Color(0.0, 0.0, 1.0, 0.0)
const NO_SHORE_LAVA := Color(0.0, 0.0, 1.0, 1.0)
## Two lips further apart than this (RGB, 0-1) are different ground.
const MIXED_LIPS := 0.12

## [content, map id, dungeon id] the chunks were built for; a change drops them.
var _liquid_key := []
## land id * 65536 + liquid id -> _lip()
var _lips := {}
## liquid id -> whether it is lava, which keeps its plain edge: shores are water's.
var _lava := {}


func _init() -> void:
	var shaded := ShaderMaterial.new()
	shaded.shader = LIQUID_SHADER
	material = shaded


## Chunk bookkeeping keyed to the map, kept separate from the ground's so it never
## races it over state.tiles.changed_cells (which the ground clears). Call this
## BEFORE the ground's refresh each frame, while changed_cells is still populated.
func refresh() -> void:
	if state == null or content == null:
		return
	var tiles := state.tiles
	var key := [content, tiles.map_id, tiles.dungeon_id]
	if tiles.cleared or _liquid_key != key:
		chunks.drop_all()
		_lips.clear()
		_lava.clear()
		_liquid_key = key
	if not tiles.changed_cells.is_empty():
		chunks.mark(tiles.changed_cells)   # mark only; the ground layer clears them
	chunks.update(self, ViewRect.of(self))


## Only the base-layer water/lava tiles; the ground draws everything else.
func paint_cells(canvas: CanvasItem, own: Rect2i) -> Dictionary:
	if state == null or content == null:
		return {}
	var tiles := state.tiles
	var first := own.position - Vector2i.ONE
	var last := own.end
	var base: Dictionary = tiles.layers.get(BASE_LAYER, {})
	var looks: Dictionary = content.tile_looks
	# Every cell drawn and the ring round them, sorted once into land, liquid or
	# nothing: each liquid cell then reads its eight neighbours from here.
	var origin := first - Vector2i.ONE
	var width := last.x - first.x + 3
	var kinds := PackedByteArray()
	kinds.resize(width * (last.y - first.y + 3))
	for x in range(origin.x, last.x + 2):
		for y in range(origin.y, last.y + 2):
			var tile_id: int = base.get(Vector2i(x, y), VOID_TILE)
			if tile_id <= VOID_TILE:
				continue
			var look: Array = looks.get(tile_id, GameData.NO_LOOK)
			if look.is_empty():
				look = content.tile_look(tile_id)
			kinds[(y - origin.y) * width + x - origin.x] = LIQUID if look[GameData.LOOK_FLAGS] & GameData.LOOK_LIQUID else LAND
	var drawn := 0
	for tile_x in range(first.x, last.x + 1):
		for tile_y in range(first.y, last.y + 1):
			var at := (tile_y - origin.y) * width + tile_x - origin.x
			if kinds[at] != LIQUID:
				continue
			var cell := Vector2i(tile_x, tile_y)
			var tile_id: int = base[cell]
			var texture := content.tile_texture(tile_id)
			var rect := Rect2(tile_x * TILE_SIZE, tile_y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			if texture == null:
				_draw_tile(canvas, content, tile_id, rect)
			else:
				var sides := 0
				var corners := 0
				for i in 4:
					if kinds[at + SIDE_STEPS[i] * width + SIDE_STEPS[i + 4]] == LAND:
						sides |= 1 << i
					if kinds[at + CORNER_STEPS[i] * width + CORNER_STEPS[i + 4]] == LAND:
						corners |= 1 << i
				# Lava never gets a shore (its edge stays plain); a shoreless water cell
				# carries the water flag; otherwise water builds its shore band.
				var shore: Color
				if _is_lava(tile_id):
					shore = NO_SHORE_LAVA
				elif sides == 0 and corners == 0:
					shore = NO_SHORE_WATER
				else:
					shore = _shore(base, cell, tile_id, sides, corners)
				canvas.draw_texture_rect(texture, rect, false, shore)
			if GroundChunk.counts(own, tile_x, tile_y):
				drawn += 1
	return {"tiles": drawn}


## A shore cell's land sides and corners, and the colour of the ground's lip
## where it pokes into the liquid, packed for the shader: the masks in red and
## green, the lip as RGB565 split over blue and alpha. A cell between two kinds of
## ground gets no lip (blue zero): one colour would be wrong on one of its sides.
func _shore(base: Dictionary, cell: Vector2i, liquid_id: int, sides: int, corners: int) -> Color:
	var land := VOID_TILE
	var mixed := false
	for i in 8:
		if ((sides if i < 4 else corners) & (1 << (i & 3))) == 0:
			continue
		var tile_id: int = base[cell + (SIDES[i] if i < 4 else CORNERS[i - 4])]
		if land == VOID_TILE:
			land = tile_id
		elif tile_id != land and not mixed:
			mixed = _distance(_lip(tile_id, liquid_id), _lip(land, liquid_id)) > MIXED_LIPS
	if mixed:
		return Color(sides / 15.0, corners / 15.0, 0.0, 1.0)
	var lip := _lip(land, liquid_id)
	var red := maxi(roundi(lip.r * 31.0), 1)
	var green := roundi(lip.g * 63.0)
	var blue := roundi(lip.b * 31.0)
	return Color(sides / 15.0, corners / 15.0, ((red << 3) | (green >> 3)) / 255.0,
		(((green & 7) << 5) | blue) / 255.0)


static func _distance(one: Color, two: Color) -> float:
	return Vector3(one.r - two.r, one.g - two.g, one.b - two.b).length()


## The ground at the water's edge as the land's shore band leaves it, wet.
func _lip(land: int, liquid_id: int) -> Color:
	var key := land * 65536 + liquid_id
	if _lips.has(key):
		return _lips[key]
	var ground: Variant = feathers.blending.signature(content, land)
	var liquid: Variant = feathers.blending.signature(content, liquid_id)
	var ground_colour: Color = ground if ground != null else Color(0.4, 0.4, 0.3)
	var liquid_colour: Color = liquid if liquid != null else Color(0.2, 0.4, 0.8)
	var lip := ground_colour.lerp(liquid_colour * TileFeather.WET_SHADE, TileFeather.WET_ALPHA)
	_lips[key] = lip
	return lip


func _is_lava(liquid_id: int) -> bool:
	if not _lava.has(liquid_id):
		_lava[liquid_id] = content.tile_is_lava(liquid_id)
	return _lava[liquid_id]
