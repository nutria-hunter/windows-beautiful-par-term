/*! par-term shader metadata
name: DBG dbg-bulge
author: pi
description: Pixel-art tilted spiral galaxy. Hard integer-pixel stars, dithered clouds, dark dust lanes, slow rigid rotation.
version: 1.0.0
safety_badges:
  - battery_friendly
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
  uniforms:
    iCenterX: 0.62
    iCenterY: 0.58
    iScale: 0.46
    iPositionAngle: -25.0
    iInclination: 0.48
    iWinding: 2.6
    iArmWidth: 0.21
    iAsymmetry: 0.45
    iCoreGain: 0.9
    iCloudGain: 0.55
    iDustStrength: 0.78
    iClusterAmount: 0.5
    iStarDensity: 0.5
    iStarGain: 1.0
    iOrbitSpeed: 0.015
    iTwinkle: 0.22
    iCloudPixel: 3
    iPaletteSteps: 8
    iQuality: 1
    iSeed: 7
    iStarCellPx: 7
*/

const float TAU = 6.28318530718;
const float PI  = 3.14159265359;
const float DEG = 0.01745329252;

// ==================================================================== controls
// control slider min=0 max=1 step=0.005 label="Galaxy Center X"
uniform float iCenterX;
// control slider min=0 max=1 step=0.005 label="Galaxy Center Y"
uniform float iCenterY;
// control slider min=0.08 max=1.2 step=0.005 label="Galaxy Scale"
uniform float iScale;
// control slider min=-90 max=90 step=0.5 label="Position Angle (deg)"
uniform float iPositionAngle;
// control slider min=0.12 max=1 step=0.01 label="Inclination (minor/major)"
uniform float iInclination;
// control slider min=0.6 max=6 step=0.02 label="Spiral Winding"
uniform float iWinding;
// control slider min=0.03 max=0.5 step=0.005 label="Arm Width"
uniform float iArmWidth;
// control slider min=0 max=1 step=0.01 label="Arm Asymmetry"
uniform float iAsymmetry;
// control slider min=0 max=2 step=0.01 label="Core Gain"
uniform float iCoreGain;
// control slider min=0 max=2 step=0.01 label="Cloud Gain"
uniform float iCloudGain;
// control slider min=0 max=1 step=0.01 label="Dust Strength"
uniform float iDustStrength;
// control slider min=0 max=1 step=0.01 label="Cluster Amount"
uniform float iClusterAmount;
// control slider min=0 max=1.5 step=0.01 label="Star Density"
uniform float iStarDensity;
// control slider min=0 max=3 step=0.01 label="Star Gain"
uniform float iStarGain;
// control slider min=0 max=0.2 step=0.001 label="Orbit Speed (rad/s)"
uniform float iOrbitSpeed;
// control slider min=0 max=1 step=0.01 label="Twinkle"
uniform float iTwinkle;

// control int min=1 max=8 step=1 label="Cloud Pixel Size"
uniform int iCloudPixel;
// control int min=2 max=10 step=1 label="Palette Steps"
uniform int iPaletteSteps;
// control int min=0 max=2 step=1 label="Quality"
uniform int iQuality;
// control int min=0 max=64 step=1 label="Seed"
uniform int iSeed;
// control int min=5 max=16 step=1 label="Star Cell (px)"
uniform int iStarCellPx;

// ==================================================================== hashes
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

// octaves are driven by iQuality so the cost lever has no extra code path
float fbm(vec2 p, int octaves) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        float use = step(float(i) + 0.5, float(octaves));
        s += a * use * vnoise(p);
        p = p * 2.07 + 13.3;
        a *= 0.5;
    }
    return s * 1.1428571;
}

vec2 rot2(float a) {
    float c = cos(a);
    float s = sin(a);
    return vec2(c, s);
}

vec2 rotv(vec2 v, float a) {
    float c = cos(a);
    float s = sin(a);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// smallest absolute distance on a circle of the given period
float arcDist(float angle, float period) {
    float m = angle - period * floor(angle / period);
    return min(m, period - m);
}

// ==================================================================== transforms
// Screen pixel space is normalised by the screen HEIGHT so the composition does
// not distort with the window aspect ratio.
vec2 screenToDisk(vec2 sx, vec2 ctr, float H, float pa, float ang) {
    vec2 p = (sx - ctr) / H;
    vec2 q = rotv(p, -pa);
    vec2 D = vec2(q.x, q.y / max(iInclination, 0.05));
    return rotv(D, -ang);
}

vec2 diskToScreen(vec2 d, vec2 ctr, float H, float pa, float ang) {
    vec2 D = rotv(d, ang);
    vec2 q = vec2(D.x, D.y * max(iInclination, 0.05));
    vec2 p = rotv(q, pa);
    return p * H + ctr;
}

// ==================================================================== galaxy fields
// The winding is softened near the centre. An unmodified log spiral wraps so
// tightly there that the arms overlap into a filled plate instead of spirals.
float armPhase(float rn, float th) {
    return th - iWinding * log(max(rn, 0.30));
}

// Perpendicular distance to the nearest arm centreline, in normalised-radius units.
float armArc(float rn, float ph) {
    return arcDist(ph, PI) * rn;
}

// Arms fade in above the bulge and fade out at the disk edge, so no flat plate
// of arm light is left behind anywhere.
float armEnvelope(float rn) {
    return smoothstep(0.10, 0.42, rn) * (1.0 - smoothstep(0.92, 1.22, rn));
}

float armProfile(float rn, float ph, float widthScale) {
    float w = iArmWidth * widthScale * (0.55 + 0.95 * rn);
    float arc = armArc(rn, ph);
    return exp(-pow(arc / max(w, 0.004), 2.0)) * armEnvelope(rn);
}

// Analytic (cheap) density used for STAR EXISTENCE. It is a function of the
// star's own disk position, which never changes with time, so stars do not
// switch on and off as the galaxy rotates.
float starDensityAt(vec2 d) {
    float rn = length(d) / max(iScale, 0.02);
    if (rn > 1.35) { return 0.0; }
    float th = atan(d.y, d.x);
    float ph = armPhase(rn, th);
    float armId = step(PI, ph - TAU * floor(ph / TAU));
    float gain = 1.0 - armId * (1.0 - iAsymmetry);
    float arm = armProfile(rn, ph, 1.0) * gain;
    float bulge = exp(-pow(rn / 0.22, 1.5));
    float nucleus = exp(-pow(rn / 0.075, 2.0));
    float d0 = mix(0.45, 1.0, vnoise(d * (11.0 / max(iScale, 0.02))));
    return clamp((arm * 0.95 + bulge * 0.55 + nucleus * 0.9) * d0 * iStarDensity, 0.0, 1.0);
}

// Colour ramps. Outer disk is cyan/blue, the inner disk is champagne gold.
vec3 rampCool(float v) {
    vec3 a = vec3(0.012, 0.024, 0.078);
    vec3 b = vec3(0.045, 0.150, 0.420);
    vec3 c = vec3(0.190, 0.560, 0.760);
    vec3 d = vec3(0.620, 0.930, 0.980);
    vec3 o = mix(a, b, smoothstep(0.06, 0.52, v));
    o = mix(o, c, smoothstep(0.45, 0.80, v));
    o = mix(o, d, smoothstep(0.76, 1.00, v));
    return o;
}

vec3 rampWarm(float v) {
    vec3 a = vec3(0.045, 0.026, 0.036);
    vec3 b = vec3(0.360, 0.215, 0.115);
    vec3 c = vec3(0.850, 0.660, 0.340);
    vec3 d = vec3(1.000, 0.950, 0.815);
    vec3 o = mix(a, b, smoothstep(0.06, 0.52, v));
    o = mix(o, c, smoothstep(0.45, 0.80, v));
    o = mix(o, d, smoothstep(0.76, 1.00, v));
    return o;
}

// ==================================================================== stars
vec3 starColour(float m) {
    vec3 c1 = vec3(1.00, 0.66, 0.42);
    vec3 c2 = vec3(1.00, 0.90, 0.72);
    vec3 c3 = vec3(1.00, 1.00, 0.98);
    vec3 c4 = vec3(0.78, 0.92, 1.00);
    vec3 c = mix(c1, c2, smoothstep(0.00, 0.35, m));
    c = mix(c, c3, smoothstep(0.32, 0.72, m));
    c = mix(c, c4, smoothstep(0.70, 1.00, m));
    return c;
}

// Disk stars live on a grid that rotates rigidly with the galaxy, so a star
// keeps its identity, size and colour. Each candidate is transformed to screen
// space and snapped to a whole pixel, then drawn as an axis-aligned hard square.
vec3 diskStars(vec2 px, vec2 dExact, vec2 ctr, float H, float pa, float ang, float densGate) {
    if (densGate < 0.004) { return vec3(0.0); }

    float incl = max(iInclination, 0.15);
    // Cell width must exceed 2/inclination so that a 3x3 search cannot miss a
    // star whose square overlaps this pixel.
    float cellPx = max(float(iStarCellPx), 2.6 / incl);
    float cs = cellPx / H;

    vec2 cid = floor(dExact / cs);
    float seed = float(iSeed) * 13.0;

    vec3 acc = vec3(0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = cid + vec2(float(i), float(j));
            vec2 rnd = hash22(c + seed);
            vec2 dStar = (c + rnd) * cs;

            vec2 sPos = diskToScreen(dStar, ctr, H, pa, ang);
            vec2 tl = floor(sPos);

            vec2 rel = px - tl;
            float occ = hash21(c + seed + 3.1);
            float m = hash21(c + seed + 23.3);
            float sz = 1.0 + step(0.88, m);
            float inside = step(0.0, rel.x) * step(rel.x, sz - 0.5)
                         * step(0.0, rel.y) * step(rel.y, sz - 0.5);

            float amp = pow(m, 2.6);
            float a = (0.28 + 0.72 * amp) * step(occ, densGate);
            acc += starColour(clamp(m * 0.7 + hash21(c + seed + 17.9) * 0.3, 0.0, 1.0)) * (a * inside);
        }
    }
    return acc;
}

// Foreground stars: a fixed screen grid with a very slow independent drift.
vec3 foregroundStars(vec2 px, float t, float dens) {
    float cell = 34.0;
    vec2 drift = vec2(floor(t * 1.6), floor(t * 0.5));
    vec2 ipx = px - drift;
    vec2 cid = floor(ipx / cell);
    vec2 inCell = ipx - cid * cell;
    float seed = 411.0 + float(iSeed);

    vec2 sp = floor(hash22(cid + seed) * (cell - 1.0));
    vec2 rel = inCell - sp;
    float inside = step(0.0, rel.x) * step(rel.x, 0.5) * step(0.0, rel.y) * step(rel.y, 0.5);
    float occ = hash21(cid + seed + 3.1);
    float m = hash21(cid + seed + 23.3);
    float amp = pow(m, 2.2);
    float a = (0.30 + 0.70 * amp) * step(occ, dens);
    float tw = mix(1.0, 0.6 + 0.4 * sin(t * 0.7 + m * TAU), iTwinkle);
    return starColour(clamp(m * 0.6 + 0.2, 0.0, 1.0)) * (a * tw * inside);
}

// ==================================================================== compose
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 px = floor(fragCoord);
    float H = max(iResolution.y, 1.0);
    vec2 ctr = vec2(iCenterX, iCenterY) * iResolution;
    float pa = radians(iPositionAngle);
    float ang = iOrbitSpeed * iTime;

    // Clouds are evaluated on a coarse block grid: that is what gives the
    // chunky dithered faces instead of a smooth airbrush.
    float blk = float(iCloudPixel);
    vec2 qpx = (floor(px / blk) + 0.5) * blk;
    vec2 dC = screenToDisk(qpx, ctr, H, pa, ang);

    float rn = length(dC) / max(iScale, 0.02);
    float th = atan(dC.y, dC.x);
    float ph = armPhase(rn, th);
    float along = log(max(rn, 0.075));

    int oct = 2 + iQuality;

    vec3 col = vec3(0.0);

    if (rn < 1.45) {
        // ---- arm identity and asymmetry ----
        float armId = step(PI, ph - TAU * floor(ph / TAU));
        float asym = 1.0 - armId * (1.0 - iAsymmetry);

        // ---- low frequency warp so the arms are not perfect spirals ----
        float warp = fbm(vec2(along * 2.2, 7.3 + float(iSeed)), oct) - 0.5;
        float phW = ph + warp * 0.55;

        float armA = armProfile(rn, phW, 1.0) * asym;
        // a third arm appears only in patches
        float armC = armProfile(rn, phW - 1.15, 0.8)
                   * smoothstep(0.42, 0.78, fbm(vec2(along * 3.4, 19.1), oct)) * 0.5;

        // ---- clusters: large-scale clumping along the arms ----
        float clus = mix(1.0, fbm(vec2(along * 6.5, phW * 2.4), oct) * 1.5, iClusterAmount);

        // ---- dust: a lane hugging the inner edge of each arm ----
        float arc = armArc(rn, phW);
        float laneW = 0.045 + 0.075 * rn;
        float lane1 = exp(-pow((arc - 0.085 - 0.10 * rn) / laneW, 2.0));
        float lane2 = exp(-pow((arc - 0.235 - 0.16 * rn) / (laneW * 0.8), 2.0));
        float dustN = fbm(vec2(along * 7.5, phW * 3.1 + 41.0), oct);
        float dust = 1.0 - iDustStrength * clamp(lane1 + 0.6 * lane2, 0.0, 1.0)
                   * smoothstep(0.22, 0.72, dustN);
        // broad gaps that break the arms apart
        float gap = smoothstep(0.60, 0.94, fbm(vec2(along * 3.2, phW * 1.6 + 67.0), oct));
        armA *= 1.0 - 0.80 * gap;
        armC *= 1.0 - 0.80 * gap;

        // ---- bulge and nucleus ----
        float nucleus = exp(-pow(rn / 0.070, 2.0));
        float bulge = exp(-pow(rn / 0.21, 1.45));
        float mottle = mix(0.42, 1.05, fbm(vec2(along * 4.2, th * 2.6), oct));

        float dens = nucleus * 1.30 * iCoreGain
                   + bulge * 0.50 * iCoreGain * mottle
                   + (armA * 0.95 + armC) * iCloudGain * clus;
        dens *= dust;

        // A soft floor stops the faint tails of the arms from being lifted into
        // the first palette step, which used to flatten the disk into a plate.
        float v = smoothstep(0.045, 0.82, clamp(dens, 0.0, 1.4));

        // ---- limited palette + non-repetitive dither ----
        float steps = float(iPaletteSteps);
        float dith = (hash21(px * 1.37 + float(iSeed)) - 0.5) * (0.22 / steps);
        float vq = floor(v * steps + 0.5 + dith * steps) / steps;
        vq = clamp(vq, 0.0, 1.0);

        // ---- inner warm / outer cool ----
        float warm = exp(-pow(rn / 0.36, 1.7));
        vec3 cold = rampCool(vq);
        vec3 hotv = rampWarm(vq);
        col = mix(cold, hotv, warm);

        // faint unresolved glow so the disk is not only quantised steps
col = vec3(bulge * 0.50 * iCoreGain * mottle);
        col = col * iBrightness;
    }

    // ---- stars ----
    float densGate = starDensityAt(screenToDisk(px, ctr, H, pa, ang));
    col += diskStars(px, screenToDisk(px, ctr, H, pa, ang), ctr, H, pa, ang, densGate) * iStarGain;
    col += foregroundStars(px, iTime, 0.075) * iStarGain;

    col = min(col, vec3(1.0)) * iBrightness;
    fragColor = vec4(col, 1.0);
}
