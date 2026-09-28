shader_type spatial;
// Soft light beam marking the current objective. A vertical quad that turns
// about its own axis to face the camera, widening with distance so it stays
// visible across the city; brightest at the base, fading up into the sky and
// toward its edges, and fading out close up so it never fills the screen.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;

uniform vec4 beam_color : source_color = vec4(1.0, 0.68, 0.25, 1.0);
uniform float intensity = 1.0;
// Height of the quad mesh (centred on its origin); the node sits at its base.
uniform float height = 90.0;
// Width in metres up close, and the extra width per metre of distance.
uniform float base_width = 1.6;
uniform float width_per_metre = 0.018;
// Metres from the camera over which the beam fades in (near, far).
uniform vec2 near_fade = vec2(6.0, 22.0);

varying float v_across;
varying float v_rise;
varying float v_dist;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	if (length(to_cam) < 0.001) {
		to_cam = vec3(0.0, 0.0, 1.0);
	}
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 base = origin - vec3(0.0, height * 0.5, 0.0);
	float dist = length(CAMERA_POSITION_WORLD - base);
	float w = base_width + dist * width_per_metre;
	vec3 world = origin + right * VERTEX.x * w + vec3(0.0, VERTEX.y, 0.0);
	v_across = VERTEX.x * 2.0;
	v_rise = VERTEX.y / height + 0.5;
	v_dist = length(CAMERA_POSITION_WORLD - world);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float edge = pow(max(1.0 - abs(v_across), 0.0), 2.2);
	float rise = pow(1.0 - clamp(v_rise, 0.0, 1.0), 1.6);
	float near = smoothstep(near_fade.x, near_fade.y, v_dist);
	ALBEDO = beam_color.rgb * edge * (0.08 + 0.92 * rise) * near * intensity;
}
