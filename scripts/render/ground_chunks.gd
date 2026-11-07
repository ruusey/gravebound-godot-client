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

var chunks := {}   # chunk -> GroundChunk
var dirty := {}    # chunk -> true


## Drops every chunk: a new map.
func drop_all() -> void:
	for chunk in chunks.values():
		chunk.queue_free()
	chunks.clear()
	dirty.clear()


## A cell's look reads its neighbours (seams, bands), and a chunk draws the
## ring of cells around its own, so a change reaches every chunk within two
## cells of it.
func mark(cells: Dictionary) -> void:
	# GroundChunk.of, inlined: a LoadMap can carry hundreds of cells, and two
	# cells either side of one fall in at most two chunks along each axis.
	for cell in cells:
		var low_x := floori((cell.x - 2) / float(GroundChunk.SIZE))
		var high_x := floori((cell.x + 2) / float(GroundChunk.SIZE))
		var low_y := floori((cell.y - 2) / float(GroundChunk.SIZE))
		var high_y := floori((cell.y + 2) / float(GroundChunk.SIZE))
		for x in range(low_x, high_x + 1):
			for y in range(low_y, high_y + 1):
				var chunk := Vector2i(x, y)
				if chunks.has(chunk):
					dirty[chunk] = true


func mark_all() -> void:
	for chunk in chunks:
		dirty[chunk] = true


## A chunk in `view` that is stale -- never drawn, OR drawn but since changed --
## is drawn now, so the ground is never missing and a tall wall's south-spilling
## front face (which only the chunk below it can paint) can't lag a frame behind the
## wall arriving. Only the ring BEYOND the view is throttled to PREFETCH a frame,
## nearest first: off-screen tiles stream in as you walk, and redrawing every chunk
## they touch at once was a frame long enough to bunch the movement packets.
func update(ground: TileRenderer, view: Rect2) -> void:
	var seen := over(view)
	var waiting: Array = []
	var ring := seen.grow(1)
	for x in range(ring.position.x, ring.end.x):
		for y in range(ring.position.y, ring.end.y):
			var chunk := Vector2i(x, y)
			if chunks.has(chunk) and not dirty.has(chunk):
				continue
			if seen.has_point(chunk):
				_draw(ground, chunk)
			else:
				waiting.append(chunk)
	var middle := Vector2(seen.position) + Vector2(seen.size) * 0.5
	waiting.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if seen.has_point(a) != seen.has_point(b):
			return seen.has_point(a)
		return middle.distance_squared_to(Vector2(a)) < middle.distance_squared_to(Vector2(b)))
	for chunk in waiting.slice(0, PREFETCH):
		_draw(ground, chunk)


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
	chunks[at].queue_redraw()
