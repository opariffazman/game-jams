shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

// Inverted hull: the back faces grow along the normal, so only a rim shows behind the body.
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float thickness = 0.03;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
