shader_type canvas_item;
render_mode unshaded;

// One projectile per MultiMesh instance, so every shot cut from one sheet is a
// single draw call. Per instance:
//   INSTANCE_CUSTOM  the sprite's region of the sheet in PIXELS (x, y, w, h).
//                    The compatibility renderer packs custom data as half
//                    floats, exact for whole pixels up to 2048 but not for UVs.
//   COLOR.r          1 to outline the sprite, 0 not to
//   the transform    its scale is the quad's size in world units; an outlined
//                    quad is one unit wider on every side than the sprite, so
//                    the silhouette has room
// The silhouette is what SpriteOutline stamps -- four copies of the sprite in
// black at 0.85 alpha, one unit right, left, down and up -- composited here in
// one pass: its alpha is what four such layers blend to, and the sprite goes
// over it.

const float OUTLINE_ALPHA = 0.85;

varying vec4 region;
varying float margin;
// A LINE_SEGMENT wall is ONE stretched quad instead of a row of tiles: the sprite
// is repeated this many times along the quad's long (X) axis. 1 for everything else.
varying float reps;
// The wall sprite's angleOffset (radians): each tiled sprite is turned by it within
// its cell so a diagonal sheet sprite points right, while the quad lies flat along
// the wall. 0 for non-walls, which carry their rotation in the quad transform.
varying float cell_turn;

void vertex() {
	region = INSTANCE_CUSTOM;
	reps = max(COLOR.g, 1.0);
	cell_turn = COLOR.b;
	// The outline border is one unit in the sprite's own space. A wall is a stretched quad
	// tiled into square cells, so a cell's size is the quad's short (Y) axis; every other
	// shot is a square quad, so either axis gives its size.
	float unit_axis = reps > 1.0 ? length(MODEL_MATRIX[1].xy) : length(MODEL_MATRIX[0].xy);
	margin = COLOR.r > 0.5 && unit_axis > 2.0 ? 1.0 / unit_axis : 0.0;
	COLOR = vec4(1.0);
}

vec4 sprite_at(sampler2D sheet, vec4 cut, vec2 local) {
	if (local.x < 0.0 || local.y < 0.0 || local.x >= 1.0 || local.y >= 1.0) {
		return vec4(0.0);
	}
	return texture(sheet, cut.xy + local * cut.zw);
}

void fragment() {
	vec4 cut = region * vec4(TEXTURE_PIXEL_SIZE, TEXTURE_PIXEL_SIZE);
	float span = 1.0 - 2.0 * margin;
	vec2 local;
	// A wall tiles its sprite along the quad's length; one quad, repeated in-shader. The
	// margin shrink is applied per CELL (after the tiling), so every tiled sprite carries
	// its own outline instead of one border drawn around the whole stretched wall.
	if (reps > 1.0) {
		local = (vec2(fract(UV.x * reps), UV.y) - vec2(margin)) / span;
		// Turn the sprite within its (square) cell by the group's angleOffset, so a
		// diagonal sheet sprite reads straight along the wall. Sampling is rotated by
		// -offset, which displays the sprite rotated by +offset.
		if (cell_turn != 0.0) {
			float s = sin(cell_turn);
			float c = cos(cell_turn);
			vec2 p = local - vec2(0.5);
			local = vec2(c * p.x + s * p.y, -s * p.x + c * p.y) + vec2(0.5);
		}
	} else {
		local = (UV - vec2(margin)) / span;
	}
	vec4 sprite = sprite_at(TEXTURE, cut, local);
	float outline = 0.0;
	if (margin > 0.0) {
		// One outline unit in the sprite's own [0, 1] space.
		float unit = margin / span;
		float clear = (1.0 - OUTLINE_ALPHA * sprite_at(TEXTURE, cut, local + vec2(unit, 0.0)).a)
			* (1.0 - OUTLINE_ALPHA * sprite_at(TEXTURE, cut, local - vec2(unit, 0.0)).a)
			* (1.0 - OUTLINE_ALPHA * sprite_at(TEXTURE, cut, local + vec2(0.0, unit)).a)
			* (1.0 - OUTLINE_ALPHA * sprite_at(TEXTURE, cut, local - vec2(0.0, unit)).a);
		outline = 1.0 - clear;
	}
	float alpha = sprite.a + outline * (1.0 - sprite.a);
	if (alpha <= 0.0) {
		discard;
	}
	COLOR = vec4(sprite.rgb * sprite.a / alpha, alpha);
}
