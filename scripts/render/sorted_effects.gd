class_name SortedEffects
extends RefCounted

## Ability and enemy effects, drawn in among the bodies so a body stays on top.
##
## Each effect is drawn just before the first body (in feet order) that it overlaps,
## so every body it touches draws over it, and walls drawn before that body are
## under it. An effect touching no body draws after everything, over every wall.
## Same cursor shape as WallCovers, so EntityRenderer threads both through one pass.

## How far above its feet a body can reach, when looking for bodies an effect touches.
const MAX_BODY_HEIGHT := 256.0

## Effects drawn last frame.
var drawn := 0
## Sorted (slot << 16 | entry) keys, and the cursor of the next one to draw.
var _keys := PackedInt64Array()
var _next := 0
var _effects: Array = []
var _bounds: Array = []
var _now := 0


## Gathers this frame's effects in view. place() then fixes where each one draws.
func collect(realm: RealmState, view: Rect2) -> void:
	drawn = 0
	_next = 0
	_keys.resize(0)
	_effects.clear()
	_bounds.clear()
	if realm == null:
		return
	_now = realm.abilities.now()
	for fx in realm.abilities.effects:
		if fx["type"] in EffectRenderer.FOLLOWS_OWNER:
			EffectRenderer.follow_owner(realm, fx)
		var box := EffectRenderer.bounds(fx)
		if not view.intersects(box) or not EffectRenderer.shown(realm, fx):
			continue
		_effects.append(fx)
		_bounds.append(box)


## Slots each effect before the first of `items` (feet-ordered, keyed by `depths`,
## EntityQueue.depth) that it overlaps, or after them all; strikes always after.
func place(items: Array, depths: PackedInt64Array) -> void:
	_keys.resize(0)
	_next = 0
	var layered := depths.bsearch(EntityQueue.LAYER_STEP) if not depths.is_empty() else items.size()
	for entry in _effects.size():
		var slot := items.size()
		if not _effects[entry]["type"] in EffectRenderer.OVER_BODIES:
			slot = _first_touching(items, depths, _bounds[entry], layered)
		_keys.append((slot << 16) | entry)
	_keys.sort()


## The first body overlapping `box`, or items.size(). Ground bodies are searched only
## where their feet can reach the box; the few raised (layered) ones after them all.
func _first_touching(items: Array, depths: PackedInt64Array, box: Rect2, layered: int) -> int:
	var start := 0
	var stop := layered
	if not depths.is_empty():
		start = depths.bsearch(_feet_depth(box.position.y))
		stop = mini(layered, depths.bsearch(_feet_depth(box.end.y + MAX_BODY_HEIGHT)))
	for i in range(start, stop):
		if _touches(items[i], box):
			return i
	for i in range(layered, items.size()):
		if _touches(items[i], box):
			return i
	return items.size()


static func _touches(item: Dictionary, box: Rect2) -> bool:
	var size: float = item["size"]
	return box.intersects(Rect2(item["pos"], Vector2(size, size)))


static func _feet_depth(y: float) -> int:
	return int(roundf(y * 16.0)) + EntityQueue.FEET_BIAS


## Draws every effect slotted at or before body `index`.
func draw_through(canvas: CanvasItem, index: int) -> void:
	var count := _keys.size()
	while _next < count and (_keys[_next] >> 16) <= index:
		_draw(canvas, _keys[_next] & 0xFFFF)
		_next += 1


## Draws the effects that touch no body: over every body and wall.
func draw_rest(canvas: CanvasItem) -> void:
	var count := _keys.size()
	while _next < count:
		_draw(canvas, _keys[_next] & 0xFFFF)
		_next += 1


## The slot each gathered effect drew at last, in gather order. For tests.
func slots() -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(_effects.size())
	for key in _keys:
		out[key & 0xFFFF] = key >> 16
	return out


func _draw(canvas: CanvasItem, entry: int) -> void:
	EffectRenderer.draw_effect(canvas, _effects[entry], _now)
	# A drawer may leave its own transform set; the next body expects none.
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	drawn += 1
