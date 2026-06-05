shader_type canvas_item;

// Water surface ripple — expanding rings from touch/drag points
// Inspired by classic water ripple effects (SM64 portal style)

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float aspect_ratio;

// Up to 6 active ripple sources
uniform vec2 ring_centers[6];
uniform float ring_ages[6];    // Time since each ring spawned (negative = inactive)
uniform int active_rings;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 total_offset = vec2(0.0);

    for (int i = 0; i < 6; i++) {
        if (i >= active_rings) break;
        float age = ring_ages[i];
        if (age < 0.0) continue;

        vec2 diff = uv - ring_centers[i];
        diff.x *= aspect_ratio;
        float dist = length(diff);

        // Ring expands outward over time
        float ring_radius = age * 0.3;  // Expansion speed
        float ring_width = 0.025;       // Thickness of the ring

        // Distance from the expanding ring edge
        float ring_dist = abs(dist - ring_radius);

        // Smooth ring shape
        float ring = smoothstep(ring_width, 0.0, ring_dist);

        // Fade out as ring expands (lifetime ~1.2s)
        float fade = 1.0 - smoothstep(0.0, 1.2, age);
        fade *= fade;  // Quadratic falloff for natural decay

        // Also fade inner rings slightly less (first ring stronger)
        ring *= fade;

        // Second harmonic ring (trailing ripple, weaker)
        float ring2_radius = age * 0.3 - 0.05;
        if (ring2_radius > 0.0) {
            float ring2_dist = abs(dist - ring2_radius);
            float ring2 = smoothstep(ring_width * 0.7, 0.0, ring2_dist);
            ring2 *= fade * 0.5;
            ring += ring2;
        }

        // Radial distortion — push pixels outward along the ring
        vec2 dir = normalize(diff + vec2(0.0001));
        dir.x /= aspect_ratio;
        total_offset += dir * ring * 0.008;
    }

    vec2 displaced_uv = uv + total_offset;
    vec4 color = texture(screen_texture, displaced_uv);

    // Subtle brightness on distorted areas
    float offset_strength = length(total_offset);
    color.rgb += vec3(offset_strength * 2.0);

    COLOR = color;
}
