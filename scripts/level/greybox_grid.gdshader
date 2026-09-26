// World-space 1 m grid for greybox geometry, so speed and distances read
// clearly while tuning movement. Tint comes from a per-instance parameter.
shader_type spatial;

instance uniform vec4 tint : source_color = vec4(0.6, 0.6, 0.62, 1.0);
uniform float grid_size = 1.0;
uniform float line_darkness = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p) {
	vec2 coord = p / grid_size;
	vec2 g = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(0.0001));
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	vec3 n = abs(world_normal);
	float line;
	if (n.y >= n.x && n.y >= n.z) {
		line = grid(world_pos.xz);
	} else if (n.x >= n.z) {
		line = grid(world_pos.zy);
	} else {
		line = grid(world_pos.xy);
	}
	ALBEDO = tint.rgb * (1.0 - line * line_darkness);
	ROUGHNESS = 0.9;
}
