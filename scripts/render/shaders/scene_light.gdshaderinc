// The flat view's light layer (SceneLighting): every light that casts no shadow,
// summed over the screen and divided by the ambient. Albedo times it is exactly what
// those lights would add as Light2Ds, with no ground chunk able to miss one.
uniform sampler2D scene_light : filter_linear, repeat_disable;
uniform bool scene_lit = false;
// The layer holds the light over this, so no colour drawn into it passes 1.
uniform float scene_light_range = 8.0;

vec3 scene_lit_colour(vec3 albedo, vec2 screen_uv) {
	if (!scene_lit) {
		return albedo;
	}
	return albedo * (1.0 + texture(scene_light, screen_uv).rgb * scene_light_range);
}
