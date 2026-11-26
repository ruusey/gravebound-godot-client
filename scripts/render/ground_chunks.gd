class_name GroundChunks
extends RefCounted

## Which ground chunks exist, which must be drawn again, and when.
##
## A chunk is made the first time it comes near the view and then kept for
## the life of the realm -- walking back over explored ground costs nothing,
## and one off screen costs the engine a rect test. It is drawn again only
## when a tile in or beside it changes; the web client's rule, but never
## freed, since here a kept chunk is one canvas item, not a thousand sprites
## walked every frame. See `update` for when.

const PREFETCH := 2
## In steady state, the most in-view chunks repainted on one frame. Walking into new
## ground, or a streamed tile diff, can mark a whole leading-edge strip of chunks stale
## at once; each wall-heavy chunk costs milliseconds to paint, so painting a strip of
## them on a single frame is a visible whole-scene hitch (the bunched-packet frame the
## original throttle warned about). They are drawn a few a frame instead, nearest the
## view centre first, and the rest follow. A just-entered realm (no chunks yet) is the
## exception -- the whole view paints at once so the first frame is framed on the player.
const MAX_IN_VIEW_REDRAW := 3
## Of those, how many may be repaints of a chunk already drawn.
const MAX_STALE_REDRAW := 1
## The tile stream's edge sits near the view's edge, so walking delivers a new column
## of cells every few frames and re-marks the same chunk each time: a chunk crossed
## by the edge was repainted a dozen times or more. A drawn chunk repaints at most this
## often; a mark after a quiet spell still paints at once (a wall cracking), and marks
## inside the window collect into one repaint when it ends.
const REPAINT_INTERVAL_MS := 200

## REPAINT_INTERVAL_MS, as a field so a test can repaint on every change.
var repaint_interval_ms := REPAINT_INTERVAL_MS
var chunks := {}   # chunk -> GroundChunk
## chunk -> the cells changed since it was drawn (Rect2i), or true for all of them
var dirty := {}
## Running totals for diagnostics (HitchRecorder): chunk paints, how many of them
## repainted a chunk already drawn, and the time spent painting.
var paints := 0
## Chunks queued to draw, ever; a cache drawn off screen (the 2.5D floor) re-renders when it moves.
var queued := 0
var repaints := 0
var paint_us := 0


## Drops every chunk: a new map.
func drop_all() -> void:
	for chunk in chunks.values():
		chunk.queue_free()
	chunks.clear()
	dirty.clear()


## A cell's look reads its neighbours (seams, bands), and a chunk draws the
## ring of cells around its own, so a change reaches every chunk within two
## cells of it -- and, southward, every chunk that redraws a wall that far north
## for its spilling face (`south` rows; TileRenderer.paint_cells).
func mark(cells: Dictionary, south := 2) -> void:
	# GroundChunk.of, inlined: a LoadMap can carry hundreds of cells, and a few
	# cells either side of one fall in at most two chunks along each axis.
	for cell in cells:
		var low_x := floori((cell.x - 2) / float(GroundChunk.SIZE))
		var high_x := floori((cell.x + 2) / float(GroundChunk.SIZE))
		var low_y := floori((cell.y - 2) / float(GroundChunk.SIZE))
		var high_y := floori((cell.y + maxi(south, 2)) / float(GroundChunk.SIZE))
		for x in range(low_x, high_x + 1):
			for y in range(low_y, high_y + 1):
				var chunk := Vector2i(x, y)
				if chunks.has(chunk):
					var area: Variant = dirty.get(chunk)
					if area is Rect2i:
						dirty[chunk] = area.expand(cell)
					elif area == null:
						dirty[chunk] = Rect2i(cell, Vector2i.ONE)


func mark_all() -> void:
	for chunk in chunks:
		dirty[chunk] = true


## Draws the stale chunks in and around `view`: never-drawn ones so the ground is
## never missing, and drawn-but-since-changed ones so a tall wall's south-spilling
## front face (which only the chunk below it can paint) follows the wall. In-view
## chunks are capped at MAX_IN_VIEW_REDRAW a frame (nearest the view centre first,
## never-drawn before changed) so a strip going stale at once -- a stream diff, or
## walking into new ground -- doesn't bunch a frame; a freshly entered realm paints
## its whole view at once. The ring BEYOND the view streams PREFETCH a frame, nearest
## first, as it always has.
func update(ground: TileRenderer, view: Rect2) -> void:
	var seen := over(view)
	var fresh: Array = []    # in view, never drawn -- bare ground, drawn first
	var stale: Array = []    # in view, drawn but a tile has since changed
	var beyond: Array = []   # the ring past the view, streamed ahead
	var ring := seen.grow(1)
	var now := Time.get_ticks_msec()
	var near := view.grow(GroundChunk.TILE_SIZE * 2)
	for x in range(ring.position.x, ring.end.x):
		for y in range(ring.position.y, ring.end.y):
			var chunk := Vector2i(x, y)
			var exists := chunks.has(chunk)
			if exists and (not dirty.has(chunk) or now - chunks[chunk].painted_at < repaint_interval_ms):
				continue
			if not seen.has_point(chunk):
				# Off screen, a drawn chunk waits for the view to reach it: the stream's
				# edge re-marks the ring constantly, and nobody sees it.
				if not exists:
					beyond.append(chunk)
			elif exists:
				# A chunk is far bigger than the stream's margin past the view, so most
				# cells arrive in an on-screen chunk but off screen themselves: the
				# repaint waits until what changed is about to show, by which time the
				# rest of the band has arrived with it.
				if _changes_near(chunk, near):
					stale.append(chunk)
			else:
				fresh.append(chunk)
	var middle := Vector2(seen.position) + Vector2(seen.size) * 0.5
	var nearer := func(a: Vector2i, b: Vector2i) -> bool:
		return middle.distance_squared_to(Vector2(a)) < middle.distance_squared_to(Vector2(b))
	fresh.sort_custom(nearer)
	stale.sort_custom(nearer)
	# Entering a realm (nothing drawn yet) paints the whole view at once, so the first
	# frame is framed on the player instead of filling in; after that the cap holds.
	var entering := chunks.is_empty()
	var budget := fresh.size() + stale.size() if entering else MAX_IN_VIEW_REDRAW
	for chunk in fresh:
		if budget <= 0:
			break
		_draw(ground, chunk)
		budget -= 1
	if not entering:
		budget = mini(budget, MAX_STALE_REDRAW)
	for chunk in stale:
		if budget <= 0:
			break
		_draw(ground, chunk)
		budget -= 1
	beyond.sort_custom(nearer)
	for chunk in beyond.slice(0, PREFETCH):
		_draw(ground, chunk)


func _changes_near(chunk: Vector2i, near: Rect2) -> bool:
	var area: Variant = dirty[chunk]
	if not area is Rect2i:
		return true
	var cells: Rect2i = area
	var world := Rect2(Vector2(cells.position * GroundChunk.TILE_SIZE), Vector2(cells.size * GroundChunk.TILE_SIZE))
	return world.grow(GroundChunk.TILE_SIZE * 2).intersects(near)


## The chunks a world rect touches, in chunk coordinates.
static func over(view: Rect2) -> Rect2i:
	var span := GroundChunk.SIZE * GroundChunk.TILE_SIZE
	var first := Vector2i(floori(view.position.x / span), floori(view.position.y / span))
	var last := Vector2i(floori(view.end.x / span), floori(view.end.y / span))
	return Rect2i(first, last - first + Vector2i.ONE)


## What the chunks in `view` put down, summed.
func stats_over(view: Rect2) -> Dictionary:
	var total := {}
	var seen := over(view)
	for x in range(seen.position.x, seen.end.x):
		for y in range(seen.position.y, seen.end.y):
			var chunk: GroundChunk = chunks.get(Vector2i(x, y))
			if chunk == null:
				continue
			for key in chunk.stats:
				total[key] = int(total.get(key, 0)) + int(chunk.stats[key])
	return total


func _draw(ground: TileRenderer, at: Vector2i) -> void:
	if not chunks.has(at):
		var chunk := GroundChunk.new(at, ground)
		chunks[at] = chunk
		ground.add_child(chunk)
	dirty.erase(at)
	chunks[at].painted_at = Time.get_ticks_msec()
	chunks[at].queue_redraw()
	queued += 1
