// Drifts the canal water along the canals so it reads as flowing.
shader_type canvas_item;

// How far the water texture has moved, in texture widths, set each frame by WorldView.
uniform vec2 shift = vec2(0.0);

void fragment() {
	COLOR = texture(TEXTURE, UV - shift);
}
