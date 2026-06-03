shader_type canvas_item;

// Screen-space shockwave distortion
// Warps pixels radially outward as a ring expands from center

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center;           // Center in UV coords (0-1)
uniform float radius;          // Current ring radius in UV space
uniform float thickness;       // Ring width in UV space
uniform float intensity;       // Distortion strength (fades over time)
uniform float aspect_ratio;    // Width / Height for circular shape

void fragment() {
    vec2 uv = SCREEN_UV;

    // Correct for aspect ratio so the ring is circular
    vec2 diff = uv - center;
    diff.x *= aspect_ratio;
    float dist = length(diff);

    // Distance from the ring edge
    float ring_dist = abs(dist - radius);

    // Smooth falloff within the ring thickness
    float ring = smoothstep(thickness, 0.0, ring_dist);

    // Radial distortion: push pixels outward along the ring
    vec2 dir = normalize(diff);
    // Undo aspect correction for the displacement direction
    dir.x /= aspect_ratio;
    vec2 displaced_uv = uv + dir * ring * intensity * 0.08;

    vec4 color = texture(screen_texture, displaced_uv);

    // Subtle bright edge on the ring front
    float edge = smoothstep(thickness * 0.8, 0.0, ring_dist) * intensity;
    color.rgb += vec3(edge * 0.08);

    COLOR = color;
}
