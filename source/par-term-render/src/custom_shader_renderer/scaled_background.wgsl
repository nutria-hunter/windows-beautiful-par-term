// Match the existing 384-byte uniform block, without a second CPU upload.
struct Params { values: array<vec4<f32>, 24>, }
@group(0) @binding(0) var background: texture_2d<f32>;
@group(0) @binding(1) var terminal: texture_2d<f32>;
@group(0) @binding(2) var<uniform> params: Params;

@vertex fn vs_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    let p = vec2<f32>(f32((index << 1u) & 2u), f32(index & 2u));
    return vec4<f32>(p * 2.0 - 1.0, 0.0, 1.0);
}
@fragment fn fs_main(@builtin(position) pos: vec4<f32>) -> @location(0) vec4<f32> {
    let size = params.values[0].xy;
    let cell = min(vec2<i32>(pos.xy / size * vec2<f32>(textureDimensions(background))), vec2<i32>(textureDimensions(background)) - 1);
    var color = textureLoad(background, cell, 0);
    let mask = clamp(textureLoad(terminal, vec2<i32>(pos.xy), 0).a, 0.0, 1.0);
    let readability = params.values[22].xy;
    // Match the native path: a configured solid background is not readability-dimmed.
    let solid = step(0.01, params.values[17].w);
    color = vec4<f32>(color.rgb * mix(1.0, max(0.0, 1.0-readability.y), readability.x*mask*(1.0-solid)), color.a);
    return color;
}
