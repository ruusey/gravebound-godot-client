class_name TileInteract
extends RefCounted

## The forge, the fame store, the potion shelves: the tiles you use with F.
##
## Which tile is meant is the web client's rule, and it is also the server's
## check: the nearest tile with an `interactionType`, on either layer, in the
## five-by-five window around the tile the player stands on, and no further
## than three tiles from the player's corner. The server refuses anything
## further with a log line and nothing the client can see.

const WINDOW := 2
const REACH_TILES := 3.0


## {tile_x, tile_y, type, name}, or {} when nothing is in reach.
static func nearest(tiles: TileMapState, content: GameData, position: Vector2) -> Dictionary:
	if content == null:
		return {}
	var size := float(GameConstants.TILE_SIZE)
	var px := floori(position.x / size)
	var py := floori(position.y / size)
	var found := {}
	var best := REACH_TILES * REACH_TILES * size * size
	for dy in range(-WINDOW, WINDOW + 1):
		for dx in range(-WINDOW, WINDOW + 1):
			var tx := px + dx
			var ty := py + dy
			if tx < 0 or ty < 0:
				continue
			for layer in [GameConstants.COLLISION_LAYER, TileMapState.BASE_LAYER]:
				var definition: Dictionary = content.tiles.get(tiles.tile_at(layer, tx, ty), {})
				# Every shipped tile carries the key, null on all but the few that
				# matter, and str(null) is "<null>", not "".
				var kind: Variant = definition.get("interactionType")
				if kind == null or str(kind) == "":
					continue
				var d2 := position.distance_squared_to(Vector2((tx + 0.5) * size, (ty + 0.5) * size))
				if d2 <= best:
					best = d2
					found = {"tile_x": tx, "tile_y": ty, "type": str(kind),
						"name": str(definition.get("name", kind))}
	return found


## What the prompt says, in the web client's words.
static func verb(candidate: Dictionary) -> String:
	match str(candidate.get("type", "")):
		"forge": return "Use Forge"
		"fame_store": return "Open Fame Store"
		"potion_storage": return "Open Potion Storage"
		"exchange_market": return "Open Exchange Market"
		"arena": return "Enter the Colosseum"
	return "Use %s" % candidate.get("name", "")
