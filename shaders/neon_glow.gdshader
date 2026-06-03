shader_type canvas_item;

// Pulsing neon glow outline for cells/panels
// Apply to a ColorRect or Panel overlay

uniform vec4 glow_color : source_color = vec4(0.0, 1.5, 1.5, 1.0);
uniform float glow_width = 3.0;
uniform float pulse_speed = 2.0;
uniform float pulse_min = 0.4;
uniform float pulse_max = 1.0;
uniform float border_width = 1.5;

void fragment() {
	vec2 uv = UV;

	// Distance from edges
	float dx = min(uv.x, 1.0 - uv.x);
	float dy = min(uv.y, 1.0 - uv.y);
	float d = min(dx, dy);

	// Convert to pixel distance
	vec2 pixel_size = TEXTURE_PIXEL_SIZE;
	float d_pixels = d / min(pixel_size.x, pixel_size.y);

	// Pulsing alpha
	float pulse = mix(pulse_min, pulse_max, (sin(TIME * pulse_speed) + 1.0) * 0.5);

	// Sharp border
	float border = smoothstep(border_width + 0.5, border_width - 0.5, d_pixels);

	// Soft glow falloff
	float glow = smoothstep(glow_width + border_width, 0.0, d_pixels) * 0.4;

	float alpha = max(border, glow) * pulse * glow_color.a;

	COLOR = vec4(glow_color.rgb, alpha);
}
