class_name EntityRenderer
extends Node2D

## Draws the players, enemies, loot and portals EntityQueue hands it.
## Bullets are BulletRenderer's job -- they neither sort nor mirror.
##
## Its own canvas item, so an effect on the characters leaves the ground and
## the projectiles alone.

const EMPTY_COUNTS := {"players": 0, "enemies": 0, "containers": 0,
	"portals": 0, "shadows": 0}

## An outline is 4 extra draw calls per sprite (SpriteOutline). Players and enemies
## always get one -- they're few and the focus -- but loot bags and portals are static
## props, and a room strewn with ~100 of each would otherwise add 4 draws EACH every
## frame, the dominant cost of the loot-pile FPS drop. Cap how many static props get an
## outline per frame; the rest draw plain. Normal play (a handful of bags) is under the
## cap, so it only bites the pathological pile.
const STATIC_OUTLINE_BUDGET := 64


var state: RealmState
var content: GameData
var queue := EntityQueue.new()
var counts := EMPTY_COUNTS.duplicate()
var _static_outlined := 0


func _draw() -> void:
	if state == null or content == null:
		return
	counts = draw_ground(self, queue.build(state, content, ViewRect.of(self)))


## Shadows go down in a pass of their own, ahead of the bodies, so the
## ellipses batch instead of alternating with a texture draw per entity. The
## native client separates them for the same reason; the web client parents
## each shadow to its own entity and gets the same picture, because the queue
## is sorted on feet -- a later entity is always lower, so its shadow can
## never reach the body of one already drawn. Measured: interleaving the two
## loops renders byte-identical output.
func draw_ground(canvas: CanvasItem, items: Array) -> Dictionary:
	var counts := EMPTY_COUNTS.duplicate()
	_static_outlined = 0
	# Every body on the pixel grid -- the same snap the overlay applies to
	# the name and bars under it, through the same transform, so the two
	# land on the same pixel and move together. Snapped after the sort,
	# which reads the true feet. The canvas transform + its inverse are the
	# same for every entity this frame, so compute them once here rather than
	# per entity inside PixelSnap.world (an affine_inverse per sprite per frame).
	var to_screen := canvas.get_global_transform_with_canvas()
	var inverse := to_screen.affine_inverse()
	for item in items:
		# Smooth items (remote players) keep their interpolated sub-pixel position so
		# slow walkers glide instead of stair-stepping between whole pixels.
		if item.get("smooth", false):
			continue
		item["pos"] = inverse * (to_screen * item["pos"]).round()
	# GroundShadow.under_entity, inlined: one ellipse per body.
	var shadow := Color(0.0, 0.0, 0.0, GroundShadow.ENTITY_ALPHA)
	var flatten := Vector2(1.0, GroundShadow.FLATTEN)
	for item in items:
		var size: float = item["size"]
		if size > 0.0:
			var origin: Vector2 = item["pos"]
			canvas.draw_set_transform(origin + Vector2(size * 0.5, size * GroundShadow.ENTITY_CENTRE),
				0.0, flatten)
			CircleStamp.disc(canvas, Vector2.ZERO, size * GroundShadow.HALF_WIDTH, shadow)
			counts["shadows"] += 1
		if item.get("lock", false):
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			LockOnRing.draw(canvas, item["pos"], size)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var outlines := SpriteOutline.enabled
	for item in items:
		_draw_entity(canvas, item, outlines)
		counts[item["kind"]] += 1
	return counts


## Where a frame lands, given the body cell it belongs to.
##
## Anchored by the bottom of that cell rather than by the cell itself: a
## taller frame grows upward, and a wider one grows away from the body --
## rightward as authored, leftward once mirrored -- so the overhanging part of
## a swing always lands on the side the character is facing. Get the mirrored
## case wrong and the weapon sticks out of the character's back.
static func frame_rect(origin: Vector2, cell: float, draw: Vector2,
		flip: bool) -> Rect2:
	return Rect2(
		origin.x + (cell - draw.x if flip else 0.0),
		origin.y + cell - draw.y,
		draw.x, draw.y)


## Missing art becomes a solid block in the entity's fallback colour, so a
## content gap is visible on screen rather than silently absent.
##
## Mirroring goes through a scale transform. draw_texture_rect's last argument
## is `transpose`, which swaps the X and Y axes -- passing a flip there draws a
## side-facing sprite rotated onto its side, which reads as the character
## facing downward while it walks left. A negative-width Rect2 mirrors but
## also displaces the sprite, so neither shortcut works.
## Where an entity's body lands and which slice of its sheet shows.
##
## Everything a caller would otherwise have to read back off a canvas: a
## standing entity draws its whole frame, and one in a liquid sinks by three
## tenths and is clipped to its cell, so the legs go under the surface. Done
## to the rect and the slice rather than with a mask, because an
## immediate-mode layer has no per-command mask to do it with.
static func body_draw(item: Dictionary) -> Dictionary:
	var rect := frame_rect(item["pos"], float(item["size"]), item["draw"], item["flip"])
	var texture: Texture2D = item["texture"]
	if not item.get("wading", false) or texture == null:
		return {"rect": rect, "slice": Rect2()}

	var cell := Rect2(item["pos"], Vector2.ONE * float(item["size"]))
	var sunk := Wading.sunk(rect, float(item["size"]))
	var shown := Wading.shown(sunk, cell)
	return {"rect": shown, "slice": Wading.slice(texture, sunk, shown)}


func _draw_entity(canvas: CanvasItem, item: Dictionary, outlines: bool) -> void:
	# A downed companion lies on its side (fallen); facing-flip no longer applies.
	var downed: bool = item.get("downed", false)
	var flip: bool = item["flip"] and not downed
	var texture: Texture2D = item["texture"]
	var rect: Rect2
	var slice := Rect2()
	if item.get("wading", false) and texture != null:
		var body := body_draw(item)
		rect = body["rect"]
		slice = body["slice"]
	else:
		rect = frame_rect(item["pos"], float(item["size"]), item["draw"], flip)
	if downed:
		# Rotate the whole frame a quarter-turn about its centre so a standing
		# sprite reads as collapsed on the ground.
		var centre := rect.position + rect.size * 0.5
		canvas.draw_set_transform(centre, PI * 0.5, Vector2.ONE)
		rect = Rect2(-rect.size * 0.5, rect.size)
	elif flip:
		# Origin at the sprite's right edge with x negated, so local x in
		# [0, size] covers the same cell right-to-left.
		canvas.draw_set_transform(rect.position + Vector2(rect.size.x, 0.0), 0.0,
			Vector2(-1.0, 1.0))
		rect = Rect2(Vector2.ZERO, rect.size)

	if texture != null:
		# Static props (loot/portals) outline only up to the per-frame budget; players
		# and enemies always do. Keeps a loot pile from spending 4 draw calls per bag.
		var kind: String = item["kind"]
		var outline := outlines
		if outline and (kind == "containers" or kind == "portals"):
			if _static_outlined >= STATIC_OUTLINE_BUDGET:
				outline = false
			else:
				_static_outlined += 1
		var modulate: Color = item["modulate"]
		if slice.size == Vector2.ZERO:
			if outline:
				# SpriteOutline.stamp, inlined.
				for offset in SpriteOutline.OFFSETS:
					canvas.draw_texture_rect(texture, Rect2(rect.position + offset, rect.size), false,
						SpriteOutline.TINT)
			canvas.draw_texture_rect(texture, rect, false, modulate)
		else:
			if outline:
				SpriteOutline.stamp(canvas, texture, rect, slice)
			canvas.draw_texture_rect_region(texture, rect, slice, modulate)
	else:
		canvas.draw_rect(rect, item["tint"])

	if flip or downed:
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
