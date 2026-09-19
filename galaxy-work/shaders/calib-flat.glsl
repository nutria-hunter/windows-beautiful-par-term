/*! par-term shader metadata
name: Calib Flat
description: Floor measurement - one constant per pixel.
version: 1.0.0
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
  uniforms:
    iTime: 0.0
*/

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.05, 0.06, 0.10, 1.0);
}
