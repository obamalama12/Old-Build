shader_type spatial;
// Inverted-hull cartoon outline. Used as a material_overlay so any mesh gets a thick ink edge.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.07, 0.04, 0.16, 1.0);
uniform float width = 0.03;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
