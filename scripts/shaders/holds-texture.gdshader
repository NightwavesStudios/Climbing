shader_type canvas_item;

uniform sampler2D grunge_mask;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.5;
uniform float grunge_scale : hint_range(0.1, 5.0) = 2.0;

void fragment() {
    vec4 base = texture(TEXTURE, UV);

    // Sample the grunge mask (scaled for tiling)
    float mask = texture(grunge_mask, UV * grunge_scale).r;

    // Apply wear by darkening
    float wear = mix(1.0, mask, wear_strength);
    base.rgb *= wear;

    COLOR = base;
}
