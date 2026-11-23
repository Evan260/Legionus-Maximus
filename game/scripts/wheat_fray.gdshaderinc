// How the wheat fields fray at their edges, shared by the field layer and by the wheat drawn over a rock standing in a field.

// Every field near the screen as x, y, width and height in world pixels, in a frame turned through `turn` so fields can lie along a canal.
uniform vec4 fields[32];
uniform int count = 0;
uniform float turn = 0.0;
// How far in from the edge the wheat thins, how far the outline wavers, and how round the corners are.
uniform float band = 26.0;
uniform float waver = 15.0;
uniform float corner = 14.0;
// No wheat is drawn further than this past a field's edge, however far the outline wavers.
uniform float reach = 20.0;
uniform vec3 wheat_tint = vec3(1.0);

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

// The colour the field shows at the world pixel `px` for the wheat tile's colour `c` there, with no alpha where the wheat has frayed away.
vec4 wheat_at(vec2 px, vec4 c) {
	vec2 p = floor(px) + 0.5;
	vec2 turned = mat2(vec2(cos(turn), -sin(turn)), vec2(sin(turn), cos(turn))) * p;
	float d = 1e4;
	for (int i = 0; i < count; i++) {
		d = blend(d, box(turned, fields[i]));
	}
	float edge = d;
	d += (noise(p / 34.0) - 0.5) * waver * 1.4 + (noise(p / 11.0) - 0.5) * waver * 0.6;
	// Each row of wheat ends at its own place, and the stalks along the top and bottom stand at uneven heights.
	d += (noise(p / vec2(37.0, 5.0)) - 0.5) * waver * 0.9 + (noise(p / vec2(3.0, 29.0)) - 0.5) * waver * 0.4;
	float depth = clamp(-d / (band * (0.55 + 0.9 * noise(p / 61.0 + 7.3))), -1.0, 1.0);
	float bright = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	// Clumps a few pixels wide and a stalk tall, so the gaps open between stalks rather than through them.
	float clump = hash(floor(p / vec2(3.0, 7.0)));
	float grain = hash(p);
	float keep = depth * 1.3 + (clump - 0.5) * 0.9 + (grain - 0.5) * 0.2 - 0.15;
	// Bare soil goes first, so grass shows between the rows before the wheat itself thins.
	keep += smoothstep(0.22, 0.45, bright) * 0.45 - 0.3 + (noise(p / vec2(9.0, 4.0)) - 0.5) * 0.5;
	c.a *= step(0.0, keep) * step(0.0, depth + 0.02) * step(edge, reach);
	// The outermost stalks are a little greener, as if they ripen later.
	c.rgb = mix(c.rgb, c.rgb * vec3(0.9, 1.0, 0.75), clamp(1.0 - depth * 2.5, 0.0, 1.0) * 0.6);
	return vec4(c.rgb * wheat_tint, c.a);
}
