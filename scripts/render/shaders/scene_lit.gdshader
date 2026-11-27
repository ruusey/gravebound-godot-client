// The ground and the bodies on it, lit from SceneLighting's light buffer.
shader_type canvas_item;

#include "res://scripts/render/shaders/scene_light.gdshaderinc"

void fragment() {
	COLOR.rgb = scene_lit_colour(COLOR.rgb, SCREEN_UV);
}
