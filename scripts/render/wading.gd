class_name Wading
extends RefCounted

## Legs under the water.
##
## A character standing in water or lava is drawn sunk into it: the body drops
## by 30% of its cell and is then clipped back to the cell, so what is left is
## the top seven tenths sitting low in the liquid. The web client does it with
## a mask and the same 0.30; clipping the drawn rect and taking the matching
## slice of the sheet is the same picture without a material, which an
## immediate-mode layer cannot carry per command.
##
## Only the player wades. The web client tests exactly one entity for it, and
## enemies keep their feet -- many of them are fish, and the rest are drawn at
## sizes the clip would eat.

## How much of the body the surface hides. The web client's `wadingClip`.
const SINK := 0.30


## Where a sunk sprite lands, before clipping.
static func sunk(rect: Rect2, cell: float) -> Rect2:
	return Rect2(rect.position + Vector2(0.0, cell * SINK), rect.size)


## The part of a sunk sprite still above the surface: whatever of it falls
## inside its own cell. A tall attack frame loses its overhang at the top as
## well, which is what the web client's mask does -- it is the cell rect, not
## a waterline.
static func shown(rect: Rect2, cell: Rect2) -> Rect2:
	return rect.intersection(cell)


## The slice of the frame that `shown` corresponds to.
##
## In the texture's OWN coordinates, not the sheet's -- a dyed frame is a
## texture of its own, and an AtlasTexture already
## knows where its frame sits and offsets a source rect by that origin, so
## handing it sheet coordinates samples past the end of the frame and clips to
## nothing -- the body disappears entirely rather than losing its legs.
static func slice(texture: Texture2D, rect: Rect2, visible: Rect2) -> Rect2:
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Rect2()
	var scale := texture.get_size() / rect.size
	return Rect2((visible.position - rect.position) * scale, visible.size * scale)
