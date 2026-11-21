shader_type canvas_item;

// Samples the view as if it were first blown up by whole pixels to prescale times its size and then smoothed down.
uniform vec2 prescale = vec2(1.0);

void fragment() {
	vec2 texel = UV / TEXTURE_PIXEL_SIZE;
	vec2 from_centre = fract(texel) - 0.5;
	vec2 flat_half = 0.5 - 0.5 / prescale;
	vec2 blend = (from_centre - clamp(from_centre, -flat_half, flat_half)) * prescale + 0.5;
	COLOR = texture(TEXTURE, (floor(texel) + blend) * TEXTURE_PIXEL_SIZE);
}
