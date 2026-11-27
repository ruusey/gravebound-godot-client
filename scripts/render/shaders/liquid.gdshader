shader_type canvas_item;

// Animates the chunk-cached water/lava tiles entirely on the GPU: the layer is
// drawn once (like the ground) and this runs every frame off TIME, so an ocean or
// a lava lake moves for free. Water vs lava is told apart by the per-tile data flag
// (data.liquid), which the renderer packs into the shoreless cells' vertex-colour
// alpha -- NOT guessed from the base pixel -- so one material covers both and lava
// animates as lava at any colour its art uses. No TEXTURE UV is offset -- that would
// bleed across the atlas -- the motion is added to the colour.
//
// The pattern is driven by WORLD position (MODEL_MATRIX * VERTEX, before the camera
// transform), not FRAGCOORD, so it stays locked to the terrain and does NOT scroll
// with the camera.
//
// A cell beside land arrives with its shore in the vertex colour (LiquidRenderer):
// red = the cardinal sides that are land, green = the corners, as 4-bit masks over
// 15; blue and alpha = the colour of the ground's lip, RGB565, with blue zero
// for none (red is never zero in a real one). Where land wraps two sides of a
// cell its corner is rounded off, and along a straight run the lip wanders a
// pixel in and out in long smooth runs, so the coastline leaves the tile grid
// without teeth. Shore effects are worked on the art's own pixel grid so they
// stay crisp.

uniform float water_speed : hint_range(0.0, 6.0) = 1.5;
uniform float lava_speed : hint_range(0.0, 6.0) = 1.0;
uniform float shore_reach : hint_range(4.0, 32.0) = 15.0;
uniform float shore_pixel : hint_range(1.0, 8.0) = 4.0;
uniform float lip_depth : hint_range(0.0, 16.0) = 3.0;
uniform float corner_radius : hint_range(0.0, 32.0) = 14.0;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.38;
uniform vec3 foam_colour : source_color = vec3(0.86, 0.95, 1.0);
// Seconds to hold the motion at instead of TIME; negative leaves it running.
// A capture pins it, as it pins every other clock.
uniform float pinned_time = -1.0;

#include "res://scripts/render/shaders/scene_light.gdshaderinc"

const float CELL = 32.0;

varying vec2 world_pos;
varying vec2 shore_mask;
varying vec3 lip_colour;
varying float has_lip;
varying float lava_mix;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	shore_mask = floor(COLOR.rg * 15.0 + 0.5);
	// Water (0) vs lava (1): the renderer packs data.liquid into alpha on the shoreless
	// cells (which carry no mask); a cell with a shore mask is always water. Gating on
	// the mask keeps a shore cell's alpha (its lip's low byte) from reading as lava.
	lava_mix = (1.0 - step(0.5, shore_mask.r + shore_mask.g)) * step(0.5, COLOR.a);
	float high = floor(COLOR.b * 255.0 + 0.5);
	float low = floor(COLOR.a * 255.0 + 0.5);
	has_lip = step(0.5, high);
	lip_colour = vec3(floor(high / 8.0) / 31.0,
		(mod(high, 8.0) * 8.0 + floor(low / 32.0)) / 63.0, mod(low, 32.0) / 31.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bit(float mask, float value) {
	return mod(floor(mask / value), 2.0);
}

// World pixels from `local` (within the cell) to the nearest land side. Where
// a land side meets a land side the corner is rounded, which comes out below
// zero: land filling the corner.
float side_distance(vec2 local) {
	float far = CELL * 2.0;
	vec2 back = CELL - local;
	float dy = min(mix(far, local.y, bit(shore_mask.r, 1.0)), mix(far, back.y, bit(shore_mask.r, 2.0)));
	float dx = min(mix(far, local.x, bit(shore_mask.r, 4.0)), mix(far, back.x, bit(shore_mask.r, 8.0)));
	vec2 into = vec2(corner_radius) - vec2(dx, dy);
	if (into.x > 0.0 && into.y > 0.0) {
		return corner_radius - length(into);
	}
	return min(dx, dy);
}

// 1 when exactly one of a corner's three neighbours is land: the land there is
// a tip poking into the liquid, not a run of coast.
float tip(float side, float other_side, float diagonal) {
	return step(abs(side + other_side + diagonal - 1.0), 0.5);
}

// World pixels to the nearest tip of land among this cell's corners.
float tip_distance(vec2 local) {
	float far = CELL * 2.0;
	vec2 back = CELL - local;
	float north = bit(shore_mask.r, 1.0);
	float south = bit(shore_mask.r, 2.0);
	float west = bit(shore_mask.r, 4.0);
	float east = bit(shore_mask.r, 8.0);
	float d = far;
	d = min(d, mix(far, length(local), tip(north, west, bit(shore_mask.g, 1.0))));
	d = min(d, mix(far, length(vec2(back.x, local.y)), tip(north, east, bit(shore_mask.g, 2.0))));
	d = min(d, mix(far, length(vec2(local.x, back.y)), tip(south, west, bit(shore_mask.g, 4.0))));
	d = min(d, mix(far, length(back), tip(south, east, bit(shore_mask.g, 8.0))));
	return d;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a < 0.01) {
		discard;
	}
	float warm = lava_mix;   // 1 on a lava tile, 0 on water -- from data.liquid, not pixels
	// World-space (camera-independent), matched to the old screen-space frequency.
	vec2 p = world_pos * 0.08;
	float t = pinned_time >= 0.0 ? pinned_time : TIME;

	// Water: the darker moving ripple bands only. (A brighter scrolling caustic
	// streak used to ride on top but read as distracting, so it's gone.)
	float ripple = sin(p.x * 1.3 + p.y * 0.7 + t * water_speed)
		+ sin(p.x * 0.6 - p.y * 1.1 - t * water_speed * 0.7);
	vec3 water = base.rgb + 0.14 * ripple * vec3(0.3, 0.6, 1.0);

	// Lava: strong glow pulse plus moving hot cracks pushing toward yellow.
	float flow = sin(p.x * 0.8 + t * lava_speed) + sin(p.y * 1.2 - t * lava_speed * 0.8);
	float pulse = 0.5 + 0.5 * sin(t * lava_speed * 1.5 + (p.x + p.y) * 0.4);
	// CLAMP, not max(): flow*0.5+0.5 reaches 1.5, so pow(_,3) spiked hot to ~3.4 and the
	// yellow additive below blew past 1.0 into a bloom-amplified yellow oval. Capped at 1.0.
	float hot = pow(clamp(flow * 0.5 + 0.5, 0.0, 1.0), 3.0);
	// Glow in the tile's OWN colour (brightened toward white-hot at the cracks) rather
	// than a baked orange, so recolouring a lava tile's art recolours its lava. An
	// orange lava sheet still reads orange; a red/purple/green one reads in that hue.
	vec3 lava = base.rgb
		+ 0.24 * pulse * base.rgb
		+ 0.28 * hot * mix(base.rgb, vec3(1.0), 0.6);

	vec3 colour = mix(water, lava, warm);
	if (shore_mask.r + shore_mask.g > 0.5) {
		vec2 snapped = (floor(world_pos / shore_pixel) + 0.5) * shore_pixel;
		vec2 local = snapped - floor(world_pos / CELL) * CELL;
		float sides = side_distance(local);
		float tips = tip_distance(local);
		// The coast itself is still: the lip is cut from noise with no TIME in it,
		// and slow noise, so it steps a pixel out in long runs rather than teeth.
		// It never runs out past a tip of land, which would lengthen the tip.
		float lip_reach = has_lip * lip_depth * smoothstep(0.4, 0.6, noise(snapped * 0.03 + 5.3))
			* smoothstep(shore_pixel, shore_pixel * 3.0, tips);
		// A cell between two kinds of ground has no lip colour, so its rounded
		// corners stay water.
		float coast = mix(max(sides, 0.001), sides - lip_reach, has_lip);
		// A tip in the diagonal cell is the nearest land there.
		coast = min(coast, max(tips, 0.001));
		// Two moving noises: one frays the foam, one staggers the waves along the
		// shore so no two stretches of beach move together.
		float fray = noise(snapped * 0.11 + vec2(t * 0.2, -t * 0.13));
		float stagger = noise(snapped * 0.025 + 17.0);

		// Shallows in three flat bands, lighter and greener toward the shore.
		float shallow = floor((1.0 - clamp(coast / shore_reach, 0.0, 1.0)) * 3.0 + 0.5) / 3.0;
		water = mix(water, water * 1.15 + vec3(0.05, 0.15, 0.13), shallow * 0.6);
		// Foam that laps up the coast and back, and a broken swell rolling in to it.
		float lap = 1.0 + 3.5 * (0.5 + 0.5 * sin(t * 1.7 + stagger * 6.2832));
		float foam = step(coast, lap) * step(0.3, fray);
		float swell_t = fract(t * 0.3 + stagger * 2.0);
		float swell_at = mix(shore_reach, lap, swell_t);
		float swell = step(abs(coast - swell_at), shore_pixel * 0.5) * step(0.45, fray)
			* sin(swell_t * 3.14159);
		water = mix(water, foam_colour, max(foam, swell * 0.6) * foam_strength);

		vec3 lip = lip_colour * (0.96 + 0.08 * hash(snapped));
		colour = mix(mix(water, lava, warm), lip, step(coast, 0.0));
	}

	COLOR = vec4(scene_lit_colour(colour, SCREEN_UV), base.a);
}
