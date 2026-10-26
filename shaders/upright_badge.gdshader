shader_type spatial;
render_mode unshaded, cull_disabled;

// The physical rounded label stays attached to its roof/pallet. Only the ink
// inside it is turned upright for the current camera. MODEL_MATRIX includes a
// MultiMesh instance transform, so all parked badges can share one material.
uniform sampler2D plate_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D glyph_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec2 glyph_right_uv;

void vertex() {
    vec3 local_u = normalize(MODEL_MATRIX[0].xyz);
    vec3 local_v = normalize(MODEL_MATRIX[2].xyz);
    vec3 camera_right = normalize(INV_VIEW_MATRIX[0].xyz);
    vec2 right_in_label = vec2(dot(camera_right, local_u), dot(camera_right, local_v));
    float magnitude = length(right_in_label);
    glyph_right_uv = magnitude > 0.0001 ? right_in_label / magnitude : vec2(1.0, 0.0);
}

void fragment() {
    vec2 p = UV - vec2(0.5);
    vec2 down_in_label = vec2(-glyph_right_uv.y, glyph_right_uv.x);
    vec2 ink_uv = vec2(dot(p, glyph_right_uv), dot(p, down_in_label)) + vec2(0.5);
    vec4 plate = texture(plate_texture, UV);
    vec4 ink = texture(glyph_texture, ink_uv);
    ALBEDO = mix(plate.rgb, ink.rgb, ink.a);
    ALPHA = plate.a;
    ALPHA_SCISSOR_THRESHOLD = 0.08;
}
