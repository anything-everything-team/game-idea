// Flat-colored voxel look (GAME_DESIGN.md §13): vertex colors, a subtle darkened
// edge on every block (even across greedy-merged quads), and a tiny per-block tint
// so large surfaces don't look plastic. Works in Forward+ and Compatibility (web).
// Vertex color alpha = 0 marks emissive blocks.
shader_type spatial;
render_mode specular_disabled;

uniform float emission_strength = 3.0;
uniform float edge_darkening = 0.18;
uniform float color_jitter = 0.06;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL; // chunks are never rotated, so model space == world space
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec3 an = abs(world_normal);
	vec3 f = fract(world_pos);
	vec2 face_uv = an.x > 0.5 ? f.yz : (an.y > 0.5 ? f.xz : f.xy);
	vec2 e = min(face_uv, 1.0 - face_uv);
	float edge = smoothstep(0.0, 0.07, min(e.x, e.y));
	vec3 cell = floor(world_pos - world_normal * 0.5);
	float tint = 1.0 + color_jitter * (hash13(cell) * 2.0 - 1.0);
	ALBEDO = COLOR.rgb * tint * mix(1.0 - edge_darkening, 1.0, edge);
	ROUGHNESS = 0.9;
	EMISSION = COLOR.rgb * (1.0 - COLOR.a) * emission_strength;
}
