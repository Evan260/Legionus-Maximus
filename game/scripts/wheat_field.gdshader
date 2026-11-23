// Frays the edges of the wheat fields: the outline wavers, and over a band inside it the soil gives way to grass and the stalks thin out.
shader_type canvas_item;

#include "res://scripts/wheat_fray.gdshaderinc"

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	COLOR = wheat_at(world, COLOR);
}
