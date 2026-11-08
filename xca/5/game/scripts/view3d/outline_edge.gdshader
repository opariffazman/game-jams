shader_type spatial;
render_mode cull_front, unshaded, depth_draw_never;

// Dark edge outside the team ring. It never writes depth and draws before the team ring,
// so the ring always paints over it whatever the view angle.
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);
uniform float thickness = 0.06;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
