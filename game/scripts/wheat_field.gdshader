// Frays the edges of Gaul's wheat fields: the outline wavers, and over a band inside it the soil gives way to grass and the stalks thin out.
shader_type canvas_item;

// Every field near the screen as x, y, width and height in world pixels.
uniform vec4 fields[32];
uniform int count = 0;
// How far in from the edge the wheat thins, how far the outline wavers, and how round the corners are.
uniform float band = 26.0;
uniform float waver = 15.0;
uniform float corner = 14.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float hash(vec2 p) {
	p = fract(p * vec2(127.31, 311.97));
	p += dot(p, p + 34.53);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Distance from a rectangle with rounded corners, negative inside it.
float box(vec2 p, vec4 r) {
	vec2 q = abs(p - r.xy - r.zw * 0.5) - r.zw * 0.5 + corner;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
}

// A union of shapes that fills in the inside corner of an L-shaped field with a curve.
float blend(float a, float b) {
	float h = clamp(0.5 + 0.5 * (b - a) / corner, 0.0, 1.0);
	return mix(b, a, h) - corner * h * (1.0 - h);
}

void fragment() {
	vec2 p = floor(world) + 0.5;
	float d = 1e4;
	for (int i = 0; i < count; i++) {
		d = blend(d, box(p, fields[i]));
	}
	d += (noise(p / 34.0) - 0.5) * waver * 1.4 + (noise(p / 11.0) - 0.5) * waver * 0.6;
	// Each row of wheat ends at its own place, and the stalks along the top and bottom stand at uneven heights.
	d += (noise(p / vec2(37.0, 5.0)) - 0.5) * waver * 0.9 + (noise(p / vec2(3.0, 29.0)) - 0.5) * waver * 0.4;
	float depth = clamp(-d / (band * (0.55 + 0.9 * noise(p / 61.0 + 7.3))), -1.0, 1.0);
	vec4 c = COLOR;
	float bright = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	// Clumps a few pixels wide and a stalk tall, so the gaps open between stalks rather than through them.
	float clump = hash(floor(p / vec2(3.0, 7.0)));
	float grain = hash(p);
	float keep = depth * 1.3 + (clump - 0.5) * 0.9 + (grain - 0.5) * 0.2 - 0.15;
	// Bare soil goes first, so grass shows between the rows before the wheat itself thins.
	keep += smoothstep(0.22, 0.45, bright) * 0.45 - 0.3 + (noise(p / vec2(9.0, 4.0)) - 0.5) * 0.5;
	c.a *= step(0.0, keep) * step(0.0, depth + 0.02);
	// The outermost stalks are a little greener, as if they ripen later.
	c.rgb = mix(c.rgb, c.rgb * vec3(0.9, 1.0, 0.75), clamp(1.0 - depth * 2.5, 0.0, 1.0) * 0.6);
	COLOR = c;
}
