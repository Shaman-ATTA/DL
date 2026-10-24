shader_type canvas_item;
// Skeletal actor shader: same fragment effects as actor.gdshader (hit flash, rim light,
// progressive wounds in UV space, darkening, noise dissolve). No vertex deformation:
// vertices are skinned by Skeleton2D/Bone2D, so wound overlays ride on their bones.
uniform vec2 size = vec2(560.0, 560.0);
uniform float squash = 0.0;
uniform float lean = 0.0;
uniform float bend = 0.0;
uniform float breathe = 0.0;
uniform float wobble = 0.0;
uniform float wobble_speed = 3.0;
uniform float cape = 0.0;
uniform float tilt = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform float rim = 0.6;
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform vec2 rim_dir = vec2(-0.7, -0.7);
uniform sampler2D wound_tex : filter_linear;
uniform float wound1 = 0.0;
uniform float wound2 = 0.0;
uniform float wound3 = 0.0;
uniform vec4 ichor : source_color = vec4(0.7, 0.08, 0.1, 1.0);
uniform float ichor_glow = 0.0;
uniform float darken = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	// progressive wounds: R = cracks (75%), G = cuts (50%), B = gashes + drips (25%)
	vec3 w = texture(wound_tex, UV).rgb;
	float crack = w.r * wound1;
	float cut = w.g * wound2;
	float gash = w.b * wound3;
	col.rgb = mix(col.rgb, col.rgb * 0.3, crack * 0.9);
	col.rgb += ichor.rgb * crack * ichor_glow * 0.9;
	float cut_edge = smoothstep(0.05, 0.35, cut) * (1.0 - smoothstep(0.55, 0.9, cut));
	col.rgb = mix(col.rgb, col.rgb * 0.35, cut_edge * 0.8);
	col.rgb = mix(col.rgb, ichor.rgb * (0.8 + ichor_glow * 0.6), smoothstep(0.35, 0.85, cut));
	float g_in = smoothstep(0.25, 0.8, gash);
	col.rgb = mix(col.rgb, col.rgb * 0.3, smoothstep(0.03, 0.3, gash) * 0.8);
	col.rgb = mix(col.rgb, ichor.rgb * (0.9 + ichor_glow), g_in);
	col.rgb += vec3(0.35) * pow(gash, 10.0);
	col.rgb *= 1.0 - darken;
	// rim light on the side facing the light
	if (rim > 0.0) {
		float a2 = texture(TEXTURE, UV + normalize(rim_dir) * TEXTURE_PIXEL_SIZE * 7.0).a;
		col.rgb += rim_color.rgb * col.a * (1.0 - a2) * rim;
	}
	if (dissolve > 0.0) {
		float n = noise(UV * 9.0) * 0.65 + noise(UV * 23.0) * 0.35;
		float t = dissolve * 1.15;
		float glow = 1.0 - smoothstep(t, t + 0.08, n);
		col.rgb = mix(col.rgb, edge_color.rgb * 2.0, glow);
		col.a *= smoothstep(t - 0.08, t, n);
	}
	col.rgb = mix(col.rgb, flash_color.rgb, flash);
	COLOR = col * COLOR;
}
