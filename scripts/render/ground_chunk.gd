class_name GroundChunk
extends Node2D

## SIZE x SIZE cells of ground, drawn once and kept.
##
## The engine keeps a canvas item's drawing and replays it every frame for
## almost nothing; what costs is rebuilding it, and the ground was over half
## of every frame when it was rebuilt each one. So a chunk draws only when
## GroundChunks asks -- its tiles arrived, or a neighbour's changed -- and
## otherwise stands.
##
## Nothing on the ground reaches more than one cell past its own: a tall
## wall spills one cell south, outlines and bands a unit or two. So a chunk
## paints its cells AND the ring of cells around them, in the one renderer's
## order (TileRenderer.paint), clipped to its own square: inside the square
## it is exactly what drawing the whole view at once drew. The clip reaches
## OVERLAP past the square, because a clip is cut in whole screen pixels:
## at a fractional scale with a border on a half pixel, two squares cut
## edge to edge could both round away from it and leave a line of
## background between them (a 1920x961 browser showed one across the
## nexus). In that sliver both chunks paint the same ground in the same
## order, so which is on top cannot show. The clip is also the box the
## engine culls an off-screen chunk by.

const SIZE := 8
const TILE_SIZE := GameConstants.TILE_SIZE
## How far the clip reaches past the square, in world units: more than a
## screen pixel at any scale the world draws at, far less than the ring.
const OVERLAP := 1.0

## Which chunk, in chunk coordinates.
var at: Vector2i
var painter: TileRenderer
## What its last draw put down, over its own cells only (TileRenderer.paint).
var stats := {}
## How many times it has been drawn: once, unless its ground changed.
var draws := 0
## When GroundChunks last asked it to draw (ticks msec).
var painted_at := -1000000


func _init(chunk: Vector2i = Vector2i.ZERO, ground: TileRenderer = null) -> void:
	at = chunk
	painter = ground
	# A shader hung on the ground reaches every chunk of it.
	use_parent_material = true


func _ready() -> void:
	var item := get_canvas_item()
	RenderingServer.canvas_item_set_custom_rect(item, true, clip())
	RenderingServer.canvas_item_set_clip(item, true)


func _draw() -> void:
	if painter != null:
		var started := Time.get_ticks_usec()
		stats = painter.paint_cells(self, cells())
		draws += 1
		var tally := painter.chunks
		tally.paints += 1
		tally.repaints += 1 if draws > 1 else 0
		tally.paint_us += Time.get_ticks_usec() - started


## Its cells, first to last.
func cells() -> Rect2i:
	return Rect2i(at * SIZE, Vector2i(SIZE, SIZE))


## Its square in world units.
func area() -> Rect2:
	return Rect2(Vector2(at * SIZE * TILE_SIZE), Vector2.ONE * SIZE * TILE_SIZE)


## What it is clipped to: its square and OVERLAP around it.
func clip() -> Rect2:
	return area().grow(OVERLAP)


static func of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(SIZE)), floori(cell.y / float(SIZE)))


## Whether a cell counts toward a chunk's stats: its own, not the ring
## around them it also draws. An empty `own` counts everything.
static func counts(own: Rect2i, x: int, y: int) -> bool:
	return not own.has_area() or own.has_point(Vector2i(x, y))
