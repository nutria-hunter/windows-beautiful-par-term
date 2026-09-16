/*! par-term shader metadata
name: Milky Way - Astral Rift
author: pi / Codex
description: Procedural pixel-art galactic river, branching dust lanes, clustered starlight and integer parallax.
version: 4.0.0
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
  uniforms:
    iStarDensity: 0.68
    iSkyDensity: 0.055
    iStarGain: 1.0
    iTwinkle: 0.16
    iSparkle: 0.035
    iNearSpeed: 24.0
    iFarSpeed: 7.0
    iSkySpeed: 0.0
    iBandWidth: 0.066
    iBandAngle: 32.0
    iBandCurve: 0.10
    iCoreWidth: 0.22
    iCoreGain: 0.8
    iGlowGain: 0.65
    iCloudAmount: 0.9
    iRiftAmount: 0.9
    iCellNear: 9
    iCellMid: 7
    iCellFar: 6
    iCellSky: 22
    iStarSize: 1
    iMagSize: 1
*/

const float TAU = 6.28318530718;
const float DEG = 0.01745329252;

// ============================================================ controls (16 floats max)
// control slider min=0 max=1.5 step=0.01 label="Band Star Density"
uniform float iStarDensity;
// control slider min=0 max=0.4 step=0.005 label="Sky Star Density"
uniform float iSkyDensity;
// control slider min=0 max=3 step=0.01 label="Star Gain"
uniform float iStarGain;
// control slider min=0 max=1 step=0.01 label="Twinkle"
uniform float iTwinkle;
// control slider min=0 max=0.5 step=0.01 label="Sparkle Cross Chance"
uniform float iSparkle;
// control slider min=0 max=240 step=1 label="Near Speed (px/s)"
uniform float iNearSpeed;
// control slider min=0 max=240 step=1 label="Far Speed (px/s)"
uniform float iFarSpeed;
// control slider min=0 max=60 step=0.5 label="Sky Speed (px/s)"
uniform float iSkySpeed;
// control slider min=0.01 max=0.30 step=0.002 label="Band Thickness"
uniform float iBandWidth;
// control slider min=-80 max=80 step=0.5 label="Band Angle (deg from horizontal, + descends to the right)"
uniform float iBandAngle;
// control slider min=-0.6 max=0.6 step=0.005 label="Band Curve"
uniform float iBandCurve;
// control slider min=0.02 max=0.60 step=0.005 label="Core Width"
uniform float iCoreWidth;
// control slider min=0 max=1.5 step=0.01 label="Core Widening"
uniform float iCoreGain;
// control slider min=0 max=2 step=0.01 label="Glow Gain"
uniform float iGlowGain;
// control slider min=0 max=1 step=0.01 label="Star Clouds"
uniform float iCloudAmount;
// control slider min=0 max=1 step=0.01 label="Great Rift"
uniform float iRiftAmount;

// control int min=4 max=24 step=1 label="Near Cell (px)"
uniform int iCellNear;
// control int min=4 max=24 step=1 label="Mid Cell (px)"
uniform int iCellMid;
// control int min=4 max=24 step=1 label="Far Cell (px)"
uniform int iCellFar;
// control int min=8 max=48 step=1 label="Sky Cell (px)"
uniform int iCellSky;
// control int min=1 max=3 step=1 label="Base Star Size (px)"
uniform int iStarSize;
// control int min=0 max=2 step=1 label="Extra Size from Magnitude"
uniform int iMagSize;

// ============================================================ hashes
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
    float n = hash21(p);
    return vec2(n, hash21(p + n * 37.19));
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm3(vec2 p) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        s += a * vnoise(p);
        p = p * 2.07 + 13.3;
        a *= 0.5;
    }
    return s * 1.1428571;
}


// Screen-space orthonormal coordinates; width is measured in screen heights.
vec2 galactic(vec2 px) {
    float a = clamp(iBandAngle, -80.0, 80.0) * DEG;
    vec2 q = (px - 0.5 * iResolution) / max(iResolution.y, 1.0);
    return vec2(dot(q, vec2(cos(a), sin(a))), dot(q, vec2(-sin(a), cos(a))));
}
float bell(float x) { return exp(-x*x); }

// x: resolved stellar density, y: dust transmission, z: warm core, w: cloud texture.
vec4 field(vec2 px) {
    vec2 q = galactic(px);
    float core = bell((q.x - 0.10) / max(iCoreWidth * 1.8, 0.02));
    float width = max(iBandWidth, 0.001) * (1.0 + iCoreGain * core);
    float bend = iBandCurve * q.x*q.x;
    float warp = (vnoise(vec2(q.x*3.7+17.0, 2.9))-0.5)*0.52;
    float d = (q.y-bend)/width + warp;
    float n = fbm3(vec2(q.x*6.0+21.0, d*2.3+q.x*2.0));
    float fine = vnoise(vec2(q.x*32.0+8.0, d*9.0));
    float lane = 0.17*sin(q.x*8.0+0.8) + (n-0.5)*0.72;
    float fork = lane + 0.48 + 0.20*sin(q.x*5.0-1.0);
    float dust = bell((d-lane)/(0.13+0.19*n));
    dust = max(dust, 0.76*bell((d-fork)/0.12)*(0.35+0.65*core));
    float trans = 1.0-clamp(iRiftAmount,0.0,1.0)*dust;
    float arms = 0.83*bell((d+0.36)/0.53) + 0.54*bell((d-0.42)/0.69);
    float clumps = mix(1.0, 0.22+1.75*smoothstep(0.23,0.79,n), iCloudAmount);
    float density = arms*clumps*trans;
    return vec4(density,trans,core,clamp(n*0.78+fine*0.22,0.0,1.0));
}

// Limited luminous pigments, quantized to actual display levels. No blur or AA.
vec3 clouds(vec2 px) {
    vec2 block = floor(px/2.0)*2.0;
    vec4 f = field(block);
    vec2 q = galactic(block);
    float side = q.y-iBandCurve*q.x*q.x;
    vec3 blue = vec3(0.075,0.14,0.25);
    vec3 violet = vec3(0.19,0.085,0.22);
    vec3 cold = mix(blue,violet,smoothstep(-0.06,0.09,side));
    vec3 warm = vec3(0.30,0.215,0.12);
    vec3 pigment = mix(cold,warm,f.z*(0.40+0.60*f.w));
    float granular = mix(0.42,1.35,step(hash21(block+7.7),f.w));
    float light = f.x*(0.28+0.90*f.z)*granular;
    // Stochastic palette quantization without a repeated Bayer/checkerboard tile.
    vec3 c = pigment*light*iGlowGain;
    c = floor(c*127.5+hash21(block+51.4))/127.5;
    return max(c,vec3(0.0));
}

vec3 starColour(float t) {
    vec3 c = mix(vec3(1.0,0.61,0.32),vec3(1.0,0.92,0.76),smoothstep(0.0,0.35,t));
    return mix(c,vec3(0.66,0.82,1.0),smoothstep(0.45,1.0,t));
}

vec3 starLayer(vec2 px, float speed, float cell, float seed, float band) {
    float slope = tan(clamp(iBandAngle,-80.0,80.0)*DEG);
    vec2 off = floor(vec2(iTime*speed,iTime*speed*slope));
    vec2 ip = floor(px)-off;
    vec2 cid = floor(ip/cell);
    float m = hash21(cid+seed+23.3);
    float sz = min(2.0,float(iStarSize)+step(0.92,m)*float(iMagSize));
    // Reserve a one-pixel margin for optional hard-edged diffraction arms.
    vec2 sp = 1.0+floor(hash22(cid+seed+3.7)*max(cell-sz-1.0,1.0));
    vec2 rel = ip-cid*cell-sp;
    float square = float(rel.x>=0.0 && rel.y>=0.0 && rel.x<sz && rel.y<sz);
    float cross = 0.0;
    if (m>0.975 && hash21(cid+seed+61.7)<iSparkle) {
        cross = float((rel.y==0.0 && rel.x>=-1.0 && rel.x<=sz) ||
                      (rel.x==0.0 && rel.y>=-1.0 && rel.y<=sz))*0.32;
    }
    float mask = max(square,cross);
    if (mask==0.0) { return vec3(0.0); }
    // Evaluate extinction at the star anchor, never at individual sprite pixels.
    vec2 anchor = cid*cell+sp+off;
    vec4 f = vec4(1.0);
    if (band>0.5) { f = field(anchor); }
    float density = mix(iSkyDensity,iStarDensity,band);
    // Continuous coarse modulation creates clusters without visible parent-cell seams.
    float cluster = mix(0.38,1.75,smoothstep(0.30,0.75,vnoise((cid*cell+seed)/83.0)));
    float occupied = step(hash21(cid+seed),min(density*cluster,0.98));
    // Continuous extinction avoids threshold popping as stars cross dust lanes.
    float envelope = mix(1.0,clamp(f.x*1.35,0.0,1.0),band);
    float amp = 0.10+0.90*m*m*m*m;
    float phase = hash21(cid+seed+71.0);
    float tw = 1.0-iTwinkle*(0.5+0.5*sin(iTime*(0.65+phase)+phase*TAU));
    return starColour(hash21(cid+seed+17.9))*amp*tw*mask*occupied*envelope*iStarGain;
}

// Independent per-pixel faint stars allow close pairs and dense unresolved clusters.
// No extra cell neighborhood searches; all points remain single physical pixels.
vec3 pinStars(vec2 px) {
    float slope = tan(clamp(iBandAngle,-80.0,80.0)*DEG);
    vec2 off = floor(vec2(iTime*iFarSpeed*0.43,iTime*iFarSpeed*0.43*slope));
    vec2 p = floor(px)-off;
    float r = hash21(p+913.1);
    if (r>0.075) { return vec3(0.0); }
    vec4 f = field(px);
    float group = vnoise(p/47.0+13.0);
    float on = step(r,0.038*iStarDensity*(0.2+2.0*group*group));
    vec3 tint = mix(vec3(0.36,0.49,0.77),vec3(0.85,0.70,0.46),f.z);
    return tint*on*min(f.x,1.4)*(0.08+0.21*hash21(p+71.1))*iStarGain;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 px = floor(fragCoord);
    vec3 col = clouds(px);
    col += pinStars(px);
    col += starLayer(px,iFarSpeed,float(iCellFar),17.0,1.0)*0.50;
    col += starLayer(px,iNearSpeed*0.58,float(iCellMid),59.0,1.0)*0.72;
    col += starLayer(px,iNearSpeed,float(iCellNear),91.0,1.0);
    col += starLayer(px,iSkySpeed,float(iCellSky),233.0,0.0)*0.82;
    fragColor = vec4(clamp(col*iBrightness,0.0,1.0),1.0);
}
