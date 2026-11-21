// Drifts the canal water along the canals so it reads as flowing.
shader_type canvas_item;

// How far the water texture moves each second, in texture widths.
uniform vec2 drift = vec2(0.0);

void fragment() {
	COLOR = texture(TEXTURE, UV - drift * TIME);
}
