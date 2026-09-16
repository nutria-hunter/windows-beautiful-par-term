/*! par-term shader metadata
name: Kanagawa - Starbound
author: Codex
description: Flat retro space mural, ink-blue nebula banks, cut-paper planets and quiet pixel stars. Texture-free.
version: 1.0.0
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  uniforms:
    iSceneGain: 0.65
    iStarGain: 0.55
    iTwinkle: 0.65
    iDrift: 0.35
    iNebula: 1.0
    iPixelSize: 8
*/

// control slider min=0 max=1.5 step=0.05 label="Scene Brightness"
uniform float iSceneGain;
// control slider min=0 max=1 step=0.05 label="Star Brightness"
uniform float iStarGain;
// control slider min=0 max=1 step=0.05 label="Twinkle"
uniform float iTwinkle;
// control slider min=0 max=1 step=0.05 label="Star Drift"
uniform float iDrift;
// control slider min=0 max=1.5 step=0.05 label="Nebula"
uniform float iNebula;
// control slider min=3 max=16 step=1 label="Pixel Size"
uniform float iPixelSize;

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise2(vec2 p) {
    vec2 c = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(c), hash21(c + vec2(1,0)), f.x),
               mix(hash21(c + vec2(0,1)), hash21(c + vec2(1,1)), f.x), f.y);
}
// Discrete palette: no bloom, continuous gradients or screen-space dithering.
vec3 ink(float k) {
    if (k < 1.0) return vec3(0.0);
    if (k < 2.0) return vec3(12, 14, 23) / 255.0;
    if (k < 3.0) return vec3(22, 27, 43) / 255.0;
    if (k < 4.0) return vec3(32, 42, 61) / 255.0;
    if (k < 5.0) return vec3(45, 61, 78) / 255.0;
    return vec3(65, 82, 99) / 255.0;
}
vec3 planet(vec2 p, vec2 center, float radius, float kind, vec3 bg) {
    vec2 q = (p - center) / radius;
    float r2 = dot(q,q);
    if (r2 > 1.0) return bg;
    float stripe = floor((q.y + 0.18*q.x + 0.09*sin(q.x*5.0)) * 7.0);
    float detail = noise2(q*5.0 + kind*13.0);
    // A drawn crescent boundary with three flat shades, not a lit 3-D sphere.
    float lightSide = q.x - 0.3*q.y + 0.34;
    vec3 c = vec3(17,21,31)/255.0;
    if (lightSide > -0.10) c = vec3(34,44,60)/255.0;
    if (lightSide > 0.26) c = vec3(54,72,87)/255.0;
    if (lightSide > 0.26 && mod(stripe,4.0)<1.0) c = vec3(74,91,104)/255.0;
    if (lightSide > 0.26 && detail>0.67) c = vec3(62,81,91)/255.0;
    if (kind > 0.5) {
        c = vec3(26,22,31)/255.0;
        if (lightSide > 0.0) c = vec3(66,45,49)/255.0;
        if (lightSide > 0.35) c = vec3(98,69,62)/255.0;
        if (lightSide > 0.35 && detail>0.62) c = vec3(121,88,70)/255.0;
    }
    return c;
}
vec3 ring(vec2 q, vec3 bg) {
    vec2 r = vec2(q.x + 0.72*q.y, q.y - 0.27*q.x);
    float e = length(r/vec2(1.90,0.34));
    if (e < 0.70 || e > 1.0) return bg;
    float band = floor((e-0.70)*35.0);
    if (band == 3.0 || band == 7.0) return bg;
    return mix(vec3(45,58,67),vec3(100,104,89),mod(band,3.0)/2.0)/255.0;
}
vec3 stars(vec2 pixel, float cellSize, float moving) {
    vec2 pos = pixel + vec2(floor(iTime*iDrift*0.30)*moving, 0.0);
    vec2 id = floor(pos/cellSize);
    float seed = hash21(id + 93.1 + moving*51.0);
    vec2 origin = floor(vec2(hash21(id+2.3),hash21(id+7.1))*(cellSize-7.0))+3.0;
    vec2 d = mod(pos,cellSize)-origin;
    float radius = seed>0.985 ? 2.0 : 0.0;
    bool hit = abs(d.x)<0.5 && abs(d.y)<0.5;
    if (radius>0.0) hit = (abs(d.x)<0.5 && abs(d.y)<=radius) || (abs(d.y)<0.5 && abs(d.x)<=radius);
    if (!hit || seed<0.48) return vec3(0);
    float phase = iTime*(0.28+hash21(id+21.0)*0.55)+seed*63.0;
    float pulse = pow(0.5+0.5*sin(phase),3.0);
    float level = floor((0.60+iTwinkle*(pulse-0.35))*5.0)/5.0;
    vec3 color = vec3(163,177,190)/255.0;
    if(seed>0.70) color=vec3(192,166,119)/255.0;
    if(seed>0.86) color=vec3(149,127,166)/255.0;
    return color*max(level,0.12)*iStarGain;
}
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float px = max(floor(iPixelSize),1.0);
    vec2 pixel = floor(fragCoord/px);
    vec2 size = iResolution/px;
    vec2 uv = (pixel+0.5)/size;
    vec2 p = (pixel+0.5)/size.y;
    float aspect = size.x/size.y;
    // Large static ink banks cross the complete canvas, leaving a quiet middle.
    float n = noise2(p*3.0)*0.7 + noise2(p*7.0+11.0)*0.3;
    float wave = 0.72 + 0.13*sin(p.x*3.7) + (n-0.5)*0.23;
    float lower = (uv.y-wave)*8.0;
    float upper = (0.12+0.10*sin(p.x*3.1+1.5)+(n-0.5)*0.22-uv.y)*8.0;
    float bank = max(lower,upper);
    float k = floor(clamp((bank+0.45)*2.3*iNebula,0.0,5.0));
    vec3 color = ink(k);
    // Sparse broken ridges, kept to the outer banks.
    if (k>=2.0 && n>0.59 && mod(floor(bank*8.0),5.0)==0.0) color = ink(k+1.0);
    vec2 center = vec2(aspect*0.81,0.77);
    vec2 q = (p-center)/0.205;
    if (q.y < 0.27*q.x) color=ring(q,color);
    color=planet(p,center,0.205,0.0,color);
    if (q.y >= 0.27*q.x) color=ring(q,color);
    color=planet(p,vec2(aspect*0.18,0.20),0.074,1.0,color);
    color=planet(p,vec2(aspect*0.68,0.48),0.025,0.0,color);
    color*=iSceneGain;
    // Foreground points never paint across the silhouettes of the planets.
    bool empty = length(q)>1.04 && distance(p,vec2(aspect*0.18,0.20))>0.08
        && distance(p,vec2(aspect*0.68,0.48))>0.03;
    if(empty) color=max(color,stars(pixel,17.0,0.0)+stars(pixel,31.0,1.0));
    fragColor=vec4(color*max(iBrightness,0.0),1.0);
}
