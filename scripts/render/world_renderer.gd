class_name WorldRenderer
extends Node2D

## The realm, drawn as six stacked canvas items.
##
## Each layer is a Node2D that redraws itself every frame -- all but the
## ground, kept in chunks and drawn again only where it changed -- still
## immediate-mode, still culled to the camera rect, with no node per entity.
## The split exists so a layer can carry its own material: every CanvasItem
## has one, so a shader on the ground leaves the characters standing on it
## alone. Both reference clients are arranged the same way, and the web client
## deliberately keeps its bullet layer outside the graded world container
## because a filter haloes the alpha-faded edges of a projectile.
##
## Draw order is child order. Nothing here sets z_index: on a CanvasItem that
## value is relative to the parent, and a stray one is what put a map layer
## over the players the last time this was a tree of nodes.

var state: RealmState
var game_data: GameData

var tiles := TileRenderer.new()
## Animated water/lava, drawn under the ground (which skips those cells); off when
## the "animated_liquids" setting is off, and then the ground draws them static.
var liquid := LiquidRenderer.new()
var entities := EntityRenderer.new()
var particles := ParticleRenderer.new()
## Hit chips, drawn over the bodies and centred on whatever was hit. RealmState.hit_burst.
var hit_chips := HitBurstRenderer.new()
## Newly streamed terrain fading in from black, over the ground and bodies.
var reveal := TerrainReveal.new()
var bullets := BulletRenderer.new()
var effects := EffectRenderer.new()
var debug := CollisionOverlay.new()
## The layers redrawn every frame (all but the chunk-cached ground), built once
## so _process doesn't allocate an array literal per frame.
var _redraw_layers: Array = []

var show_collision: bool:
	get: return debug.show_collision
	set(value): debug.show_collision = value


func _ready() -> void:
	# Added in draw order: ground, what stands on it (with the tall walls redrawn
	# among the bodies by depth, so they cover whatever stands behind them), what
	# flies over all of it, then the debug view. Names, bars and numbers are not here: they are UI, Controls on
	# EntityOverlay's own CanvasLayer, outside the camera.
	# Nearest on every layer, said outright rather than inherited from the
	# project default: the web export drew the zoomed world with linear
	# filtering -- every tile, sprite and name a 2x blur -- while the
	# Controls beside it, which do not zoom, stayed crisp. The desktop honours
	# the default; the world must not depend on which build honours what.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Liquid sits under the ground: the ground leaves its cells transparent, so the
	# animated water/lava shows through and props/walls on it still draw over it.
	# hit_chips sits just over the bodies, so a burst reads on top of the sprite.
	for layer in [liquid, tiles, entities, hit_chips, reveal, particles, bullets, effects, debug]:
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer)
	# Projectiles are bright overlays, not part of the lit scene. Unshaded, each bullet
	# is ONE draw no matter how many of the dozens of scene lights overlap it -- a screen
	# full of enemy shots is otherwise bullets x lights shading passes, which tanks the
	# frame rate even though the bullets emit no light of their own. Also renders them
	# full-bright so shots stay readable in a dark dungeon (the web client keeps its
	# bullet layer outside the graded world for the same reason).
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	# Bright overlays, not lit scenery: particles, ability effects and the debug
	# view read full-bright like the bullets, and sharing the unlit material keeps
	# each a single pass instead of being re-shaded once per overlapping scene light
	# (dozens in a torch-lined dungeon) -- the per-light multiply those layers paid
	# was pure cost, since none of them is meant to be darkened by the ambient.
	for overlay in [bullets, particles, effects, debug, hit_chips]:
		overlay.material = unlit
	# Liquid is chunk-cached and animates on the GPU, so it is not redrawn per frame.
	_redraw_layers = [entities, hit_chips, particles, bullets, effects, debug]
	_wire()


func setup(realm_state: RealmState, content: GameData) -> void:
	state = realm_state
	game_data = content
	_wire()


## What the last frame actually drew, after culling -- the externally visible
## evidence that culling works, and what the debug HUD reports.
var draw_stats: Dictionary:
	get:
		var stats := entities.counts.duplicate()
		stats["tiles"] = tiles.drawn
		stats["feathers"] = tiles.feathers_drawn
		stats["bullets"] = bullets.drawn
		stats["particles"] = particles.drawn
		stats["effects"] = effects.drawn
		stats["wall_tops"] = entities.covers.drawn
		stats["object_shadows"] = int(tiles.stats.get("shadows", 0))
		stats["wall_bands"] = int(tiles.stats.get("bands", 0))
		stats["billboard_rings"] = int(tiles.stats.get("rings", 0))
		stats["billboard_bottoms"] = int(tiles.stats.get("bottoms", 0))
		return stats


## Everything that moves, every frame; the ground only where it changed.
func _process(_delta: float) -> void:
	# The liquid layer refreshes BEFORE the ground, while tiles.changed_cells is
	# still populated (the ground clears it). Off => the ground draws liquids static.
	var animate_liquids := state != null and state.settings.is_on("animated_liquids")
	liquid.visible = animate_liquids
	tiles.skip_liquids = animate_liquids
	if animate_liquids:
		liquid.refresh()
	# Before the ground, which resets tiles.cleared.
	reveal.refresh()
	tiles.refresh()
	for layer in _redraw_layers:
		layer.queue_redraw()


func _wire() -> void:
	tiles.state = state
	tiles.content = game_data
	liquid.state = state
	liquid.content = game_data
	entities.state = state
	entities.content = game_data
	particles.state = state
	hit_chips.field = state.hit_burst.chips if state != null else null
	reveal.state = state
	bullets.state = state
	bullets.content = game_data
	effects.state = state
	debug.state = state
	debug.content = game_data
