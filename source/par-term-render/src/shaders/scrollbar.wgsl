// Scrollbar shader

struct Uniforms {
    position: vec2<f32>,  // Position in NDC
    size: vec2<f32>,      // Size in NDC
    color: vec4<f32>,     // RGBA color
    // Rounded-rect / capsule parameters: the quad's size in pixels, an
    // anti-alias width in pixels, and one unused slot. Working in pixels lets the
    // shader build a true capsule, whose end caps stay circular regardless of the
    // bar's aspect ratio.
    shape: vec4<f32>,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var out: VertexOutput;

    // Generate quad vertices
    let x = f32(vertex_index & 1u);
    let y = f32((vertex_index >> 1u) & 1u);

    // Transform to scrollbar position and size
    let pos = vec2<f32>(
        uniforms.position.x + x * uniforms.size.x,
        uniforms.position.y + y * uniforms.size.y
    );

    out.position = vec4<f32>(pos, 0.0, 1.0);
    out.uv = vec2<f32>(x, y);

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // Capsule in pixel space: a vertical segment inset by half the width, swept by a
    // radius of half the width. Doing this per-axis in normalised units would give an
    // ellipse whose corners differ on x and y; in pixels the caps are true semicircles.
    let size_px = max(uniforms.shape.xy, vec2<f32>(1.0, 1.0));
    let p_px = (in.uv - vec2<f32>(0.5, 0.5)) * size_px;
    let radius = size_px.x * 0.5;
    let half_segment = max((size_px.y - size_px.x) * 0.5, 0.0);
    let d = vec2<f32>(abs(p_px.x), max(abs(p_px.y) - half_segment, 0.0));
    let dist = length(d) - radius;

    // Fade across roughly one pixel so the edge is crisp rather than blurry.
    let aa = max(uniforms.shape.z, 0.5);
    let coverage = 1.0 - smoothstep(-aa, aa, dist);
    let alpha = uniforms.color.a * coverage;

    // Output premultiplied colors for PreMultiplied composite alpha mode
    return vec4<f32>(uniforms.color.rgb * alpha, alpha);
}
