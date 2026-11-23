shader_type canvas_item;
// Draws the world view as usual, recolouring the armour and cloth pixels of the legion's soldiers by Livery's tiers,
// and drawing the wheat of the row in front over the lower part of a rock standing in a field.

#include "res://scripts/wheat_fray.gdshaderinc"

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
uniform sampler2D wheat_tile : filter_nearest, repeat_enable;

varying vec4 tint;
varying float soldier;
varying float in_wheat;
varying float lift;
varying vec2 world;

vec3 ramp(vec3 a, vec3 b, vec3 c, float l) {
	return l < 0.5 ? mix(a, b, l * 2.0) : mix(b, c, l * 2.0 - 1.0);
}

void vertex() {
	soldier = step(mark * 0.5, COLOR.r);
	tint = COLOR;
	tint.r -= mark * soldier;
	// WorldView._add_in_wheat() marks the green and carries in the blue how far down the row of wheat is moved.
	in_wheat = step(mark * 0.5, COLOR.g);
	lift = floor(COLOR.b / mark) * in_wheat;
	tint.g -= mark * in_wheat;
	tint.b -= mark * lift;
	world = VERTEX;
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
	if (in_wheat > 0.5 && c.a > 0.0) {
		ivec2 size = textureSize(wheat_tile, 0);
		vec4 w = texelFetch(wheat_tile, ivec2(mod(floor(world) - vec2(0.0, lift), vec2(size))), 0);
		vec4 shown = wheat_at(world, w);
		// Dark pixels are the soil between the stalks, where the rock shows through.
		if (shown.a > 0.5 && dot(w.rgb, vec3(0.3, 0.59, 0.11)) > 0.3) {
			c = vec4(shown.rgb, 1.0);
		}
	}
	COLOR = c * tint;
}
