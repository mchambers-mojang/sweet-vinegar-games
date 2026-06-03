shader_type canvas_item;

// Neon grid background with ripple warp effect
// Apply to a ColorRect behind the game board

uniform float grid_spacing = 40.0;
uniform float line_thickness = 1.0;
uniform vec4 line_color : source_color = vec4(0.0, 0.6, 0.8, 0.2);
uniform vec4 bg_color : source_color = vec4(0.04, 0.04, 0.1, 1.0);

// Ripple impact uniforms
uniform vec2 impact_pos = vec2(0.5, 0.5);  // UV coords
uniform float impact_time = -10.0;         // negative = no active ripple
uniform float ripple_speed = 2.0;
uniform float ripple_decay = 3.0;
uniform float ripple_amplitude = 8.0;

void fragment() {
	vec2 uv = UV;
	vec2 pixel = uv * vec2(textureSize(TEXTURE, 0));

	// Ripple displacement
	float t = TIME - impact_time;
	if (t > 0.0 && t < 3.0) {
		float dist = distance(uv, impact_pos);
		float wave = sin(dist * 30.0 - t * ripple_speed * 10.0);
		float decay = exp(-t * ripple_decay) * exp(-dist * 5.0);
		vec2 dir = normalize(uv - impact_pos + vec2(0.001));
		uv += dir * wave * decay * ripple_amplitude / vec2(textureSize(TEXTURE, 0));
	}

	// Recalculate pixel position after warp
	pixel = uv * vec2(textureSize(TEXTURE, 0));

	// Grid lines
	float gx = mod(pixel.x, grid_spacing);
	float gy = mod(pixel.y, grid_spacing);

	float line_x = step(gx, line_thickness) + step(grid_spacing - line_thickness, gx);
	float line_y = step(gy, line_thickness) + step(grid_spacing - line_thickness, gy);
	float grid = max(line_x, line_y);

	// Soft glow around lines
	float glow_x = smoothstep(line_thickness * 4.0, 0.0, min(gx, grid_spacing - gx));
	float glow_y = smoothstep(line_thickness * 4.0, 0.0, min(gy, grid_spacing - gy));
	float glow = max(glow_x, glow_y) * 0.3;

	vec4 final_color = bg_color;
	final_color = mix(final_color, line_color, grid * line_color.a);
	final_color = mix(final_color, line_color * 0.5, glow);

	// Intersection brightening
	if (grid > 0.5 && line_x > 0.5 && line_y > 0.5) {
		final_color = line_color * 1.5;
	}

	COLOR = final_color;
}
