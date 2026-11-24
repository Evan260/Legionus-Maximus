// Draws the grass a steppe fire has reached as burnt: the ground's dips in charcoal and its tufts in grey ash, in a few flat tones,
// with the strip still burning glowing orange, hottest at the front, and embers flickering on it.
shader_type canvas_item;

const vec3 TONES[5] = vec3[5](vec3(0.118, 0.098, 0.09), vec3(0.18, 0.153, 0.137), vec3(0.251, 0.22, 0.196), vec3(0.36, 0.33, 0.302), vec3(0.47, 0.44, 0.40));
const vec3 GLOW = vec3(0.95, 0.36, 0.07);
const float EMBER_STEP = 11.0;
// The ground's lightness that turns to the darkest and the lightest tone.
uniform float lo = 0.43;
uniform float hi = 0.62;
// The fire's starting edge, the way it spreads and the way across it, and how far from that edge it has burnt out and spread.
uniform vec2 origin;
uniform vec2 spread = vec2(1.0, 0.0);
uniform vec2 across = vec2(0.0, -1.0);
uniform vec2 span;
// How far the burning strip's back edge strays from the true one, as WorldView.ragged_band() frays an edge.
uniform float reach = 3.0;

varying vec2 world;
varying vec4 tint;

void vertex() {
	world = VERTEX;
	tint = COLOR;
}

// The same wave as WorldView._wave() for the back edge of a band (edge 3) that does not move with time.
float back_wave(float along) {
	return 0.6 * sin(along * 0.31 + 3.0 * 1.7) + 0.4 * sin(along * 0.83 + 3.0 * 0.9);
}

void fragment() {
	vec4 g = texture(TEXTURE, UV);
	float l = dot(g.rgb, vec3(0.299, 0.587, 0.114));
	int i = min(int(clamp((l - lo) / (hi - lo), 0.0, 1.0) * 5.0), 4);
	vec3 c = TONES[i];
	vec2 off = world - origin;
	float a = dot(off, spread);
	float b = dot(off, across);
	if (a >= span.x - min(reach, (span.y - span.x) / 6.0) * back_wave(b)) {
		float hot = clamp(1.0 - (span.y - a) / 30.0, 0.0, 1.0);
		c = mix(c, GLOW, 0.28 + 0.14 * hot);
		vec2 cell = floor(world / EMBER_STEP);
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec2 at = cell * EMBER_STEP + floor(vec2(fract(h * 7.31), fract(h * 3.17)) * (EMBER_STEP - 2.0));
		vec2 px = floor(world);
		if (px.y == at.y && (px.x == at.x || (h > 0.66 && px.x == at.x + 1.0))) {
			float flicker = 0.5 + 0.5 * sin(TIME * (3.0 + floor(h * 5.0)) + h * 13.0);
			c = mix(c, flicker > 0.75 ? vec3(1.0, 0.82, 0.3) : vec3(0.95, 0.38, 0.08), 0.45 + 0.5 * flicker);
		}
	}
	COLOR = vec4(c * tint.rgb, tint.a * g.a);
}
