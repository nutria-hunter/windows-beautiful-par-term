/*! par-term shader metadata
name: Pipeline Test
author: probe
description: Minimal shader; paints red if the custom-shader pipeline is alive.
version: 1.0.0
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
*/
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(1.0, 0.0, 0.0, 1.0);
}
