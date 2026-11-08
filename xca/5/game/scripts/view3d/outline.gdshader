shader_type spatial;
render_mode cull_front, unshaded, depth_draw_never, skip_vertex_transform;

// Inverted hull with a width in screen pixels, so the outline keeps its weight at any zoom, render scale or
// model size. The hull grows in clip space along the view-space normal.
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float width_px = 3.0;

void vertex() {
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec4 clip = PROJECTION_MATRIX * view_position;
	vec2 direction = view_normal.xy;
	float length_xy = length(direction);
	direction = length_xy > 0.0001 ? direction / length_xy : vec2(0.0);
	clip.xy += direction * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
