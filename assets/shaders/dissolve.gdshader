shader_type canvas_item;
// Hit flash + noise dissolve with glowing edge. No textures needed.
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float n = noise(UV * 9.0) * 0.65 + noise(UV * 23.0) * 0.35;
	float t = dissolve * 1.15;
	float edge = smoothstep(t - 0.08, t, n);
	if (dissolve > 0.0) {
		float glow = 1.0 - smoothstep(t, t + 0.08, n);
		c.rgb = mix(c.rgb, edge_color.rgb * 2.0, glow * step(0.001, dissolve));
		c.a *= edge;
	}
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	COLOR = c * COLOR;
}
