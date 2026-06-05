shader_type canvas_item;

// Water-like ripple distortion at a touch point
// Creates concentric rings that expand and fade from the touch position

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center;           // Touch position in UV coords (0-1)
uniform float time;            // Time since touch started
uniform float intensity;       // Distortion strength (fades as finger moves)
uniform float aspect_ratio;    // Width / Height

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 diff = uv - center;
    diff.x *= aspect_ratio;
    float dist = length(diff);

    // Create multiple concentric rings expanding outward
    float ripple_speed = 0.6;
    float wavelength = 0.03;
    float max_radius = 0.15;

    // Ripple wave pattern
    float wave = sin((dist - time * ripple_speed) / wavelength * TAU) * 0.5 + 0.5;

    // Fade based on distance from center and max radius
    float dist_fade = smoothstep(max_radius, 0.0, dist);

    // Combine wave with fade
    float ripple = wave * dist_fade * intensity;

    // Radial displacement
    vec2 dir = normalize(diff + vec2(0.0001));
    dir.x /= aspect_ratio;
    vec2 displaced_uv = uv + dir * ripple * 0.012;

    vec4 color = texture(screen_texture, displaced_uv);

    // Subtle highlight on wave crests
    color.rgb += vec3(ripple * 0.04);

    COLOR = color;
}
