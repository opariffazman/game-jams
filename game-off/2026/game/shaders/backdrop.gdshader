shader_type spatial;
render_mode unshaded, cull_disabled;

/** Panel fill color. */
uniform vec3 panel_color : source_color = vec3(0.04, 0.04, 0.065);
/** Cool window strip color. */
uniform vec3 cyan_color : source_color = vec3(0.1, 0.89, 1.0);
/** Hot window strip color. */
uniform vec3 magenta_color : source_color = vec3(1.0, 0.18, 0.53);
/** World units across one panel. */
uniform float panel_width : hint_range(0.5, 8.0, 0.1) = 2.4;
/** World units up one panel. */
uniform float panel_height : hint_range(0.5, 8.0, 0.1) = 3.2;
/** Height in world units where the wall has faded to dark. */
uniform float fade_height : hint_range(4.0, 40.0, 0.5) = 26.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The four walls are axis aligned, so x plus z runs along each of them.
	vec2 cell = vec2((world_pos.x + world_pos.z) / panel_width, world_pos.y / panel_height);
	vec2 id = floor(cell);
	vec2 f = fract(cell);
	float h = hash(id);
	vec3 col = panel_color * (0.6 + 0.9 * hash(id + 7.0));
	float seam = step(f.x, 0.025) + step(f.y, 0.02);
	col += cyan_color * 0.07 * clamp(seam, 0.0, 1.0);
	float lit = step(0.3, h) * step(0.12, f.x) * step(f.x, 0.88);
	float strip = step(0.62, f.y) * step(f.y, 0.68) * lit;
	float tall = step(0.88, h) * step(0.45, f.x) * step(f.x, 0.52) * step(0.1, f.y) * step(f.y, 0.9);
	vec3 neon = h > 0.8 ? magenta_color : cyan_color;
	col = mix(col, neon, clamp(strip + tall, 0.0, 1.0) * 0.9);
	// Horizon band: a magenta glow on the floor line that cools to cyan above it.
	float band = smoothstep(0.0, 0.4, world_pos.y) * (1.0 - smoothstep(0.4, 3.0, world_pos.y));
	col += mix(magenta_color, cyan_color, smoothstep(0.2, 2.6, world_pos.y)) * band * 0.55;
	col *= 1.0 - smoothstep(fade_height * 0.35, fade_height, world_pos.y) * 0.85;
	ALBEDO = col;
}
