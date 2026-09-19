/*! par-term shader metadata
name: Baked dust
description: Layer baked out of the starbound art for texture reuse.
version: 1.0.0
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
*/

uniform float iStarGain;
uniform float iTwinkle;
uniform float iPixelSize;
uniform float iDrift;

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

vec3 starDust(vec2 fragCoord, vec3 color) {
    float cell=9.0;
    vec2 id=floor(fragCoord/cell);
    float seed=hash21(id+401.0);
    if(seed<0.80) return color;
    vec2 off=floor(vec2(hash21(id+2.3),hash21(id+7.1))*cell);
    vec2 d=mod(fragCoord,cell)-off;
    if(abs(d.x)>0.5 || abs(d.y)>0.5) return color;
    float tw=0.5+0.5*sin(iTime*(0.4+seed*2.2)+seed*40.0);
    vec3 col = seed>0.985 ? vec3(226,206,164)/255.0 : vec3(206,216,232)/255.0;
    return max(color, col*(0.30+0.55*tw)*max(iStarGain,0.4));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 pixel = fragCoord;
    fragColor = vec4(starDust(pixel, vec3(0.0)), 1.0);
}
