class_name HitBurstRenderer
extends Node2D

## Draws one HitBurst pool as crisp pixel squares.
##
## Two of these exist -- one added under the bodies, one over them -- each
## pointed at the matching ParticleField, so the same burst reads as chips
## flying behind and (a few) in front of the sprite. Solid, nearest-filtered
## quads, not the soft dots the trail/impact field uses: a hit should look
## pixelated, like a block shattering, not a puff of smoke. Batched through one
## MultiMesh exactly as ParticleRenderer does, so a screenful of chips is a
## single draw call.

## Past any chip size HitBurst spawns; only pads the cull.
const MAX_CHIP := 12.0

var field: ParticleField
var drawn := 0

static var _white: ImageTexture
var _multimesh: MultiMesh


func _ready() -> void:
	# Crisp squares: a chip sampled linearly would smear into a soft blob.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_multimesh.mesh = quad


func _draw() -> void:
	drawn = 0
	if field == null:
		return
	drawn = _paint(field, ViewRect.of(self))


## The in-view chips packed into the shared MultiMesh and drawn at once; fade is
## linear in remaining life, so a chip holds its colour then winks out.
func _paint(pool: ParticleField, view: Rect2) -> int:
	if _multimesh.instance_count < pool.count:
		_multimesh.instance_count = pool.count
	var count := 0
	var padded := view.grow(MAX_CHIP)
	for i in pool.count:
		var at := Vector2(pool.x[i], pool.y[i])
		if not padded.has_point(at):
			continue
		var remaining := pool.life[i] / pool.max_life[i]
		var size := pool.size_start[i] + (pool.size_end[i] - pool.size_start[i]) * (1.0 - remaining)
		var colour: Color = pool.tint[i]
		colour.a = minf(1.0, remaining * 2.2)
		_multimesh.set_instance_transform_2d(count, Transform2D(0.0, Vector2(size, size), 0.0, at))
		_multimesh.set_instance_color(count, colour)
		count += 1
	_multimesh.visible_instance_count = count
	if count > 0:
		draw_multimesh(_multimesh, _white_pixel())
	return count


## A 1x1 opaque white texture: the quad's colour is the chip's, so the texture
## only has to carry full alpha.
static func _white_pixel() -> ImageTexture:
	if _white != null:
		return _white
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	return _white
