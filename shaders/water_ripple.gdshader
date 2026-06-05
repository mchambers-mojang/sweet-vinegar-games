shader_type canvas_item;

// Water displacement effect — smooth wake that follows the drag point
// Looks like dragging a finger through still water

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center;           // Current touch position in UV coords (0-1)
uniform vec2 velocity;         // Drag velocity (normalized direction + speed)
uniform float intensity;       // Distortion strength (0 = off)
uniform float aspect_ratio;    // Width / Height

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 diff = uv - center;
    diff.x *= aspect_ratio;
    float dist = length(diff);

    // Smooth radial falloff — larger, softer area of influence
    float radius = 0.12;
    float falloff = exp(-dist * dist / (radius * radius));

    // Directional wake: displace UVs away from the drag direction
    vec2 wake_dir = normalize(velocity + vec2(0.0001));
    wake_dir.x /= aspect_ratio;

    // Combine drag speed influence with proximity
    float speed = length(velocity);
    float displacement = falloff * intensity * min(speed, 1.0);

    // Push pixels outward from center + slightly along the wake
    vec2 radial_dir = normalize(diff + vec2(0.0001));
    radial_dir.x /= aspect_ratio;
    vec2 push = mix(radial_dir, wake_dir, 0.4) * displacement * 0.02;

    vec2 displaced_uv = uv + push;
    vec4 color = texture(screen_texture, displaced_uv);

    // Subtle refraction highlight near the center
    float highlight = falloff * intensity * speed * 0.03;
    color.rgb += vec3(highlight);

    COLOR = color;
}
