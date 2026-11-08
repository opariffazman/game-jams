shader_type spatial;
render_mode unshaded, cull_back;

/** Floor fill color. */
uniform vec3 base_color : source_color = vec3(0.043, 0.043, 0.07);
/** Grid line color. */
uniform vec3 line_color : source_color = vec3(0.1, 0.55, 0.7);
/** World units between grid lines. */
uniform float cell : hint_range(0.25, 4.0, 0.05) = 1.0;
/** Grid line width as a fraction of a cell. */
uniform float line_width : hint_range(0.005, 0.2, 0.005) = 0.03;
/** Grid line strength. */
uniform float line_strength : hint_range(0.0, 1.0, 0.01) = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid = abs(fract(world_pos.xz / cell - 0.5) - 0.5) / fwidth(world_pos.xz / cell);
	float edge = 1.0 - clamp(min(grid.x, grid.y) - line_width * 20.0, 0.0, 1.0);
	ALBEDO = mix(base_color, line_color, edge * line_strength);
}
