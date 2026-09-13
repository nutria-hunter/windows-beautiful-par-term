/*! par-term shader metadata
name: Continuum - Pearl Spiral
author: pi / Codex
description: Connected pearlescent spiral disk, curved dust, quiet multicolour integer stars and asynchronous scintillation.
version: 3.0.1
defaults:
  animation_speed: 1.0
  brightness: 1.0
  text_opacity: 1.0
  full_content: false
  auto_dim_under_text: false
  uniforms:
    iCenterX: 0.62
    iCenterY: 0.58
    iScale: 0.53
    iPositionAngle: -25.0
    iInclination: 0.53
    iWinding: 3.3
    iArmWidth: 0.3
    iCoreGain: 0.85
    iCloudGain: 0.66
    iDustStrength: 0.46
    iGasGain: 0.12
    iStarDensity: 0.58
    iStarGain: 0.8
    iSkyDensity: 0.18
    iOrbitSpeed: 0.008
    iTwinkle: 0.6
    iCloudPixel: 4
    iPaletteSteps: 10
    iQuality: 1
    iSeed: 7
    iStarCellPx: 6
*/

const float TAU = 6.28318530718;
const float PI  = 3.14159265359;
const float DEG = 0.01745329252;
// The bulge is measured with a rounder metric than the disk, so the core reads
// as a spheroid sitting in the disk rather than a flat patch of it.
const float CORE_ROUND = 2.10;
const float ARM_ASYM = 0.55;
const float CLUSTER_AMOUNT = 0.60;

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
// control slider min=0 max=2 step=0.01 label="Core Gain"
uniform float iCoreGain;
// control slider min=0 max=2 step=0.01 label="Cloud Gain"
uniform float iCloudGain;
// control slider min=0 max=1 step=0.01 label="Dust Strength"
uniform float iDustStrength;
// control slider min=0 max=1.5 step=0.01 label="Gas Nebula Gain"
uniform float iGasGain;
// control slider min=0 max=1.5 step=0.01 label="Star Density"
uniform float iStarDensity;
// control slider min=0 max=3 step=0.01 label="Star Gain"
uniform float iStarGain;
// control slider min=0 max=0.5 step=0.005 label="Sky Star Density"
uniform float iSkyDensity;
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

// Integer arithmetic makes shared lattice corners identical across GPU backends.
float latticeHash(vec2 p) {
    uvec2 q = uvec2(ivec2(p));
    uint n = q.x * 1597334677u ^ q.y * 3812015801u;
    n = (n ^ (n >> 16u)) * 2246822519u;
    n = (n ^ (n >> 13u)) * 3266489917u;
    n = n ^ (n >> 16u);
    return float(n >> 8u) * (1.0 / 16777216.0);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = latticeHash(i);
    float b = latticeHash(i + vec2(1.0, 0.0));
    float c = latticeHash(i + vec2(0.0, 1.0));
    float d = latticeHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// octaves are driven by iQuality so the cost lever has no extra code path
float fbm(vec2 p, int octaves) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        if (i >= octaves) { break; }
        s += a * vnoise(p);
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
// Screen -> position-angle-aligned face-on axes (inclination not applied yet).
vec2 screenToFaceOn(vec2 sx, vec2 ctr, float H, float pa) {
    vec2 p = (sx - ctr) / H;
    return rotv(p, -pa);
}

// Face-on axes -> rotating disk frame. inclScale > 1 makes the shape rounder.
vec2 faceToDisk(vec2 q, float ang, float inclScale) {
    vec2 D = vec2(q.x, q.y / max(iInclination * inclScale, 0.04));
    return rotv(D, -ang);
}

vec2 screenToDisk(vec2 sx, vec2 ctr, float H, float pa, float ang) {
    return faceToDisk(screenToFaceOn(sx, ctr, H, pa), ang, 1.0);
}

vec2 diskToScreen(vec2 d, vec2 ctr, float H, float pa, float ang) {
    vec2 D = rotv(d, ang);
    vec2 q = vec2(D.x, D.y * max(iInclination, 0.05));
    vec2 p = rotv(q, pa);
    return p * H + ctr;
}


// All morphology lives in Cartesian disk coordinates. No angular noise seam.
float armPhase(float rn, float th) {
    return th - iWinding * log(sqrt(rn*rn + 0.025));
}
float armEnvelope(float r) {
    return smoothstep(0.06,0.23,r)*(1.0-smoothstep(0.72,1.38,r));
}
float bell(float x) { return exp(-x*x); }

// x: broken arms, y: transmission, z: compact nurseries, w: cloud grain.
vec4 structureAt(vec2 p) {
    float r=length(p);
    float th=atan(p.y,p.x);
    vec2 seed=vec2(float(iSeed)*1.73,11.9);
    float n=vnoise(p*5.7+seed);
    float f=vnoise(p*19.0+seed+31.0);
    float ph=armPhase(r,th)+(n-0.5)*0.20;
    float w=max(iArmWidth*(0.43+0.55*r)*(0.65+0.85*n),0.006);
    float dist=sin(ph)*r;
    float asym=0.73+0.27*cos(ph);
    float spine=bell(dist/w)*asym;
    // Discontinuous side branches have a different pitch, not parallel rings.
    float branchPh=ph+0.48+0.8*r+(f-0.5)*0.23;
    float branch=bell(sin(branchPh)*r/(w*0.55))
                *smoothstep(0.40,0.72,n)*(1.0-smoothstep(0.9,1.3,r));
    float islands=0.68+0.65*smoothstep(0.22,0.79,n);
    islands*=0.80+0.32*smoothstep(0.23,0.76,f);
    float arms=(spine*islands+branch*0.58)*armEnvelope(r);
    float edge=sin(ph+0.15+(f-0.5)*0.17)*r;
    float lane=bell(edge/(0.015+0.032*r+0.028*n));
    float fork=bell((edge-0.055-0.07*n)/(0.012+0.023*r))
              *smoothstep(0.36,0.68,f);
    float dust=1.0-iDustStrength*clamp(lane*0.90+fork*0.55,0.0,1.0)
              *smoothstep(0.20,0.64,n);
    float knots=smoothstep(0.48,0.79,f)*smoothstep(0.40,0.73,n)
               *spine*armEnvelope(r);
    return vec4(arms,dust,knots,f);
}

float starDensityAt(vec2 d) {
    vec2 p=d/max(iScale,0.02);
    float r=length(p);
    if(r>1.45) { return 0.0; }
    vec4 s=structureAt(p);
    float central=bell(r/0.23);
    return clamp((s.x*0.38+s.z*1.3+central*0.30)*s.y*iStarDensity,0.0,0.97);
}

// Colour ramps. Outer disk is cyan/blue, the inner disk is champagne gold.
vec3 rampCool(float v) {
    vec3 a = vec3(0.0);
    vec3 b = vec3(0.045, 0.150, 0.420);
    vec3 c = vec3(0.190, 0.560, 0.760);
    vec3 d = vec3(0.620, 0.930, 0.980);
    vec3 o = mix(a, b, smoothstep(0.06, 0.52, v));
    o = mix(o, c, smoothstep(0.45, 0.80, v));
    o = mix(o, d, smoothstep(0.76, 1.00, v));
    return o;
}

vec3 rampWarm(float v) {
    vec3 a = vec3(0.0);
    vec3 b = vec3(0.420, 0.290, 0.180);
    vec3 c = vec3(0.900, 0.790, 0.590);
    vec3 d = vec3(1.000, 0.975, 0.910);
    vec3 o = mix(a, b, smoothstep(0.06, 0.52, v));
    o = mix(o, c, smoothstep(0.45, 0.80, v));
    o = mix(o, d, smoothstep(0.76, 1.00, v));
    return o;
}

// ==================================================================== stars

vec3 starColour(float t) {
    vec3 warm=vec3(1.0,0.69,0.42);
    vec3 pearl=vec3(1.0,0.94,0.83);
    vec3 ice=vec3(0.64,0.80,1.0);
    vec3 lilac=vec3(0.82,0.72,1.0);
    vec3 c=mix(warm,pearl,smoothstep(0.0,0.35,t));
    c=mix(c,ice,smoothstep(0.48,0.82,t));
    return mix(c,lilac,smoothstep(0.88,1.0,t));
}

float scintillation(vec2 id, float t) {
    float h=hash21(id+41.7);
    float rate=mix(0.35,1.55,hash21(id+57.1));
    float phase=h*TAU;
    float wave=0.5+0.5*sin(t*rate+phase);
    float slow=0.5+0.5*sin(t*rate*0.37+phase*2.3);
    float depth=mix(0.12,0.58,hash21(id+81.4));
    // Mostly calm; a few stars have a deeper but smooth crest. Never disappear.
    float envelope=0.72*wave+0.28*slow;
    return 1.0-iTwinkle*depth*(1.0-envelope*envelope);
}

// Disk stars live on a grid that rotates rigidly with the galaxy, so a star
// keeps its identity, size and colour. Each candidate is transformed to screen
// space and snapped to a whole pixel, then drawn as an axis-aligned hard square.
vec3 diskStars(vec2 px, vec2 dExact, vec2 ctr, float H, float pa, float ang, float densGate) {
    if (length(dExact) > iScale*1.46 + 0.02) { return vec3(0.0); }

    float incl = max(iInclination, 0.05);
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
            float sz = 1.0 + step(0.94, m);
            float inside = step(0.0, rel.x) * step(rel.x, sz - 0.5)
                         * step(0.0, rel.y) * step(rel.y, sz - 0.5);

            if (inside < 0.5) { continue; }
            float occupancy = starDensityAt(dStar);
            if (occupancy <= 0.0) { continue; }
            float amp = pow(m, 2.6);
            float a = (0.10 + 0.72 * amp) * step(occ, occupancy);
            float tw = scintillation(c + seed, iTime);
            acc += starColour(hash21(c + seed + 17.9)) * (a * tw * inside);
        }
    }
    return acc;
}

// Static background stars. Positions are fixed integer pixels on a screen grid
// and nothing drifts; each star only pulses, with its own phase and period, so
// the sky twinkles without ever moving. Hard 1x1 / 2x2 squares, no AA.
vec3 skyStars(vec2 px, float t, float dens, float cell, float seedOff, float brightScale) {
    vec2 cid = floor(px / cell);
    vec2 inCell = px - cid * cell;
    float seed = seedOff + float(iSeed);

    float occ = hash21(cid + seed);
    float m = hash21(cid + seed + 23.3);
    float sz = 1.0 + step(0.93, m);
    vec2 sp = floor(hash22(cid + seed + 3.7) * (cell - sz + 1.0));
    vec2 rel = inCell - sp;
    float inside = step(0.0, rel.x) * step(rel.x, sz - 0.5)
                 * step(0.0, rel.y) * step(rel.y, sz - 0.5);

    float amp = pow(m, 2.4);
    float a = (0.10 + 0.76 * amp) * brightScale * float(occ < dens);

    float tw = scintillation(cid + seed, t);
    return starColour(hash21(cid + seed + 17.9)) * (a * tw * inside);
}

// Quantization changes luminance; hue is chosen separately to retain violet/gold.
vec3 pigment(float light, float gold, float ice) {
    float steps=max(float(iPaletteSteps),2.0);
    float v=clamp(light,0.0,1.4);
    v=v/(1.0+0.36*v);
    v=floor(v*steps+0.25)/steps;
    vec3 violet=mix(vec3(0.18,0.095,0.36),vec3(0.58,0.38,0.79),v);
    vec3 azure=mix(vec3(0.10,0.23,0.40),vec3(0.45,0.78,0.91),v);
    vec3 amber=mix(vec3(0.67,0.39,0.18),vec3(1.0,0.85,0.55),smoothstep(0.05,0.60,v));
    vec3 c=mix(mix(violet,azure,ice),amber,clamp(gold,0.0,1.0));
    c=mix(c,vec3(1.0,0.94,0.79),smoothstep(0.68,1.0,v)*gold);
    return c*v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 px=floor(fragCoord);
    float H=max(iResolution.y,1.0);
    vec2 ctr=vec2(iCenterX,iCenterY)*iResolution;
    float pa=radians(iPositionAngle);
    float ang=iOrbitSpeed*iTime;
    float blk=max(float(iCloudPixel),1.0);
    vec2 qpx=(floor(px/blk)+0.5)*blk;
    vec2 qC=screenToFaceOn(qpx,ctr,H,pa);
    vec2 dC=faceToDisk(qC,ang,1.0);
    vec2 p=dC/max(iScale,0.02);
    float r=length(p);
    vec3 col=vec3(0.0);

    if(r<1.45) {
        vec4 st=structureAt(p);
        int oct=clamp(iQuality+1,1,3);
        float cloud=fbm(p*23.0+float(iSeed)+7.3,oct);
        float fine=fbm(p*64.0+19.4,oct);
        float ph=armPhase(r,atan(p.y,p.x));
        float fade=1.0-smoothstep(0.78,1.35,r);
        // The continuous disk is the missing material between the two main arms.
        // It fades radially; it is never multiplied by an angular mask.
        float disk=exp(-pow(r/0.67,1.7))*fade;
        float broad=0.52+0.48*bell(sin(ph)*1.7);
        float spiral=st.x*(0.64+0.65*cloud);
        float secondary=bell(sin(ph+0.82)*r/0.17)*armEnvelope(r)*0.18;
        float dust=0.70+0.30*st.y;
        float material=(disk*(0.23+0.17*cloud)*broad+spiral*0.60+secondary)*iCloudGain;
        material*=dust;
        // Curved filaments remain inside the disk instead of a straight cross-axis cut.
        float innerDust=1.0-iDustStrength*0.36*bell(sin(ph+0.24)*r/0.045)
                        *smoothstep(0.07,0.22,r)*(0.45+0.55*cloud);
        float nucleus=bell(r/0.083);
        float bulge=exp(-pow(r/0.29,1.55));
        float core=(nucleus*0.75+bulge*(0.30+0.20*cloud))*iCoreGain;
        float energy=(material+core)*innerDust*(0.83+0.50*fine);
        float warm=exp(-pow(r/0.47,1.65));
        float rose=bell((r-0.47)/0.23)*(0.4+0.6*cloud);
        vec3 outer=vec3(0.37,0.45,0.88);
        vec3 mauve=vec3(0.76,0.40,0.65);
        vec3 gold=vec3(1.0,0.77,0.48);
        vec3 hue=mix(mix(outer,mauve,rose*0.65),gold,warm);
        hue=mix(hue,vec3(1.0,0.94,0.78),nucleus*0.60);
        // Fine output levels retain the dim disk, while coarse spatial blocks keep hard edges.
        float levels=max(float(iPaletteSteps)*2.0,8.0);
        float grain=(hash21(floor(p*H)+float(iSeed))-0.5)*0.70;
        energy=floor(max(energy,0.0)*levels+0.5+grain)/levels;
        col=hue*max(energy,0.0);
        // Small embedded nurseries are subordinate to the galaxy, never blown-out islands.
        float knots=st.z*(0.25+0.65*smoothstep(0.32,0.75,fine))*iCloudGain;
        col+=mix(vec3(0.51,0.65,0.91),vec3(1.0,0.79,0.57),warm)*knots*0.28;
        col+=outer*disk*(0.16+0.15*cloud)*iGasGain;
        // Background-only highlight compression leaves foreground text and stars separate.
        col=col/(vec3(1.0)+col*0.9);
        col=floor(max(col,vec3(0.0))*255.0+0.5)/255.0;
    }
    vec2 exact=screenToDisk(px,ctr,H,pa,ang);
    col+=diskStars(px,exact,ctr,H,pa,ang,1.0)*iStarGain;
    col+=skyStars(px,iTime,iSkyDensity,23.0,411.0,1.0)*iStarGain;
    col+=skyStars(px,iTime,iSkyDensity*0.45,47.0,907.0,1.3)*iStarGain;
    fragColor=vec4(clamp(col*iBrightness,0.0,1.0),1.0);
}
