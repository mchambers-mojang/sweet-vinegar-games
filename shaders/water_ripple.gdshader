shader_type canvas_item;

// Water surface ripple — expanding rings from touch/drag points
// Inspired by classic water ripple effects (SM64 portal style)

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float aspect_ratio;
uniform vec2 viewport_size;    // Viewport dimensions in pixels

// Up to 6 active ripple sources
uniform vec2 ring_centers[6];
uniform float ring_ages[6];    // Time since each ring spawned (negative = inactive)
uniform int active_rings;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 total_offset = vec2(0.0);

    // Convert UV distances to pixels for consistent ring size
    float px_scale = viewport_size.y;

    for (int i = 0; i < 6; i++) {
        if (i >= active_rings) break;
        float age = ring_ages[i];
        if (age < 0.0) continue;

        vec2 diff = uv - ring_centers[i];
        diff.x *= aspect_ratio;
        float dist = length(diff) * px_scale;

        // Ring expands at fixed pixel speed
        float ring_radius = age * 150.0;
        float ring_width = 20.0;  // Wider, softer ring

        // Gaussian-like falloff from ring edge (smooth blend)
        float ring_dist = dist - ring_radius;
        float ring = exp(-(ring_dist * ring_dist) / (ring_width * ring_width));

        // Fade out as ring expands
        float fade = 1.0 - smoothstep(0.0, 1.2, age);
        fade *= fade;

        ring *= fade;

        // Signed displacement — push outward on outer edge, inward on inner
        // This creates a natural water-like refraction
        float signed_ring = sign(ring_dist) * ring;

        // Radial distortion direction
        vec2 dir = normalize(diff + vec2(0.0001));
        dir.x /= aspect_ratio;
        total_offset += dir * signed_ring * 0.006;
    }

    vec2 displaced_uv = uv + total_offset;
    vec4 color = texture(screen_texture, displaced_uv);

    // Very subtle caustic highlight — keeps rings from looking individually outlined
    float offset_strength = length(total_offset);
    color.rgb += vec3(offset_strength * 0.8);

    COLOR = color;
}
