class_name TileRenderer
extends Node2D

## Draws terrain -- once, in GroundChunks it keeps, not every frame.
##
## Its own canvas item, so a shader can be hung on the ground without touching
## the entities standing on it; its chunks use their parent's material.
##
## Tiles are square cells, except walls: their art is twice as tall as it is
## wide and carries its own front face, so it is drawn two cells tall.
##
## Tile id 0 is Void_Tile: "no tile here", not a black square. The overlay
## layer is almost entirely void -- 16109 of 16384 cells in Nexus_Auru_V1 --
## so drawing it blacks out the ground underneath. The web client skips it the
## same way (`if (!tile || tile.base <= 0) continue`).

const TILE_SIZE := GameConstants.TILE_SIZE
## Empty cell. Layers above the ground use it wherever they place nothing.
const VOID_TILE := 0

## The layer the terrain lives on; anything above it is collision and props.
const BASE_LAYER := 0

## Unknown tile ids are warned about once, not once per tile per frame.
var missing_tiles := {}
var feathers := FeatherPass.new()
var shadows := ObjectShadows.new()
var bands := WallBandPass.new()
var strokes := WallStroke.new()
var billboards := BillboardOutlines.new()
## Fringes laid down by the last draw.
var feathers_drawn: int:
	get: return int(stats.get("feathers", 0))


var state: RealmState
var content: GameData
## The 3D view projects this onto its floor and draws props/walls as real 3D
## objects, so in that mode only the base terrain (and its feather blending) is
## painted -- otherwise props/walls would appear twice: flat here and standing.
var ground_only := false
## When the animated LiquidRenderer is active it draws the base-layer water/lava
## tiles itself (over this layer, under the props), so the ground omits them and
## leaves those cells transparent. Toggling it rebuilds the chunks.
var skip_liquids := false
var chunks := GroundChunks.new()
## What the chunks in view put down, over their own cells: "tiles",
## "feathers", "shadows", "bands", "rings", "bottoms".
var stats := {}
var drawn: int:
	get: return int(stats.get("tiles", 0))
var _drawn_for := []   # the content and the band switch the chunks were drawn with


## Each frame, from WorldRenderer: what changed goes to the chunks it
## touches, and the chunks in view are drawn if they need it.
func refresh() -> void:
	if state == null or content == null:
		return
	var tiles := state.tiles
	# A new map or new content: none of it stands. The bands switched: all
	# of it is drawn again.
	if tiles.cleared or _drawn_for.is_empty() or _drawn_for[0] != content:
		chunks.drop_all()
	elif _drawn_for[1] != WallBandPass.enabled or _drawn_for[2] != skip_liquids:
		chunks.mark_all()
	_drawn_for = [content, WallBandPass.enabled, skip_liquids]
	tiles.cleared = false
	if not tiles.changed_cells.is_empty():
		chunks.mark(tiles.changed_cells)
		tiles.changed_cells.clear()
	var view := ViewRect.of(self)
	chunks.update(self, view)
	stats = chunks.stats_over(view)


## One chunk: its cells and the ring around them, in this order, the stats
## counting its own cells only.
func paint_cells(canvas: CanvasItem, own: Rect2i) -> Dictionary:
	if state == null or content == null:
		return {}
	var tiles := state.tiles
	# Two rows north, not one: the ring's floor is painted over whatever the chunk
	# above put there, so a wall two rows up must be drawn again here or its front
	# face, which spills into the ring row, is covered.
	var first := own.position - Vector2i(1, 2)
	var last := own.end
	var drawn := 0
	billboards.ringed = 0

	var looks: Dictionary = content.tile_looks
	var cracks: Dictionary = tiles.cracks
	var count_all := not own.has_area()
	var layers := tiles.layers.keys()
	layers.sort()
	for layer in layers:
		# In ground-only mode (the 3D projected floor) only the terrain is drawn;
		# props/walls/their shadows+bands are the 3D view's own geometry.
		if ground_only and layer != BASE_LAYER:
			continue
		var cells: Dictionary = tiles.layers[layer]
		# Props cast their shadows, and walls their bands, before any of them
		# is drawn: ahead of the layer they live on, not after the terrain.
		if layer == GameConstants.COLLISION_LAYER:
			shadows.paint(canvas, tiles, content, first, last, own)
			bands.paint_under(canvas, tiles, content, first, last, own)
			strokes.paint_under(canvas, tiles, content, first, last)
		var collision: bool = layer == GameConstants.COLLISION_LAYER
		var liquids_elsewhere: bool = layer == BASE_LAYER and skip_liquids
		# Everything per cell reads the cached tile_look, not GameData's getters:
		# a call into another script per cell cost more than drawing the cell.
		for tile_x in range(first.x, last.x + 1):
			for tile_y in range(first.y, last.y + 1):
				var key := Vector2i(tile_x, tile_y)
				var tile_id: int = cells.get(key, VOID_TILE)
				if tile_id <= VOID_TILE:
					continue
				var look: Array = looks.get(tile_id, GameData.NO_LOOK)
				if look.is_empty():
					look = content.tile_look(tile_id)
				var flags: int = look[GameData.LOOK_FLAGS]
				# The animated liquid layer owns these cells; leave them transparent.
				if liquids_elsewhere and flags & GameData.LOOK_LIQUID:
					continue
				var rect := Rect2(tile_x * TILE_SIZE, tile_y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
				var texture: Texture2D = look[GameData.LOOK_TEXTURE]
				var size: float = look[GameData.LOOK_SIZE]
				# Oversized decorations (large trees/bushes) draw at their `size`, centred
				# on the cell (GameData.tile_render_rect).
				var draw_rect := rect if size <= TILE_SIZE \
					else Rect2(rect.position - Vector2.ONE * ((size - TILE_SIZE) * 0.5), Vector2(size, size))
				if collision and not flags & GameData.LOOK_WALL:
					billboards.ring(canvas, texture, draw_rect, own)
				if texture == null:
					_draw_tile(canvas, content, tile_id, rect)
				elif draw_rect != rect:
					canvas.draw_texture_rect(texture, draw_rect, false)
				else:
					# Wall art is 8x16 -- top face above, front face below -- so it draws
					# cell-wide and aspect-scaled tall, anchored at the cell top, spilling
					# one cell south over the floor (see _draw_tile).
					canvas.draw_texture_rect(texture,
						Rect2(rect.position, Vector2(TILE_SIZE, look[GameData.LOOK_HEIGHT])), false)
				if collision and not cracks.is_empty():
					_draw_crack(canvas, content, tile_id, int(cracks.get(key, 0)), rect)
				if count_all or own.has_point(key):
					drawn += 1
		# Fringes blend the base layer's seams, so they go on after it and
		# before the walls that sit on top; the walls' edge light goes over.
		if layer == BASE_LAYER:
			feathers.paint(canvas, tiles, content, first, last, own)
		elif layer == GameConstants.COLLISION_LAYER:
			bands.paint_over(canvas, tiles, content, first, last)
	# The billboards' lower edges, over every layer so nothing covers them.
	if not ground_only:
		billboards.paint_bottoms(canvas, tiles, content, first, last, own)
	return {"tiles": drawn, "feathers": feathers.drawn, "shadows": shadows.drawn, "bands": bands.drawn,
		"rings": billboards.ringed, "bottoms": billboards.drawn}


func _draw_tile(canvas: CanvasItem, content: GameData, tile_id: int, rect: Rect2) -> void:
	var texture := content.tile_texture(tile_id)
	if texture != null:
		# Oversized decorations (large trees/bushes) draw at their `size`, centred on the
		# cell so the canopy spills over the neighbouring cells you can walk under while the
		# solid trunk stays the centre cell. Ordinary tiles (size == cell) fall through.
		var draw_rect := content.tile_render_rect(tile_id, rect)
		if draw_rect != rect:
			canvas.draw_texture_rect(texture, draw_rect, false)
			return
		# Wall art is 8x16 -- top face above, front face below -- so it draws
		# cell-wide and aspect-scaled tall, anchored at the cell top, spilling
		# one cell south over the floor. Layers ascend and rows run north to
		# south, so a wall below re-covers the spill with its own top face,
		# exactly as both reference clients do it.
		var height := content.tile_render_height(tile_id)
		canvas.draw_texture_rect(texture,
			Rect2(rect.position, Vector2(rect.size.x, height)), false)
		return

	# A content gap should be visible rather than silently blank.
	if not missing_tiles.has(tile_id):
		missing_tiles[tile_id] = true
		push_warning("no sprite for tile id %d" % tile_id)
	canvas.draw_rect(rect, Color.from_hsv(fmod(tile_id * 0.137, 1.0), 0.35, 0.45))


## A damaged breakable wall's crack overlay, laid over the art exactly as the
## tile itself was drawn: the full 8x16 cell for walls, its top square otherwise.
func _draw_crack(canvas: CanvasItem, content: GameData, tile_id: int, stage: int, rect: Rect2) -> void:
	if stage <= 0:
		return
	var draw_rect := content.tile_render_rect(tile_id, rect)
	var height := content.tile_render_height(tile_id)
	if draw_rect == rect and height > rect.size.y:
		var overlay := content.crack_overlay(stage)
		if overlay != null:
			canvas.draw_texture_rect(overlay, Rect2(rect.position, Vector2(rect.size.x, height)), false)
		return
	var face := content.crack_top_face(stage)
	if face != null:
		canvas.draw_texture_rect(face, draw_rect, false)
