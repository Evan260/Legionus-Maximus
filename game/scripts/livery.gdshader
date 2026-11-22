shader_type canvas_item;
// Draws the world view as usual, recolouring the armour and cloth pixels of the legion's soldiers by Livery's tiers.

uniform bool armour_on = false;
uniform vec3 armour_0;
uniform vec3 armour_1;
uniform vec3 armour_2;
uniform bool cloth_on = false;
uniform vec3 cloth_0;
uniform vec3 cloth_1;
uniform vec3 cloth_2;
uniform float cloth_lift = 1.9;
uniform float mark = 16.0;

varying vec4 tint;
varying float soldier;

vec3 ramp(vec3 a, vec3 b, vec3 c, float l) {
	return l < 0.5 ? mix(a, b, l * 2.0) : mix(b, c, l * 2.0 - 1.0);
}

void vertex() {
	soldier = step(mark * 0.5, COLOR.r);
	tint = COLOR;
	tint.r -= mark * soldier;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float tag = floor(c.a * 255.0 + 0.5);
	if (tag == 253.0 || tag == 254.0) {
		c.a = 1.0;
		if (soldier > 0.5) {
			float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			if (tag == 254.0 && armour_on) {
				c.rgb = ramp(armour_0, armour_1, armour_2, l);
			} else if (tag == 253.0 && cloth_on) {
				c.rgb = ramp(cloth_0, cloth_1, cloth_2, min(1.0, l * cloth_lift));
			}
		}
	}
	COLOR = c * tint;
}
