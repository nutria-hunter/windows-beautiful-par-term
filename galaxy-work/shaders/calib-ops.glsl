/*! par-term shader metadata
name: Bench Probe
description: Calibration probe. 1000 sin/cos iterations per pixel with no early exit, so the GPU time is predictable and large.
version: 1.0.0
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
  uniforms:
    iLoops: 0
    iTime: 0.0
*/

// control int min=0 max=2000 step=1 label="Extra Loop Goal"
uniform int iLoops;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float s = 0.0;
    vec2 p = fragCoord * 0.001;
    for (int i = 0; i < 1000; i++) {
        float fi = float(i);
        s += sin(fi * 0.017 + p.x) * cos(fi * 0.023 + p.y) + sin(fi * 0.031 - p.y * 1.7);
    }
    s += float(iLoops) * 0.0;
    fragColor = vec4(vec3(fract(s * 0.001)), 1.0);
}
