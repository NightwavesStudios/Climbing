shader_type canvas_item;

uniform float wear_strength : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    vec4 base = texture(TEXTURE, UV);

    // Apply wear by darkening
    base.rgb *= (1.0 - wear_strength);

    COLOR = base;
}
