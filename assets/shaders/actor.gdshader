shader_type canvas_item;
// Actor shader: vertex deformation on a subdivided grid mesh (squash/stretch, curved lean,
// breathing, jelly wobble, cape flutter, tilt) + fragment effects (hit flash, rim light,
// progressive wound overlay, darkening, noise dissolve with glowing edge).
// Mesh space: feet at y = 0, top at y = -size.y, x centred.
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

void vertex() {
	vec2 v = VERTEX;
	float h = clamp(-v.y / size.y, 0.0, 1.0);
	float cx = v.x / size.x;
	v.y *= 1.0 - squash;
	v.x *= 1.0 + squash * 0.8 * (0.4 + 0.6 * h);
	float chest = exp(-pow((h - 0.62) / 0.22, 2.0));
	v.x *= 1.0 + breathe * chest;
	v.y -= breathe * size.y * 0.04 * h;
	v.x += (lean * h * h + bend * sin(h * 3.14159)) * size.y;
	v.x += wobble * sin(TIME * wobble_speed + h * 4.0) * h * size.x * 0.045;
	v.y += wobble * cos(TIME * wobble_speed * 1.3 + cx * 5.0) * h * size.y * 0.02;
	float cw = (1.0 - smoothstep(0.06, 0.30, UV.x)) * smoothstep(0.25, 0.75, h);
	v += vec2(sin(TIME * 7.0 + UV.y * 9.0) * 9.0 - 6.0, cos(TIME * 5.0 + UV.y * 7.0) * 5.0) * cw * cape;
	float s = sin(tilt); float c = cos(tilt);
	VERTEX = vec2(c * v.x - s * v.y, s * v.x + c * v.y);
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
