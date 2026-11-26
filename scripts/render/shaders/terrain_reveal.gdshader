// Covers freshly streamed terrain in the void's black and lifts it off.
// COLOR.a is how much of the cell is still covered (1 = hidden, 0 = shown).
// Smooth mode fades the black; dither mode drops whole art pixels in a 4x4
// Bayer order, so the terrain dissolves in on the art's own pixel grid.
shader_type canvas_item;
render_mode unshaded;

uniform bool dither = false;
// World units per art pixel: an 8px tile drawn at 32.
uniform float art_pixel = 4.0;

varying vec2 world_position;

const float BAYER[16] = float[16](
	0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0);

void vertex() {
	world_position = VERTEX;
}

void fragment() {
	float covered = COLOR.a;
	if (dither) {
		vec2 cell = mod(floor(world_position / art_pixel), 4.0);
		if (covered <= BAYER[int(cell.x) + int(cell.y) * 4]) {
			discard;
		}
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, covered);
	}
}
