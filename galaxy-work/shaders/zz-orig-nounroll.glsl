/*! par-term shader metadata
name: Kanagawa - Starbound
author: Codex
description: Flat retro space mural, ink-blue nebula banks, cut-paper planets and quiet pixel stars. Texture-free; banded day/night lighting with a real terminator, restrained lit-limb atmospheres, ring shadows, coast-hugging city lights, eclipses, comets, depth-layered star drifts, breathing nebula banks and fleets that range from a lone squadron to a grand fleet warping in at a distance.
version: 6.1.0
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
    iPixelSize: 4
    iOrbitSpeed: 1.0
    iSurfaceSpeed: 0.35
    iCityFlow: 0.5
    iCityGain: 0.65
    iWarpRate: 1.0
    iShipGain: 0.65
    iRim: 0.5
    iNebulaLife: 0.7
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
// control slider min=0 max=3 step=0.1 label="Planet Orbit"
uniform float iOrbitSpeed;
// control slider min=0 max=1 step=0.05 label="Surface Motion"
uniform float iSurfaceSpeed;
// control slider min=0 max=1 step=0.05 label="City Traffic"
uniform float iCityFlow;
// control slider min=0 max=1 step=0.05 label="City Lights"
uniform float iCityGain;
// control slider min=0 max=3 step=0.1 label="Ship Event Frequency"
uniform float iWarpRate;
// control slider min=0 max=1 step=0.05 label="Ship Event Brightness"
uniform float iShipGain;
// control slider min=0 max=1 step=0.05 label="Atmosphere Rim"
uniform float iRim;
// control slider min=0 max=1 step=0.05 label="Nebula Life"
uniform float iNebulaLife;

const float TAU = 6.28318530718;
// Radius of the city world in the screen units `p` uses (fractions of the viewport height). It is
// named because four places have to agree on it: the body, its atmosphere halo, its orbit
// structures, and the eclipse shadow the moon casts across it.
const float CITY_R = 0.19;
// Every body crosses the sky left to right on a *straight* lane - a tilted orbit read from inside a
// system looks like a line, and a bobbing one only ever read as a wobble - and wraps while it is
// still well off-screen so the loop never shows. `spanScale` stretches the travel path: a small
// factor keeps a body in frame for much of its cycle (the hero world), a large one turns it into a
// rare visitor. The speed is scaled with the span, so on-screen pace is the same for every body.

// Per-fragment painter depth. Lower z is nearer; isolated art previews leave it disabled.
bool depthEnabled=false;
float sceneDepth=1000.0;

// Generic inverse sprite deformation: rotate to object axes, then undo axial scale.
// No screen-grid snapping: an authored 2px cell may rotate/translate across physical pixels.

// A stylized metric wake, not a physical spacetime simulation or screen refraction.
// q is in logical units but callers rasterize in physical 2px cells before rotation.

// Shared 2.5D camera: x/y are scene coordinates, z is positive camera distance.
// Projection, target direction and depth tests all use the same z convention.

// Frozen 3D endpoints: the pulse cannot bend as actors move during its travel.

// Rare flagship ultimate: deterministic probability per encounter, reproducible in tests.



vec2 orbitLane(float aspect, float phase, float rate, float amp, float mid, float spanScale) {
    float span=(aspect+2.0*amp+0.6)*spanScale;
    float start=fract(phase/TAU);
    float x=mod(start+iTime*iOrbitSpeed*rate*0.0022/spanScale, 1.0)*span-(amp+0.2);
    return vec2(x,mid);
}

vec3 depthComposite(vec3 before, vec3 after, float z) {
    if(!depthEnabled) return after;
    if(all(lessThan(abs(after-before),vec3(0.00001)))) return before;
    if(z>sceneDepth) return before;
    sceneDepth=z;
    return after;
}

float illumination(vec2 q, vec2 center) {
    vec2 lamp=vec2(iResolution.x/iResolution.y*0.32,-0.35);
    vec3 light=normalize(vec3(lamp-center,0.42));
    vec3 normal=vec3(q,sqrt(max(0.0,1.0-dot(q,q))));
    return dot(normal,light);
}

float lightBand(float d) {
    if (d < -0.06) return 0.0;
    if (d <  0.06) return 1.0;
    if (d <  0.34) return 2.0;
    if (d <  0.62) return 3.0;
    return 4.0;
}

vec2 bodyLocal(vec2 screen, vec2 center, float radius) {
    float px=max(floor(iPixelSize),1.0);
    vec2 origin=floor(center*iResolution.y);
    return (floor((screen*iResolution.y-origin)/px)+0.5)*px/(iResolution.y*radius);
}

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

float bayer2(vec2 a) { a=floor(a); return fract(a.x/2.0 + a.y*a.y*0.75); }

float bayer4(vec2 a) { return bayer2(0.5*a)*0.25 + bayer2(a); }

vec3 ink(float k) {
    if (k < 1.0) return vec3(0.0);
    if (k < 2.0) return vec3(12, 14, 23) / 255.0;
    if (k < 3.0) return vec3(22, 27, 43) / 255.0;
    if (k < 4.0) return vec3(32, 42, 61) / 255.0;
    if (k < 5.0) return vec3(45, 61, 78) / 255.0;
    return vec3(65, 82, 99) / 255.0;
}

float hexEdge(vec2 v, float r) {
    float d=max(max(abs(v.x),abs(v.x*0.5+v.y*0.8660254)),abs(v.x*0.5-v.y*0.8660254));
    return abs(d-r);
}

vec2 snapPixel(vec2 v) { return floor(v)+0.5; }

vec2 snapFine(vec2 v) { float p=max(floor(iPixelSize),1.0); return floor(v*p)/p; }

vec2 fineLocal(vec2 fragCoord, vec2 center, float px) {
    return (fragCoord-floor(center*px))/px;
}

vec2 placeAt(vec2 fragCoord, vec2 center, float px, float step) {
    return floor(fineLocal(fragCoord,center,px)/step)*step;
}

vec2 chunkLocal(vec2 fragCoord, vec2 center, float px) {
    return placeAt(fragCoord,center,px,0.5);
}

float lodStep(float apparentPx) {
    if(apparentPx > 64.0) return 4.0;
    return 2.0;
}

vec3 shade3(float lit, vec3 base, vec3 hi, vec3 lo) {
    if(lit > 0.28) return hi;
    if(lit < -0.18) return lo;
    return base;
}

float ditherLevel(float v, vec2 pixel, float steps) {
    float x = clamp(v,0.0,1.0)*steps;
    float lo = floor(x);
    float thr = bayer4(pixel)*0.65 + hash21(pixel+3.0)*0.35;
    return (lo + (fract(x) > thr ? 1.0 : 0.0))/steps;
}

vec3 planet(vec2 p, vec2 center, float radius, float kind, vec3 bg, vec2 pixel) {
    vec2 q = bodyLocal(p,center,radius);
    float r2 = dot(q,q);
    // One physical pixel of it, and only a faint cast: the atmosphere is meant to be felt at the
    // edge of a planet, not to outline it. `iRim` scales it and can switch it off entirely.
    float limb = 1.0/(iResolution.y*max(radius,1e-4));
    if (r2 > 1.0 + 2.5*limb) return bg;
    float lightSide = illumination(q,center);
    float band = lightBand(lightSide);
    if (r2 > 1.0) {
        // Outside the disk: the lit limb keeps the atmosphere and the night limb keeps a much
        // fainter one, so an unlit hemisphere still has an edge instead of fading into a blob.
        float halo = lightSide > 0.15 ? (band > 3.0 ? 1.0 : 0.45)
            : (band < 1.0 ? 0.22 : 0.30);
        return max(bg, vec3(34,56,70)/255.0*(iRim*halo));
    }
    float angle=iTime*iSurfaceSpeed*0.018;
    vec2 surface=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*q;
    float ribbons = surface.y + 0.18*surface.x + 0.07*sin(surface.x*5.0)
        + 0.025*sin(surface.x*15.0+surface.y*6.0);
    float stripe = floor(ribbons * 9.0);
    float detail = noise2(surface*5.0 + kind*13.0);
    // Five flat tones per body, read straight off the light band: night, twilight and three day
    // steps. Cloud ribbons, storms and craters ride only on the day side.
    vec3 c;
    if (kind < 0.5) {
        // Gas giant: banded and cool, with one oval storm.
        c = vec3(17,21,31)/255.0;
        if (band > 0.5) c = vec3(27,34,48)/255.0;
        if (band > 1.5) c = vec3(38,50,66)/255.0;
        if (band > 2.5) c = vec3(56,73,88)/255.0;
        if (band > 3.5) c = vec3(74,91,104)/255.0;
        if (band > 2.5 && mod(stripe,4.0)<1.0) c = vec3(74,91,104)/255.0;
        if (band > 2.5 && detail>0.67) c = vec3(62,81,91)/255.0;
        // Long cloud ribbons with discrete breaks and a small oval storm.
        if (band > 2.5 && mod(stripe,7.0)==2.0 && detail>0.35)
            c=vec3(83,101,111)/255.0;
        if (band > 2.5 && mod(stripe,9.0)==5.0)
            c=vec3(42,58,74)/255.0;
        vec2 storm=(surface-vec2(0.43,0.17))/vec2(0.25,0.085);
        float swirl=dot(storm,storm);
        if(band>2.5 && swirl<1.0) c=vec3(91,96,92)/255.0;
        if(band>2.5 && swirl<0.40) c=vec3(47,63,75)/255.0;
    } else if (kind < 1.5) {
        // Rocky desert: warm ochre, cratered.
        c = vec3(26,22,31)/255.0;
        if (band > 0.5) c = vec3(46,34,37)/255.0;
        if (band > 1.5) c = vec3(66,45,49)/255.0;
        if (band > 2.5) c = vec3(98,69,62)/255.0;
        if (band > 3.5) c = vec3(121,88,70)/255.0;
        float land=noise2(surface*12.0+17.0);
        if(band>2.5 && land>0.65) c=vec3(79,53,49)/255.0;
        vec2 crater=surface-vec2(0.40,-0.24);
        float cr=length(crater/vec2(0.23,0.19));
        if(band>2.5 && cr<1.0) c=vec3(135,98,76)/255.0;
        if(band>2.5 && cr<0.70) c=vec3(72,48,46)/255.0;
    } else if (kind < 2.5) {
        // Ice world: pale polar collars and hard fracture lines, the coldest cast in the set.
        c = vec3(15,21,30)/255.0;
        if (band > 0.5) c = vec3(26,36,48)/255.0;
        if (band > 1.5) c = vec3(48,64,78)/255.0;
        if (band > 2.5) c = vec3(78,98,112)/255.0;
        if (band > 3.5) c = vec3(112,134,146)/255.0;
        if(band>0.5 && abs(surface.y)>0.60) c=mix(c, vec3(118,140,152)/255.0, 0.35);
        float crack=abs(surface.y+0.23*surface.x+0.07*sin(surface.x*5.0)-0.26);
        if(band>1.5 && crack<0.018 && surface.x<0.55) c=mix(c, vec3(110,131,145)/255.0, 0.38);
        if(band>2.5 && noise2(surface*11.0+77.0)>0.74) c=vec3(92,116,130)/255.0;
    } else if (kind < 3.5) {
        // Volcanic: basalt plains over dark crust. The fissures glow on the *night* side, which is
        // where a volcanic world actually shows its own light.
        c = vec3(22,14,13)/255.0;
        if (band > 0.5) c = vec3(38,22,18)/255.0;
        if (band > 1.5) c = vec3(58,34,25)/255.0;
        if (band > 2.5) c = vec3(88,50,32)/255.0;
        if (band > 3.5) c = vec3(118,68,38)/255.0;
        float basalt=noise2(surface*8.0+29.0);
        if(band>2.5 && basalt>0.62) c=vec3(64,44,36)/255.0;
        float fissure=abs(fract(surface.x*4.0+surface.y*2.0+noise2(surface*5.0)*1.5)-0.5);
        if(fissure<0.045) c=mix(c, vec3(196,92,44)/255.0, band<0.5 ? 0.60 : 0.35);
        vec2 vent=surface-vec2(-0.35,0.30);
        if(length(vent/vec2(0.26,0.22))<1.0)
            c=mix(c, band<0.5 ? vec3(150,66,34)/255.0 : vec3(126,72,44)/255.0, 0.55);
    } else {
        // Ocean world: deep blue, an archipelago, a bright shelf line and no rings.
        c = vec3(13,22,34)/255.0;
        if (band > 0.5) c = vec3(20,34,50)/255.0;
        if (band > 1.5) c = vec3(32,52,72)/255.0;
        if (band > 2.5) c = vec3(48,74,96)/255.0;
        if (band > 3.5) c = vec3(68,98,120)/255.0;
        float isle=noise2(surface*9.0+13.0);
        if(band>1.5 && isle>0.68) c=mix(c, vec3(96,98,78)/255.0, 0.65);
        else if(band>1.5 && isle>0.58) c=mix(c, vec3(70,86,92)/255.0, 0.45);
        if(band>2.5 && isle>0.74) c=mix(c, vec3(122,120,96)/255.0, 0.55);
    }
    // Each zone gets its own limb treatment: a warm cast on the twilight strip, a bright inner rim on
    // the day limb, and a faint cool rim on the night limb. The warm part is a *dithered* band that
    // fades with the light instead of a drawn line along the terminator (which read as a shadow rule
    // ruled across the disk).
    float warm = ditherLevel(clamp(1.0 - abs(lightSide)*4.0, 0.0, 1.0), pixel, 3.0);
    c = mix(c, vec3(104,74,54)/255.0, 0.22*warm*iRim);
    if (r2 > 1.0 - 2.0*limb) {
        if (band > 3.0) c = mix(c, vec3(83,116,130)/255.0, 0.35*iRim);
        else if (band > 1.5) c = mix(c, vec3(58,80,94)/255.0, 0.30*iRim);
        else c = mix(c, vec3(30,46,60)/255.0, 0.35*iRim);
    }
    return depthComposite(bg,c,clamp(0.30/radius,1.4,8.0));
}

vec3 cityPlanet(vec2 q, vec2 center, vec2 pixel) {
    float light=illumination(q,center);
    float band=lightBand(light);
    float angle=iTime*iSurfaceSpeed*0.009;
    vec2 s=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*q;
    // Build the surface with no reference to the sun: continents, ocean, the shelf line, the cloud
    // deck and later the city plan are all albedo, and the light is applied afterwards as a quantised
    // multiplier. That order is what lets the clouds and coast lines continue across the terminator
    // instead of stopping at it, which is how they read on a real world.
    float land=noise2(s*4.0+9.0);
    // Clouds ride their own drift: a faster spin than the surface plus a latitude shear, so they
    // slide across the continents instead of being painted onto them. A pure rotation in the same
    // frame as the land is why they used to look frozen.
    float cloudSpin=angle*2.4+iTime*iSurfaceSpeed*0.010;
    vec2 sc=mat2(cos(cloudSpin),sin(cloudSpin),-sin(cloudSpin),cos(cloudSpin))*q;
    float cloud=noise2(vec2(sc.x*2.0,sc.y*6.0)+31.0);
    // Settlements hug the coast. The land mask's edge is where a night map of Earth lights up and
    // the interior stays dark, so the lights read as a map instead of an even sprinkle.
    bool nearCoast=abs(land-0.60)<0.06;
    float terrain=noise2(s*7.0+23.0);
    vec3 albedo = land>0.60
        ? mix(vec3(58,64,58)/255.0, vec3(76,80,70)/255.0, step(0.55,terrain))
        : vec3(28,36,48)/255.0;
    if(nearCoast) albedo=mix(albedo, vec3(70,88,100)/255.0, 0.45);
    // Two hard-edged flat tones rather than one soft wash: the threshold is what makes these read as
    // cloud instead of a smear over the continents.
    if(cloud>0.78) albedo=mix(albedo, vec3(91,103,111)/255.0, 0.48);
    else if(cloud>0.64) albedo=mix(albedo, vec3(70,84,96)/255.0, 0.32);
    // Three readable megacities: concentric districts, radial avenues, long links.
    float metropolis=0.0;
    float traffic=0.0;
    // Masks for the daylight pass: the same road plan, drawn as concrete instead of light.
    float mRing=0.0;
    float mSpoke=0.0;
    float mCore=0.0;
    float mLink=0.0;
    for(int j=0;j<3;j++) {
        vec2 hub=vec2(0.40,0.40);
        float radius=0.37;
        if(j==1) {hub=vec2(-0.38,0.20); radius=0.15;}
        if(j==2) {hub=vec2(0.18,-0.53); radius=0.15;}
        vec2 d=(s-hub)/radius;
        float r=length(d);
        float a=atan(d.y,d.x);
        if(r<1.0) {
            float rings=abs(fract(r*6.0)-0.5);
            float spoke=abs(sin(a*6.0))*r;
            // Coherent rings are interrupted by small dark city blocks.
            float lots=hash21(floor(s*95.0));
            if((rings<0.15 && lots>0.18) || spoke<0.035 || r<0.12)
                metropolis=max(metropolis,1.0);
            if(rings<0.15) mRing=1.0;
            if(spoke<0.035) mSpoke=1.0;
            if(r<0.12) mCore=1.0;
            float pulse=0.5+0.5*sin(r*24.0-iTime*iCityFlow*0.65+float(j)*2.0);
            traffic=max(traffic,pulse);
        }
    }
    // Links use Cartesian distance; no angular seam can cut across the planet.
    vec2 roadA=vec2(-0.38,0.20), roadB=vec2(0.40,0.40), roadC=vec2(0.18,-0.53);
    vec2 ab=roadB-roadA, bc=roadC-roadB;
    float dAB=length(s-roadA-ab*clamp(dot(s-roadA,ab)/dot(ab,ab),0.0,1.0));
    float dBC=length(s-roadB-bc*clamp(dot(s-roadB,bc)/dot(bc,bc),0.0,1.0));
    if(min(dAB,dBC)<0.013) {metropolis=1.0; mLink=1.0; traffic=0.5+0.5*sin(dot(s,vec2(29,17))-iTime*iCityFlow);}
    // Smaller settlements support the major silhouettes without filling the disk.
    vec2 lots=floor(s*65.0);
    float seed=hash21(lots+18.0);
    float belt=abs(fract((s.y+0.12*sin(s.x*6.0))*8.0)-0.5);
    float district=noise2(s*11.0+6.0);
    bool road=belt<0.09 && district>(nearCoast ? 0.20 : 0.42);
    bool tower=seed>(nearCoast ? 0.70 : 0.84) && district>0.50;
    // Night lights are collected on their own and added only after the surface has been lit.
    vec3 lights=vec3(0.0);
    if(road || tower || metropolis>0.0) {
        float route=floor(s.y*8.0);
        float signal=0.5+0.5*sin(s.x*26.0-iTime*iCityFlow*0.65+route*2.7);
        if(metropolis>0.0) signal=traffic;
        float trafficLevel=signal>0.85 ? 1.0 : (signal>0.48 ? 0.72 : 0.48);
        // The night hemisphere is a map of light, not a glitter: most of the traffic pulse is
        // replaced by a slow steady glow and the night boost is smaller, so the dark side reads
        // as a lit planet instead of a sparkling blob.
        float steady=0.80+0.20*sin(iTime*iCityFlow*0.16+route*0.9);
        float level=mix(trafficLevel,steady,band<1.5 ? 0.78 : 0.30);
        vec3 neon=vec3(85,151,145)/255.0;
        if(seed>0.72) neon=vec3(158,115,161)/255.0;
        if(seed>0.92) neon=vec3(187,157,102)/255.0;
        if(metropolis>0.0) neon=vec3(194,167,112)/255.0;
        if(band>1.5) {
            // By day the same plan reads as concrete: the core is the brightest surface, ring roads
            // are darker bands, avenues and intercity links are light lines, and every other building
            // is a grey block. That is what makes the city legible with no lights on at all.
            vec3 core=vec3(93,98,92)/255.0;
            vec3 pave=vec3(79,88,91)/255.0;
            vec3 concrete=vec3(92,96,96)/255.0;
            vec3 kerb=vec3(70,74,76)/255.0;
            if(metropolis>0.0) albedo=mix(albedo, mRing>0.5 ? kerb : concrete, 0.70*iCityGain);
            if(mCore>0.5) albedo=mix(albedo, core, 0.65*iCityGain);
            if(mSpoke>0.5) albedo=mix(albedo, pave, 0.70*iCityGain);
            if(mLink>0.5) albedo=mix(albedo, pave, 0.55*iCityGain);
            if(tower) albedo=mix(albedo, vec3(74,83,85)/255.0, 0.35*iCityGain);
            else if(road) albedo=mix(albedo, vec3(66,78,84)/255.0, 0.30*iCityGain);
        } else {
            float night=band<0.5 ? 1.25 : 0.50;
            lights=max(lights, neon*level*night*iCityGain);
        }
    }
    // Quantised lighting of that one surface, dithered so the five steps read as a ramp: the
    // terminator is a soft band of hard pixels, not a drawn edge. The night half keeps a cold cast.
    float lit = band<0.5 ? 0.18 : (band<1.5 ? 0.32 : (band<2.5 ? 0.55 : (band<3.5 ? 0.76 : 1.0)));
    vec3 c = albedo*lit;
    if(light<0.06) c=mix(c, c*vec3(0.78,0.90,1.15), 0.55);
    c=max(c, lights);
    // The same three-zone limb as the natural bodies: a dithered sunset cast, a lit inner rim, and a
    // faint cool rim on the night side so the unlit half keeps its silhouette.
    float rq=dot(q,q);
    float warm = ditherLevel(clamp(1.0 - abs(light)*4.0, 0.0, 1.0), pixel, 3.0);
    c = mix(c, vec3(108,78,56)/255.0, 0.22*warm*iRim);
    if(rq>0.975 && band>1.5) c=mix(c,vec3(58,86,100)/255.0,0.45*iRim);
    if(rq>0.990 && band>3.0) c=mix(c,vec3(76,106,120)/255.0,0.35*iRim);
    if(rq>0.985 && band<1.0) c=mix(c,vec3(30,44,58)/255.0,0.55*iRim);
    return c;
}

vec2 stationPoint(float a) {
    // Same tilted ellipse for the rail and its vehicles.
    vec2 e=vec2(1.52*cos(a),0.42*sin(a));
    return vec2(e.x-0.30*e.y,e.y+0.30*e.x);
}

float segmentDistance(vec2 p, vec2 a, vec2 b) {
    vec2 v=b-a;
    return length(p-a-v*clamp(dot(p-a,v)/dot(v,v),0.0,1.0));
}

vec2 detailLocal(vec2 fragCoord, vec2 center, float radius, float pitch) {
    vec2 origin=floor(center*iResolution.y);
    return (floor((fragCoord-origin)/pitch)+0.5)*pitch/(iResolution.y*radius);
}

vec3 infrastructure(vec2 q, vec2 fine, vec3 bg, float front, float pixelWidth) {
    vec3 dark=vec3(18,23,33)/255.0, plate=vec3(46,57,69)/255.0;
    vec3 edge=vec3(76,85,92)/255.0, gold=vec3(114,104,77)/255.0;
    vec3 teal=vec3(65,103,105)/255.0;
    vec2 e=vec2(q.x+0.30*q.y,q.y-0.30*q.x)/1.09;
    vec2 ef=vec2(fine.x+0.30*fine.y,fine.y-0.30*fine.x)/1.09;
    vec3 c=bg;
    if((e.y>=0.0)==(front>0.5)) {
        vec2 axes=vec2(1.52,0.42);
        float rho=length(e/axes);
        // Convert ellipse implicit distance to screen-normal distance: uniform rail thickness.
        float grad=max(length(e/(axes*axes))/max(rho,0.001),0.001);
        float dist=(rho-1.0)/grad;
        if(abs(dist)<pixelWidth*0.90) c=dark;
        if(dist>pixelWidth*0.05 && dist<pixelWidth*0.60) c=plate;
        float rf=length(ef/axes);
        float df=(rf-1.0)/max(length(ef/(axes*axes))/max(rf,0.001),0.001);
        // One-pixel recessed service rail, never a bright continuous neon outline.
        if(abs(df+pixelWidth*0.30)<pixelWidth*0.125) c=vec3(34,47,58)/255.0;
    }
    for(int j=0;j<3;j++) {
        float a=0.65+float(j)*TAU/3.0;
        vec2 anchor=stationPoint(a), foot=anchor*0.53;
        if((sin(a)>=0.0)!=(front>0.5)) continue;
        if(segmentDistance(fine,foot,anchor)<pixelWidth*0.125) c=plate;
        vec2 d=q-anchor;
        // Armored docking bastion: stepped shoulders, recessed bay, a narrow command deck.
        if(abs(d.x)<0.095 && abs(d.y)<0.034) c=dark;
        if(abs(d.x)<0.065 && abs(d.y)<0.050) c=plate;
        if(abs(d.x)<0.044 && d.y<-0.018 && d.y>-0.039) c=edge;
        if(abs(d.x)<0.054 && abs(d.y)<0.014) c=dark;
        vec2 f=fine-anchor;
        if(abs(f.x)<0.027 && abs(f.y-0.008)<pixelWidth*0.125) c=gold*iCityGain;
        float lift=0.5+0.5*sin(iTime*iCityFlow*0.13+float(j)*2.1);
        vec2 cabin=mix(foot,anchor,lift);
        if(max(abs(q.x-cabin.x),abs(q.y-cabin.y))<pixelWidth*0.50) c=plate;
        if(max(abs(fine.x-cabin.x),abs(fine.y-cabin.y))<pixelWidth*0.125) c=teal*iCityGain;
    }
    for(int j=0;j<3;j++) {
        float a=iTime*iCityFlow*0.022+float(j)*TAU/3.0;
        if((sin(a)>=0.0)!=(front>0.5)) continue;
        vec2 ship=stationPoint(a);
        if(max(abs(q.x-ship.x),abs(q.y-ship.y))<pixelWidth*0.55) c=plate;
        if(max(abs(fine.x-ship.x),abs(fine.y-ship.y))<pixelWidth*0.125) c=teal*iCityGain;
    }
    return c;
}

vec3 ring(vec2 q, vec3 bg, vec2 lightDir) {
    vec2 r = vec2(q.x + 0.72*q.y, q.y - 0.27*q.x);
    float e = length(r/vec2(1.90,0.34));
    if (e < 0.70 || e > 1.0) return bg;
    float band = floor((e-0.70)*65.0);
    if (band == 6.0 || band == 7.0 || band == 14.0) return bg;
    float fleck=hash21(floor(r*95.0));
    float tone=mod(band,4.0)/3.0;
    if(fleck>0.83) tone=max(0.0,tone-0.33);
    // The planet shades its own ring: everything inside the hard shadow cylinder trailing behind
    // it loses most of its light, and that is what makes the ring read as a ring around a sphere
    // instead of a drawn ellipse.
    vec2 anti=-lightDir;
    float along=max(dot(q,anti),0.0);
    if(along>0.0 && length(q-anti*along)<1.02) tone*=0.30;
    return mix(vec3(38,49,60),vec3(100,104,89),tone)/255.0;
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

vec3 stars(vec2 pixel, float cellSize, float driftRate, float boost, float cloud) {
    // Each layer crawls at its own whole-pixel rate, and that is what separates them into depth
    // planes: the far layer never moves, the near one slides fastest. The step is still floored to
    // whole logical pixels, so no layer gains sub-pixel motion.
    vec2 pos = pixel + vec2(floor(iTime*iDrift*0.30*driftRate), 0.0);
    vec2 id = floor(pos/cellSize);
    float seed = hash21(id + 93.1 + driftRate*51.0);
    // `cloud` is the shared density field, computed once per frame by the caller: every layer reads
    // the same voids and drifts, and no layer pays for its own noise sampling.
    if (seed < 0.36 || seed > 0.36 + 1.15*cloud) return vec3(0);
    vec2 origin = floor(vec2(hash21(id+2.3),hash21(id+7.1))*(cellSize-7.0))+3.0;
    vec2 d = mod(pos,cellSize)-origin;
    // Size: four classes, from a single pixel to a wide cross. Assigned per star, so a field holds a
    // few big ones among many small - the thing an even sprinkle cannot do.
    float sizeRoll=hash21(id+13.7);
    float arm = sizeRoll>0.985 ? 2.5*boost : (sizeRoll>0.94 ? 1.5*boost : 0.5);
    bool hit = abs(d.x)<0.5 && abs(d.y)<0.5;
    if (arm>0.9) hit = (abs(d.x)<0.5 && abs(d.y)<=arm) || (abs(d.y)<0.5 && abs(d.x)<=arm);
    if (!hit) return vec3(0);
    // Density drifts in slow clouds, so the field keeps quiet voids and crowded drifts instead of
    // an even sprinkle (see the shared `cloud` parameter).
    // Twinkle: period and depth are per star, so slow steady ones sit next to quick faint ones
    // instead of the whole field breathing in step.
    float rate = 0.10+hash21(id+31.0)*1.30;
    float depth = 0.25+hash21(id+41.0)*0.75;
    float phase = iTime*rate+seed*63.0;
    float pulse = pow(0.5+0.5*sin(phase),3.0);
    // Seven brightness steps down to a barely-there floor, and a wider colour palette.
    float level = floor((0.35+iTwinkle*depth*(pulse-0.35))*7.0)/7.0;
    float hue = hash21(id+53.0);
    vec3 color = vec3(214,224,236)/255.0;              // white
    if(hue>0.86) color=vec3(190,206,238)/255.0;        // pale blue
    else if(hue>0.72) color=vec3(226,206,164)/255.0;   // warm gold
    else if(hue>0.62) color=vec3(232,190,186)/255.0;   // rose
    else if(hue>0.54) color=vec3(196,180,226)/255.0;   // violet
    else if(hue>0.48) color=vec3(174,214,208)/255.0;   // teal
    return color*max(level,0.08)*iStarGain;
}

float transitLifetime(float age, float nominal, float period) {
    float rate=max(iWarpRate,0.0001);
    float untilReset=(period-mod(iTime*rate,period))/rate;
    return max(0.01,min(nominal,age+untilReset-0.01));
}

vec2 cometSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/420.0);
    float seed=hash21(vec2(slot,137.0));
    if(seed<0.38) return vec2(-100.0,seed);
    float delay=30.0+300.0*hash21(vec2(slot,53.0));
    return vec2((mod(clock,420.0)-delay)/iWarpRate,seed);
}

vec3 cometPixel(vec2 fragCoord, vec2 pixel, vec2 size, vec3 color) {
    float px=max(floor(iPixelSize),1.0);
    // `px` cancels in the ratio, so this is the same aspect mainImage works with.
    float aspect=size.x/size.y;
    vec2 ev=cometSchedule(iTime);
    float age=ev.x, seed=ev.y;
    // Duration and tail length vary per event, so a comet is not the same streak every time.
    float life=6.0+6.0*hash21(vec2(seed,23.0));
    life=transitLifetime(age,life,420.0);
    if(age<0.0 || age>life) return color;
    float progress=clamp(age/life,0.0,1.0);
    // Six crossings, chosen by the event seed: horizontal from either side (slightly down or up) and
    // vertical from top or bottom. Entry and exit are given in screen units, so the streak is always
    // framed whichever way it runs.
    float run=hash21(vec2(seed,19.0));
    vec2 start,endp;
    if(run<0.30)      { start=vec2(-0.14,0.05+0.35*hash21(vec2(seed,7.0))); endp=vec2(aspect+0.14,0.55+0.40*hash21(vec2(seed,11.0))); }
    else if(run<0.50) { start=vec2(aspect+0.14,0.05+0.35*hash21(vec2(seed,7.0))); endp=vec2(-0.14,0.55+0.40*hash21(vec2(seed,11.0))); }
    else if(run<0.68) { start=vec2(0.10+0.80*hash21(vec2(seed,7.0)),-0.10); endp=vec2(0.10+0.80*hash21(vec2(seed,11.0)),1.10); }
    else if(run<0.84) { start=vec2(0.10+0.80*hash21(vec2(seed,7.0)),1.10); endp=vec2(0.10+0.80*hash21(vec2(seed,11.0)),-0.10); }
    else              { start=vec2(-0.14,0.75+0.30*hash21(vec2(seed,7.0))); endp=vec2(aspect+0.14,0.02+0.30*hash21(vec2(seed,11.0))); }
    // Extend along the actual travel direction until the complete trail has left the viewport.
    vec2 clearance=normalize(endp-start)*0.50;
    start-=clearance;endp+=clearance;
    vec2 head=snapFine(mix(start,endp,progress)*size.y);
    vec2 dir=normalize(endp-start);   // the same direction in logical pixels (uniform scaling)
    vec2 rel=placeAt(fragCoord,head,px,1.0);
    // A minority of comets are warm rather than icy.
    vec3 spark=hash21(vec2(seed,29.0))>0.72 ? vec3(238,214,178)/255.0 : vec3(232,240,250)/255.0;
    if(abs(rel.x)<1.0 && abs(rel.y)<1.0)
        return max(color,spark*max(iStarGain,0.75));
    // The tail is a chain of whole pixels, not a thin line. A line at an arbitrary angle is re-rasterised
    // on every step of the head, so its edges crawl sideways and the streak shivers; beads that are each
    // snapped to the lattice only ever translate, and a chain of shrinking blocks reads as a comet tail
    // in pixel art anyway.
    vec2 dirPx=normalize(vec2(floor(dir.x*4.0+0.5)*0.25,floor(dir.y*4.0+0.5)*0.25)+vec2(0.0,1e-4));
    float len=30.0+16.0*hash21(vec2(seed,37.0));
    for(int k=1;k<=12;k++) {
        float f=float(k)/12.0;
        vec2 bp=snapFine(head-dirPx*(len*f));
        vec2 dd=placeAt(fragCoord,bp,px,1.0);
        float sz=f<0.18 ? 2.0 : (f<0.45 ? 1.0 : 0.5);
        if(abs(dd.x)>sz || abs(dd.y)>sz) continue;
        vec3 tone = f<0.18 ? vec3(190,214,232)/255.0
            : (f<0.42 ? vec3(128,158,182)/255.0
            : (f<0.70 ? vec3(78,102,128)/255.0 : vec3(44,60,84)/255.0));
        color=max(color,tone*max(iStarGain,0.70)*(1.0-progress*0.35));
    }
    return color;
}

float fleetClass(float seed) {
    float r=hash21(vec2(seed,211.0));
    if(r<0.30) return 0.0;
    if(r<0.82) return 1.0;
    return 2.0;
}

vec2 meteorSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/85.0);
    float seed=hash21(vec2(slot,613.0));
    if(seed<0.45) return vec2(-100.0,seed);
    float delay=6.0+60.0*hash21(vec2(slot,17.0));
    return vec2((mod(clock,85.0)-delay)/iWarpRate,seed);
}

vec3 meteorPixel(vec2 fragCoord, vec2 pixel, vec2 size, vec3 color) {
    float px=max(floor(iPixelSize),1.0);
    float aspect=size.x/size.y;
    vec2 ev=meteorSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=0.55+0.55*hash21(vec2(seed,29.0));
    life=transitLifetime(age,life,85.0);
    if(age>life) return color;
    float progress=age/life;
    // Four crossings, so it does not always cut the same way. Entry and exit are in screen units.
    float run=hash21(vec2(seed,19.0));
    vec2 start,endp;
    if(run<0.34)      { start=vec2(-0.10,0.05+0.40*hash21(vec2(seed,7.0))); endp=vec2(aspect+0.10,0.45+0.45*hash21(vec2(seed,11.0))); }
    else if(run<0.62) { start=vec2(aspect+0.10,0.05+0.40*hash21(vec2(seed,7.0))); endp=vec2(-0.10,0.45+0.45*hash21(vec2(seed,11.0))); }
    else if(run<0.82) { start=vec2(0.10+0.80*hash21(vec2(seed,7.0)),-0.08); endp=vec2(0.10+0.80*hash21(vec2(seed,11.0)),1.08); }
    else              { start=vec2(-0.10,0.70+0.28*hash21(vec2(seed,7.0))); endp=vec2(aspect+0.10,0.06+0.30*hash21(vec2(seed,11.0))); }
    // Extend along the actual travel direction until the complete trail has left the viewport.
    vec2 clearance=normalize(endp-start)*0.50;
    start-=clearance;endp+=clearance;
    vec2 head=snapFine(mix(start,endp,progress)*size.y);
    vec2 dir=normalize(endp-start);
    vec2 rel=placeAt(fragCoord,head,px,1.0);
    // Head: a single logical pixel, brighter than anything else in the sky.
    if(abs(rel.x)<1.0 && abs(rel.y)<1.0)
        return max(color,vec3(238,244,252)/255.0*max(iStarGain,0.8));
    // Trail: beads on the lattice, like the comet's, so a fast streak does not crawl sideways.
    vec2 dirPx=normalize(vec2(floor(dir.x*4.0+0.5)*0.25,floor(dir.y*4.0+0.5)*0.25)+vec2(0.0,1e-4));
    float tail=10.0+12.0*hash21(vec2(seed,37.0));
    for(int k=1;k<=8;k++) {
        float f=float(k)/8.0;
        vec2 bp=snapFine(head-dirPx*(tail*f));
        vec2 dd=placeAt(fragCoord,bp,px,1.0);
        if(abs(dd.x)>0.5 || abs(dd.y)>0.5) continue;
        vec3 tone = f<0.4 ? vec3(186,206,228)/255.0 : vec3(98,120,148)/255.0;
        color=max(color,tone*max(iStarGain,0.7)*(1.0-progress*0.35));
    }
    return color;
}

vec2 patrolSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/420.0);
    float seed=hash21(vec2(slot,5077.0));
    if(seed<0.35) return vec2(-100.0,seed);
    float delay=15.0+90.0*hash21(vec2(slot,59.0));
    return vec2((mod(clock,420.0)-delay)/iWarpRate,seed);
}

vec2 structureSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/250.0);
    float seed=hash21(vec2(slot,3079.0));
    if(seed<0.35) return vec2(-100.0,seed);
    float delay=10.0+60.0*hash21(vec2(slot,41.0));
    return vec2((mod(clock,250.0)-delay)/iWarpRate,seed);
}

vec3 structureArt(vec2 d, float r, float seed, bool gate, vec3 color) {
    vec3 dark=vec3(18,23,33)/255.0, mid=vec3(46,57,69)/255.0;
    vec3 lit=vec3(76,85,92)/255.0, gold=vec3(114,104,77)/255.0;
    vec3 teal=vec3(65,103,105)/255.0;
    vec2 n=d/max(r,1.0);
    if(gate) {
        // Oblique, thick armored aperture. Faceted octagonal rim with four docking buttresses.
        vec2 e=vec2(n.x/0.43,n.y);
        float oct=max(max(abs(e.x),abs(e.y)),(abs(e.x)+abs(e.y))*0.7071068);
        if(oct<1.03 && oct>0.72) {
            color=e.x+e.y<-0.2 ? lit : mid;
            if(oct<0.84) color=dark;
        }
        if(oct<0.72) {
            color=vec3(9,14,23)/255.0;
            float wave=0.5+0.5*sin(oct*14.0-iTime*0.30+seed*6.0);
            if(wave>0.84) color=vec3(22,32,44)/255.0;
            if(oct>0.65 && e.y>0.0) color=teal*0.65;
        }
        for(int k=0;k<4;k++) {
            float a=0.7853982+float(k)*1.5707963;
            vec2 u=vec2(cos(a),sin(a));
            vec2 v=e-u*0.93;
            float along=dot(v,u), across=dot(v,vec2(-u.y,u.x));
            if(abs(across)<0.16 && along>-0.18 && along<0.26) {
                color=across<0.0 ? mid : dark;
                if(abs(across)<0.055 && along<-0.06) color=gold;
            }
        }
    } else {
        // Heavy orbital drydock: paired armored dock jaws, central keel, broad radiator banks.
        if(abs(n.x)<1.40 && abs(n.y)<0.09) color=dark;
        for(int j=0;j<2;j++) {
            float side=j==0 ? -1.0 : 1.0;
            vec2 v=vec2(n.x-side*0.92,n.y);
            if(abs(v.x)<0.30 && abs(v.y)<0.79) {
                color=v.x<0.0 ? mid : dark;
                if(v.y<-0.60) color=lit;
                if(abs(v.x)<0.18 && abs(v.y)<0.48) color=vec3(25,33,44)/255.0;
                if(abs(v.y)<0.035 && abs(v.x)<0.18) color=mid;
            }
            vec2 jaw=vec2(n.x,n.y-side*0.39);
            if(jaw.x>-0.57 && jaw.x<0.68-abs(jaw.y)*0.65 && abs(jaw.y)<0.14)
                color=jaw.y<0.0 ? mid : dark;
            if(jaw.x>-0.18 && jaw.x<0.31 && abs(jaw.y)<0.026) color=gold;
        }
        if(n.x>-0.62 && n.x<-0.30 && abs(n.y)<0.59) color=mid;
        if(n.x>-0.55 && n.x<-0.38 && abs(n.y)<0.24) color=lit;
        if(n.x>-0.48 && n.x<-0.40 && abs(n.y)<0.10) color=dark;
        // Small rotating service collar; only four discrete lamps, no spinning bright checkerboard.
        float rr=length(n-vec2(-0.45,0.0));
        if(rr>0.26 && rr<0.35) color=mid;
        for(int k=0;k<4;k++) {
            float a=iTime*0.08+float(k)*1.5707963+seed*6.0;
            vec2 v=n-vec2(-0.45,0.0)-vec2(cos(a),sin(a))*0.30;
            if(max(abs(v.x),abs(v.y))<0.034) color=teal;
        }
    }
    return color;
}

vec3 structurePass(vec2 fragCoord, vec2 pixel, vec2 size, vec3 color) {
    float px=max(floor(iPixelSize),1.0);
    float aspect=size.x/size.y;
    vec2 ev=structureSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    // Slow: a couple of minutes to cross, the way the planets move.
    float life=70.0+35.0*hash21(vec2(seed,53.0));
    life=transitLifetime(age,life,250.0);
    if(age>life) return color;
    float progress=age/life;
    float lane=0.06+0.88*hash21(vec2(seed,11.0));
    vec2 center=snapFine(mix(vec2(-0.12,lane),vec2(aspect+0.12,lane),progress)*size.y
        +vec2(0.0,sin(progress*6.2831853)*0.008*size.y));
    float r=(0.022+0.014*hash21(vec2(seed,23.0)))*size.y;   // logical pixels
        vec2 d=placeAt(fragCoord,center,px,0.5);   // 2 screen px, like the ships
    if(abs(d.x)>r*1.8 || abs(d.y)>r*1.8) return color;
    color=structureArt(d,r,seed,hash21(vec2(seed,31.0))<0.5,color);
    return color;
}

vec2 asteroidSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/300.0);
    float seed=hash21(vec2(slot,941.0));
    if(seed<0.42) return vec2(-100.0,seed);
    float delay=20.0+200.0*hash21(vec2(slot,37.0));
    return vec2((mod(clock,300.0)-delay)/iWarpRate,seed);
}

vec3 asteroidGroup(vec2 fragCoord, vec2 pixel, vec2 size, vec3 color) {
    float aspect=size.x/size.y;
    float px=max(floor(iPixelSize),1.0);
    vec2 ev=asteroidSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=60.0+30.0*hash21(vec2(seed,53.0));
    life=transitLifetime(age,life,300.0);
    if(age>life) return color;
    float progress=age/life;
    // A shallow lane across the sky, travelling the scene's direction. `life` is short compared with a
    // planet's crossing, so the belt reads as fast even though it is drawn at the same scale.
    float lane=0.10+0.80*hash21(vec2(seed,11.0));
    vec2 start=vec2(-max(0.80,aspect*0.35), lane);
    vec2 endp=vec2(aspect+max(0.80,aspect*0.35), lane+(hash21(vec2(seed,23.0))-0.5)*0.30);
    vec2 center=mix(start,endp,progress)*size.y;
    vec2 dir=normalize(endp-start);
    vec2 side=vec2(-dir.y,dir.x);
    int count=14+int(floor(hash21(vec2(seed,71.0))*12.0));
    for(int j=0;j<min(count,26);j++) {
        float id=float(j);
        float r1=hash21(vec2(seed*13.0,id+5.0));
        float r2=hash21(vec2(seed*29.0,id+9.0));
        // Rocks trail the group centre, strung out along the direction of travel and spread across it,
        // with the belt opening up a little as it crosses.
        vec2 rock = snapFine(center - dir*(r1*0.30+progress*0.16)*size.x*0.45 + side*(r2-0.5)*0.30*size.y);
        // Offsets come from the physical grid, not the 4px block, so the rock's raster translates
        // smoothly instead of re-boiling its interior as it slides.
        // The rock is a sprite: its features live on its own 4px lattice, but that lattice is positioned to
        // the physical pixel, so the whole mosaic slides one pixel at a time. Sampling the shape from the
        // *fragment* and quantising its features to blocks is what removes the shimmer: block-centre
        // sampling flipped a whole boundary block on every sub-pixel move.
        vec2 d=floor(fineLocal(fragCoord,rock,px));
        // Cheap reject before anything expensive: only the pixels near this rock are shaded.
        if(abs(d.x)>7.5 || abs(d.y)>7.5) continue;
        float r3=hash21(vec2(seed*41.0,id+17.0));
        float wr = r3>0.86 ? 6.5 : (r3>0.55 ? 4.2 : 2.6);   // radius in logical pixels
        // The silhouette is a smooth function of the angle rather than a noise lattice. A noise lattice
        // sampled on the absolute grid boils its whole interior while the rock slides - that is the
        // sizzle; lobes change only where the boundary crosses a pixel, so the shape travels without
        // churning (the planets read as objects for the same reason: their field is a function of
        // quantised local coordinates).
        float ang=atan(d.y,d.x);
        float lobe=0.86+0.14*sin(ang*3.0+float(id)*2.1);
        float rr=wr*lobe;
        float dd=dot(d,d);
        if(dd > rr*rr) continue;
        float g = d.x*0.7 + d.y*1.2;
        vec3 tone = vec3(41,43,47)/255.0;
        if(g < -wr*0.30) tone = vec3(53,55,59)/255.0;
        else if(g > wr*0.35) tone = vec3(27,29,34)/255.0;
        if(dd > (rr-1.8)*(rr-1.8) && g < 0.0) tone = vec3(64,65,69)/255.0;   // rim light
        // Two craters fixed to the rock itself, not to the grid: a lattice would slide across the
        // surface as the rock travelled.
        if(length(d-vec2(wr*0.34,wr*0.16))<wr*0.30 || length(d+vec2(wr*0.30,wr*0.34))<wr*0.22)
            tone = vec3(21,23,28)/255.0;
        // Ore and mining drones are deliberately off: the belt should read as a drab, moody field of rock the
        // eye skips over, not as a resource display. One flag keeps the code path testable.
        bool mined = false;
        vec3 ore=vec3(105,91,60)/255.0;
        float oreRoll=hash21(vec2(seed*59.0,id+29.0));
        if(oreRoll<0.34) ore=vec3(104,108,114)/255.0;
        else if(oreRoll<0.62) ore=vec3(69,85,117)/255.0;
        if(mined) {
            float vein=abs(fract((d.x*0.8+d.y*1.1)*0.32+float(id))-0.5);
            if(vein<0.11) tone=ore;
            if(dd>(rr-2.4)*(rr-2.4)) tone=mix(tone,ore,0.40);
        }
        color=max(color,tone);
        if(mined) {
            // One to three drones working the rock, on a slow orbit, each with a mining beam.
            int drones=1+(hash21(vec2(seed,61.0+id))>0.45 ? 1 : 0)+(hash21(vec2(seed,67.0+id))>0.75 ? 1 : 0);
            for(int k=0;k<min(drones,3);k++) {
                float kf=float(k);
                float a2=iTime*0.30*(1.0+0.25*kf)+kf*2.4+float(id);
                vec2 dp=snapFine(rock+vec2(cos(a2),sin(a2))*rr*1.75);
                vec2 dq=placeAt(fragCoord,dp,px,1.0);
                if(abs(dq.x)<1.8 && abs(dq.y)<1.4) {
                    color=max(color,vec3(65,68,75)/255.0);
                    if(dq.x>0.6) color=max(color,vec3(81,117,129)/255.0);   // engine
                }
                // A mining beam, measured at the fragment so it is one screen pixel wide.
                vec2 toRock=normalize(rock-dp);
                vec2 relM=(fragCoord-dp*max(floor(iPixelSize),1.0));
                float alongM=dot(relM,toRock);
                if(alongM>0.0 && alongM<rr*1.75*max(floor(iPixelSize),1.0)
                    && length(relM-toRock*alongM)<0.8)
                    color=max(color,ore*0.85);
            }
        }
    }
    return color;
}

vec2 shieldState(float attackAge, float seed) {
    if(attackAge<0.0) return vec2(0.0,0.0);
    float hitRate=2.6;
    float capacity=8.0+5.0*hash21(vec2(seed,83.0));
    float upTime=capacity/hitRate;
    float downTime=3.0+1.6*hash21(vec2(seed,89.0));
    float u=mod(attackAge,upTime+downTime+0.9);
    if(u<0.9) return vec2(u/0.9,0.0);                          // forming
    if(u<0.9+upTime) return vec2(1.0-0.55*(u-0.9)/upTime,0.0);  // up, dimming as it strains
    float since=u-(0.9+upTime);
    return vec2(0.0, since<0.30 ? 1.0-since/0.30 : 0.0);       // broken, with a flash
}

float raiderDownTime(float id, float seed) {
    return 35.0+13.0*id+5.0*hash21(vec2(seed,97.0+id));
}

float defenderDownTime(float id, float seed) {
    return 45.0+15.0*id+5.0*hash21(vec2(seed,131.0+id));
}

vec2 defenderPos(vec2 formation, vec2 forward, vec2 sidev, float id, float seed, vec2 size) {
    float r1=hash21(vec2(seed*23.0,id+7.0));
    return formation+sidev*(r1-0.5)*0.12*size.y-forward*id*0.030*size.y;
}

vec2 raiderPos(vec2 formation, vec2 forward, vec2 sidev, float id, float seed, vec2 size) {
    float r1=hash21(vec2(seed*11.0,id+5.0));
    return formation+sidev*(r1-0.5)*0.11*size.y-forward*id*0.035*size.y;
}

vec2 incursionSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/420.0);
    float seed=hash21(vec2(slot,1597.0));
    // The first slot always fires, twelve seconds in: an event that a 30%-skipped, seven-minute slot only
    // produced once in a while was, in practice, an event nobody saw. Random pacing stays for every later
    // slot, so the majesty is intact - the first one is simply guaranteed to be discoverable.
    if(slot<0.5) return vec2((mod(clock,420.0)-12.0)/iWarpRate,max(seed,0.5));
    if(seed<0.30) return vec2(-100.0,seed);
    float delay=20.0+220.0*hash21(vec2(slot,29.0));
    return vec2((mod(clock,420.0)-delay)/iWarpRate,seed);
}

vec2 armorLight(vec2 worldCenter, vec2 forward) {
    vec2 lamp=vec2(iResolution.x/iResolution.y*0.32,-0.35);
    vec2 light=normalize(lamp-worldCenter);
    return vec2(dot(light,forward),dot(light,vec2(-forward.y,forward.x)));
}

vec3 warshipArt(vec2 s, float kind, float age, float depth, vec3 bg, vec2 light, bool alien) {
    float artPitch=0.5/max(depth,0.20);
    s=(floor(s/artPitch)+0.5)*artPitch;
    // Hull units remain compatible with all existing formation, warp and clipping code.
    float aft=-25.0, bow=32.0, beam=9.0;
    if(kind>0.5 && kind<1.5) {aft=-28.0;bow=33.0;beam=12.0;}
    if(kind>1.5 && kind<2.5) {aft=-34.0;bow=34.0;beam=12.0;}
    if(kind>2.5 && kind<3.5) {aft=-44.0;bow=46.0;beam=17.0;}
    if(kind>3.5 && kind<4.5) {aft=-12.0;bow=16.0;beam=5.5;}
    if(kind>4.5) {aft=-26.0;bow=27.0;beam=11.0;}
    float u=(s.x-aft)/(bow-aft), ay=abs(s.y);
    float pixel=0.5/max(depth,0.20);
    float shoulder=clamp((u-0.18)/0.70,0.0,1.0);
    float width=beam*(1.0-shoulder*0.85);
    width*=clamp(0.60+u*4.0,0.0,1.0);
    // Six structural families: escort, broad cruiser, twin-deck carrier, stepped capital,
    // compact spear and three armored cargo pods. Negative spaces are intentional geometry.
    if(kind>1.5 && kind<2.5) width=beam*min(1.0,0.65+u*3.0)*(1.0-clamp((u-0.82)/0.18,0.0,1.0)*0.62);
    if(kind>2.5 && kind<3.5) {
        width=beam*(u<0.18 ? 0.72+u : u<0.38 ? 1.0 : u<0.62 ? 0.78 : max(0.08,1.98-u*2.05));
    }
    if(kind>4.5) width=beam*(u<0.18 ? 0.56 : u>0.83 ? 0.68 : 0.90);
    float arc=0.0;
    if(alien) {
        arc=beam*0.18*sin(u*3.14159265);
        width=beam*(0.22+0.78*sin(clamp(u,0.0,1.0)*3.14159265));
        if(kind>1.5 && kind<2.5) width*=1.0+0.16*sin(u*9.0);
        ay=abs(s.y-arc);
    }
    bool body=u>=0.0 && u<=1.0 && ay<width;
    if(kind>1.5 && kind<2.5 && u>0.38 && u<0.91 && ay<beam*0.18) body=false;
    if(alien && u>0.48 && u<0.98 && abs(s.y-arc)<beam*0.17) body=false;
    if(kind>4.5 && u>0.2 && u<0.8 && ay>beam*0.48) {
        if(fract((u-0.20)*5.0)<0.15) body=false;
    }
    vec3 shadow=vec3(16,22,31)/255.0, recess=vec3(10,15,23)/255.0;
    vec3 steel=vec3(45,57,69)/255.0, upper=vec3(66,79,88)/255.0;
    vec3 edge=vec3(99,111,113)/255.0, glint=vec3(139,150,144)/255.0;
    vec3 gold=vec3(135,119,80)/255.0, engine=vec3(83,134,132)/255.0;
    if(alien) {
        steel=vec3(49,46,64)/255.0;upper=vec3(72,67,86)/255.0;
        edge=vec3(108,99,118)/255.0;glint=vec3(143,133,146)/255.0;
        engine=vec3(118,104,141)/255.0;
    }
    vec3 c=bg;
    if(body) {
        float sideLight=sign(s.y-arc)*light.y;
        vec3 material=sideLight>0.0 ? steel : shadow;
        float rim=width-ay;
        // Thick lower bevel / thin lit edge. Only short sections get specular accents.
        if(rim<pixel*1.05) material=sideLight>0.18 ? edge : recess;
        if(rim<pixel && sideLight>0.35 && u>0.16 && u<0.29) material=glint;
        // Tiered upper superstructure has large quiet planes surrounding the machinery trench.
        float deckW=width*0.59;
        bool deck=u>0.14 && u<0.80 && ay<deckW;
        if(deck) {
            material=sideLight>-0.25 ? upper : steel;
            if(deckW-ay<pixel*0.85) material=sideLight>0.0 ? edge : recess;
            // Two longitudinal plate breaks; no whole-hull barcode or random noise.
            if((abs(u-0.35)<0.012 || abs(u-0.64)<0.012) && ay>deckW*0.42) material=shadow;
        }
        // A recessed service channel, staggered access hatches, then an armored bridge crown.
        bool channel=u>0.19 && u<0.59 && s.y>width*0.14 && s.y<width*0.40;
        if(channel) {
            material=recess;
            if(fract((u-0.19)*12.0)>0.68) material=steel;
            if(s.y>width*0.34) material=shadow;
        }
        if(u>0.23 && u<0.36 && s.y>-width*0.36 && s.y<width*0.07) {
            material=steel;
            if(s.y<-width*0.20) material=edge;
            if(u>0.25 && u<0.31 && s.y>-width*0.19 && s.y<-width*0.04) material=recess;
        }
        // Structured rear heat exchangers are limited to two machinery islands.
        if(u>0.04 && u<0.19 && ay>width*0.30 && ay<width*0.76) {
            material=recess;
            if(mod(floor(s.x/max(pixel,0.75)),3.0)==0.0) material=upper;
        }
        if(kind>1.5 && kind<2.5 && u>0.43 && u<0.82 && ay<beam*0.40) {
            material=recess;
            if(ay>beam*0.32) material=steel;
            if(ay<beam*0.23 && u>0.50 && u<0.66) material=gold;
        }
        if(kind>2.5 && kind<3.5 && u>0.38 && u<0.61 && ay>width*0.55 && ay<width*0.80) {
            material=steel;
            if(abs(u-0.45)<0.025 || abs(u-0.55)<0.025) material=edge;
            if(ay>width*0.73) material=recess;
        }
        if(kind>4.5 && u>0.20 && u<0.79 && ay<width*0.80) {
            float pod=fract((u-0.20)*5.0);
            material=pod<0.14 ? recess : sideLight>0.0 ? upper : steel;
            if(pod>0.17 && pod<0.24) material=edge;
            if(pod>0.40 && pod<0.70 && ay<width*0.25) material=shadow;
        }
        if(alien) {
            // Overlapping carapace plates wrap across the spine, instead of human hatch grids.
            float seam=fract(u*4.0+(s.y-arc)/beam*0.15);
            if(seam<0.07 && u>0.13 && u<0.85) material=recess;
            if(seam>0.09 && seam<0.13 && ay<width*0.73) material=edge;
        }
        // Sparse windows are a functional landmark, not a glowing center stripe.
        if(u>0.27 && u<0.34 && s.y<-width*0.06 && s.y>-width*0.19) material=gold;
        c=material*iShipGain*(0.76+0.24*clamp(depth,0.0,1.0));
    }
    // Aft exhaust in shielded sockets; paired drives for large hulls, one for the escort.
    float engineY=beam*(kind>3.5 && kind<4.5 ? 0.0 : 0.35);
    float exhaust=abs(ay-engineY);
    if(s.x<aft+pixel && s.x>aft-1.8 && exhaust<max(pixel*0.65,1.0))
        c=shadow*iShipGain;
    if(s.x<aft && s.x>aft-(1.2+0.35*sin(age*1.2)) && exhaust<max(pixel*0.38,0.7))
        c=engine*iShipGain*(0.65+0.35*depth);
    return c;
}

vec2 spriteInverse(vec2 local, vec2 scale) {
    return local/max(abs(scale),vec2(0.006));
}

vec3 warpTrail(vec2 q, float phase, float depth, vec3 bg) {
    if(phase<=0.20 || phase>=1.0) return bg;
    float fade=pow(1.0-phase,2.0);
    float length=(16.0+95.0*phase)*depth;
    if(q.x>0.0 || q.x<-length || abs(q.y)>5.0*depth) return bg;
    float taper=1.0+q.x/length;
    float band=abs(q.y)/(max(depth,0.25));
    if(band<0.7 || (band>2.0 && band<2.5))
        return max(bg,vec3(64,109,112)/255.0*fade*taper*iShipGain);
    return bg;
}

vec3 hullImpact(vec2 q, float age, vec3 bg) {
    if(age<0.0 || age>0.24) return bg;
    float fade=1.0-age/0.24;
    if(length(q)<1.0+age*7.0) return max(bg,vec3(202,180,127)/255.0*fade);
    for(int j=0;j<5;j++) {
        float a=float(j)*2.39996;
        vec2 v=vec2(cos(a),sin(a));
        vec2 r=q-v*(2.0+age*(28.0+float(j)*5.0));
        if(abs(dot(r,v))<1.4 && abs(dot(r,vec2(-v.y,v.x)))<0.65)
            bg=max(bg,vec3(153,103,69)/255.0*fade);
    }
    return bg;
}

vec3 damagedHull(vec2 s, float kind, float age, float depth, vec3 bg, vec2 light, bool alien, float untilDown) {
    vec3 c=warshipArt(s,kind,age,depth,bg,light,alien);
    if(untilDown>1.25 || all(lessThan(abs(c-bg),vec3(0.001)))) return c;
    float damage=clamp(1.0-untilDown/1.25,0.0,1.0);
    float fracture=abs(s.y-0.22*s.x-1.7*sin(s.x*0.32));
    if(abs(s.x)<18.0 && fracture<0.5+damage*1.8) {
        c=vec3(12,16,23)/255.0*iShipGain;
        if(fracture<0.6 && sin(age*24.0+s.x)>0.55)
            c=vec3(155,102,58)/255.0*iShipGain;
    }
    return c;
}

vec3 hullWreck(vec2 local, float kind, float age, float depth, vec3 bg, bool alien) {
    if(age<0.0 || age>=2.0) return bg;
    // Six actual hull sections, each preserving its painted armor, drifting and tumbling.
    if(abs(local.x)>65.0*depth+age*18.0 || abs(local.y)>25.0*depth+age*18.0) return bg;
    for(int j=0;j<6;j++) {
        float k=float(j);
        vec2 anchor=vec2(-30.0+k*13.0,0.0);
        vec2 velocity=vec2((k-2.5)*3.0,(mod(k,2.0)*2.0-1.0)*(5.0+k));
        vec2 d=local/depth-anchor-velocity*age;
        float a=(mod(k,2.0)*2.0-1.0)*age*(0.7+k*0.12);
        vec2 r=vec2(cos(a)*d.x+sin(a)*d.y,-sin(a)*d.x+cos(a)*d.y);
        if(abs(r.x)>6.4 || abs(r.y)>19.0) continue;
        vec3 piece=warshipArt(r+anchor,kind,age,depth,vec3(-1),normalize(vec2(-0.4,-1)),alien);
        if(piece.x>=0.0) {
            float fade=1.0-smoothstep(0.7,2.0,age);
            bg=mix(bg,piece*0.80,fade);
            if(abs(r.x)>5.0 && age<0.40) bg=max(bg,vec3(125,80,47)/255.0*(1.0-age/0.40));
        }
    }
    return hullImpact(local*max(floor(iPixelSize),1.0),age,bg);
}

vec3 patrolPass(vec2 fragCoord, vec2 pixel, vec2 size, vec3 color) {
    float aspect=size.x/size.y;
    float px=max(floor(iPixelSize),1.0);
    vec2 ev=patrolSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=150.0+40.0*hash21(vec2(seed,67.0));
    life=transitLifetime(age,life,420.0);
    if(age>life) return color;
    float progress=age/life;
    float lane=0.10+0.80*hash21(vec2(seed,13.0));
    vec2 start=vec2(-0.45,lane);
    vec2 endp=vec2(aspect+0.45,lane);
    int count=1+int(floor(hash21(vec2(seed,71.0))*2.99));
    for(int k=0;k<min(count,3);k++) {
        float id=float(k);
        float r1=hash21(vec2(seed*17.0,id+3.0));
        // A gentle weave, so a patrol does not look like it is running on rails.
        float weave=sin(progress*8.2+id*2.1)*0.012+sin(progress*17.0+id)*0.005;
        vec2 p2p=mix(start,endp,progress)*size.y+vec2(0.0,weave*size.y)
            -vec2(1.0,0.0)*id*(0.05+0.02*r1)*size.y;
        // Physical-grid offsets (see `fineLocal`): the patrol is the one that used to sizzle.
        vec2 d=(fragCoord/px-p2p);
        if(abs(d.x)>46.0 || abs(d.y)>26.0) continue;
        // The fleet's own hulls, unscaled: a patrol is not warping, so nothing compresses. Distance is
        // randomized per event: some cruise closer in, most stay far out on the orbit.
        float kind=mod(floor(hash21(vec2(seed*7.0,id+11.0))*3.0),3.0);
        float dep=0.18+0.20*hash21(vec2(seed,73.0));
        color=depthComposite(color,warshipArt(d/dep,kind,age*0.5+id,dep,color,armorLight(p2p/size.y,vec2(1,0)),false),0.72/dep);
    }
    return color;
}

vec3 alienHull(vec2 s, float kind, float age, float depth, vec3 bg) {
    return warshipArt(s,kind,age,depth,bg,normalize(vec2(-0.4,-1.0)),true);
}

vec3 metricWake(vec2 q, float phase, float depth, vec3 bg, bool alien) {
    if(phase<=0.0 || phase>=1.0 || iShipGain<=0.0) return bg;
    float envelope=sin(phase*3.14159265);
    float pitch=2.0/max(floor(iPixelSize),1.0);
    float d=max(depth,0.25);
    float height=(6.0+12.0*envelope)*d;
    float yy=abs(q.y)/max(height,pitch);
    if(yy>1.0 || abs(q.x)>42.0*d) return bg;
    vec3 cold=vec3(65,103,105)/255.0;
    vec3 warm=vec3(114,104,77)/255.0;
    if(alien) cold=vec3(93,79,110)/255.0;
    vec3 c=bg;
    // Dark lens bounded by opposing bent wavefronts. No full-screen flash or bright hoop.
    float snapRelease=smoothstep(0.25,0.43,phase);
    float squeeze=mix(0.20,1.0,snapRelease);
    float curve=(1.0-yy*yy)*9.0*d*squeeze;
    if(q.x>-curve*1.3 && q.x<curve*0.65) c*=1.0-0.20*envelope;
    for(int j=0;j<3;j++) {
        float k=float(j);
        // Closely packed forward fronts; separated aft fronts expand as the bubble relaxes.
        float front=curve+(2.0+k*2.5)*d*squeeze;
        float rear=-curve-(3.0+k*(4.0+phase*5.0))*d*squeeze;
        float width=pitch*0.52;
        // Deliberate staggered breaks near the extremities, not noisy spark particles.
        bool segment=yy<0.62 || (j==1 && yy<0.83) || (j==0 && yy>0.88);
        if(segment && abs(q.x-front)<width)
            c=max(c,cold*(0.85-k*0.17)*envelope*iShipGain);
        if(yy<0.82-k*0.13 && abs(q.x-rear)<width)
            c=max(c,mix(cold,warm,0.25)*(0.52-k*0.11)*envelope*iShipGain);
    }
    // Two short edge glints describe the pressure boundary; the center remains quiet.
    if(yy>0.36 && yy<0.53 && abs(q.x-(curve+2.0*d))<pitch*0.52)
        c=max(c,vec3(116,145,141)/255.0*envelope*iShipGain);
    return c;
}

vec3 alienGate(vec2 q, float phase, float depth, vec3 bg) {
    return metricWake(q,clamp(phase*12.0,0.0,1.0),depth,bg,true);
}

vec2 shipSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/70.0);
    float seed=hash21(vec2(slot,81.0));
    // The slot and the event age must share one period: they used to disagree (340 vs 180), so a
    // whole slot could pass with nothing to show, and 22% of slots produced no fleet at all. The
    // first slot is guaranteed and starts early, so a reload shows ships within seconds instead of
    // leaving the operator wondering whether they render at all.
    // Frequent flybys: one fleet roughly every 70 seconds, and the first 6 seconds after a (re)load,
    // so the warp-in and warp-out read as a regular part of the scene rather than an occasional
    // surprise. A 12% skip keeps it from feeling metronomic without ever leaving a long dead gap.
    if(slot<0.5) return vec2((mod(clock,70.0)-6.0)/iWarpRate,max(seed,0.5));
    if(seed<0.12) return vec2(-100.0,seed);
    float dly=6.0+26.0*hash21(vec2(slot,19.0));
    return vec2((mod(clock,70.0)-dly)/iWarpRate,seed);
}

vec3 warpGate(vec2 q, float phase, float depth, vec3 bg) {
    return metricWake(q,phase,depth,bg,false);
}

vec3 operaShield(vec2 rel, float age, float radius, bool planetary, vec3 bg) {
    float duration=planetary ? 0.22 : 0.12;
    if(age<0.0 || age>duration) return bg;
    float t=age/duration;
    float r=radius*(0.25+0.75*sqrt(t));
    float edge=abs(length(rel)-r);
    float polar=atan(rel.y,rel.x);
    // A fast expanding pressure front followed by a dim segmented return wave.
    float segments=step(0.15,fract(polar*3.8197186));
    if(edge<0.7 && segments>0.0)
        bg=max(bg,vec3(106,150,143)/255.0*(1.0-t));
    if(planetary && abs(length(rel)-r*0.62)<0.65)
        bg=max(bg,vec3(113,107,82)/255.0*(1.0-t)*0.65);
    if(length(rel)<1.3 && t<0.28) bg=max(bg,vec3(190,202,177)/255.0);
    return bg;
}

vec3 incursionEvent(vec2 fragCoord, vec2 pixel, vec2 size, vec2 target, float targetR, float shieldStr, float railShieldStr, vec3 color) {
    float aspect=size.x/size.y;
    vec2 ev=incursionSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=130.0+40.0*hash21(vec2(seed,61.0));
    if(age>=life) return color;
    float px=max(floor(iPixelSize),1.0);
    // They arrive on the far side of the target's lane, so the world sits in their field of fire.
    float side=hash21(vec2(seed,17.0))>0.5 ? 1.0 : -1.0;
    float lane=clamp(target.y+side*(0.24+0.16*hash21(vec2(seed,23.0))),0.10,0.90);
    vec2 entryP=vec2(-0.16,lane);
    vec2 exitP=vec2(aspect+0.16,lane+(hash21(vec2(seed,43.0))-0.5)*0.10);
    float inP=clamp(age/2.6,0.0,1.0);
    float outP=clamp((age-(life-3.4))/3.4,0.0,1.0);
    // Nothing to attack if the megacity world is not on screen: the squadron warps in, holds station
    // briefly and leaves again instead of bombarding empty sky.
    bool planetVisible = target.x+CITY_R>0.02 && target.x-CITY_R<aspect-0.02
        && target.y+CITY_R>0.02 && target.y-CITY_R<0.98;
    if(!planetVisible) life=min(life,9.0);
    float attack=(planetVisible && age>3.0 && age<life-3.4) ? 1.0 : 0.0;
    // Smoothstep: a quick arrival, slow station-keeping through the bombardment, quick departure. A
    // constant rate either crawls or races, and a line of hulls that blinks out of existence reads as
    // a bug rather than a withdrawal.
    float travel=clamp((age-2.0)/max(0.1,life-3.4),0.0,1.0);
    travel=travel*travel*(3.0-2.0*travel);
    vec2 forward=normalize(exitP-entryP);
    vec2 sidev=vec2(-forward.y,forward.x);
    vec2 formation=mix(entryP,exitP,travel)*size.y;
    int count=4+int(floor(hash21(vec2(seed,71.0))*5.99));
    vec2 tgtPx=target*size.y;
    // The defending squadron, if one answers: its lane is set up here so the raiders can aim at it.
    bool defended = hash21(vec2(seed,211.0))>0.45;
    int dCount = defended ? 3+int(floor(hash21(vec2(seed,223.0))*2.99)) : 0;
    vec2 dEntry=vec2(aspect+0.16,lane);
    vec2 dExit=vec2(-0.16,lane);
    vec2 dForward=normalize(dExit-dEntry);
    vec2 dSide=vec2(-dForward.y,dForward.x);
    vec2 dFormation=mix(dEntry,dExit,clamp((age-2.6)/max(0.1,life-3.4),0.0,1.0))*size.y;
    for(int j=0;j<min(count,9);j++) {
        float id=float(j);
        // Shot-down raiders are gone before they can fire again.
        if(age>raiderDownTime(id,seed)) continue;
        // Each craft arrives on its own beat rather than the whole line popping in at once.
        float inS=clamp((age-2.5-id*0.70)/5.0,0.0,1.0);
        if(inS<=0.0) continue;
        vec2 center=raiderPos(formation,forward,sidev,id,seed,size);
        // Gates: they open where the squadron entered, and again where it leaves.
        float gatePhase=age<life*0.6 ? inS : outP;
        vec2 gateOrigin=(age<life*0.5 ? entryP : exitP)*size.y;
        vec2 gd=fragCoord-floor(gateOrigin*px);
        float gspan=70.0*px;
        if(abs(gd.x)<gspan && abs(gd.y)<gspan) {
            vec2 gp=(floor(gd/2.0)+0.5)*2.0/px;
            vec2 gq=vec2(dot(gp,forward),dot(gp,sidev));
            color=alienGate(gq,gatePhase,0.9,color);
        }
        // Ships are allowed detail finer than the 4px block: sampled at the fragment, anchored to the
        // physical grid, so the plating reads at this scale without stepping.
        vec2 p2=(fragCoord/px-center);
        vec2 q2=vec2(dot(p2,forward),dot(p2,sidev));
        // A raid leaves the way it came, but it stays *legible* while it does: the compression is held back
        // until the last third of the departure, or the ships spent their exit as sub-pixel specks and the
        // warp-out simply read as "they vanished" (or never appeared at all).
        float depart=clamp((outP-0.68)/0.32,0.0,1.0);
        float lenS=mix(0.10,1.0,inS)*max(0.22,1.0-depart*0.90);
        float widS=mix(0.16,1.0,inS)*max(0.06,1.0-depart*0.94);
        vec2 s2=spriteInverse(q2,vec2(lenS,widS)*0.34);
        float kind=mod(floor(hash21(vec2(seed*7.0,id+31.0))*5.0),5.0);
        if(abs(s2.x)<60.0 && abs(s2.y)<40.0)
            color=depthComposite(color,damagedHull(s2,kind,age+id,0.34,color,armorLight(center/size.y,forward),true,raiderDownTime(id,seed)-age),0.72/0.34);
        // Raider shields fail shortly before the hull is lost.
        float rfail=age-(raiderDownTime(id,seed)-0.9);
        if(rfail>0.0 && rfail<0.30 && hexEdge(fineLocal(fragCoord,center,px),1.5+rfail*4.5)<0.9)
            color=mix(color,vec3(214,150,186)/255.0,(1.0-rfail/0.30)*0.55);
        // Gunfire and impacts, on a fixed cadence per ship so the volley reads as a rhythm.
        if(attack>0.5 && inS>0.85) {
            // Where a bolt stops is what the shield is *for*: while it holds, the shots end at the
            // bubble and the glints land on it instead of on the city. Half the squadron trades fire
            // with the defending ships rather than the planet.
            float stopR = shieldStr>0.02 ? 1.06 : 1.0;
            vec2 aimPx=tgtPx;
            float aimRadius=targetR*size.y*stopR;
            bool duelling = defended && dCount>0 && mod(id,2.0)>0.5 && age>3.8;
            bool railHit = mod(id,4.0)>2.5;
            if(duelling) {
                float k=mod(id,float(dCount));
                aimPx=snapPixel(defenderPos(dFormation,dForward,dSide,k,seed,size));
                aimRadius=0.0;
            } else if(railHit) {
                // Some of the squadron goes after the orbital ring instead, which has its own shield.
                float a=hash21(vec2(seed,173.0+id))*6.2831853;
                vec2 er=vec2(1.52*cos(a),0.42*sin(a));
                aimPx=snapFine(tgtPx+vec2(er.x-0.30*er.y,er.y+0.30*er.x)*targetR*size.y);
                aimRadius=0.0;
            }
            vec2 toward=normalize(aimPx-center);
        // Fire: three thin bolts per ship. The bombardment has to read as heavy, but each trace stays
        // narrow - a planet is a hundred times a hull's width, so a fat beam would look like a beam of
        // paint. Volume comes from the number of shots, not their size.
        for(int b=0;b<3;b++) {
            float bAge=mod(age-id*0.055-float(b)*0.035,9.0);
            if(bAge>0.22) continue;
            if(depthEnabled && mix(0.72/0.34,2.0,clamp(bAge/0.10,0.0,1.0))>sceneDepth+0.02) continue;
            float rnd=hash21(vec2(seed*31.0,id*3.0+float(b)));
            // Aim lands at any depth inside the disc, not only on the rim: a barrage that all lands on
            // one circle reads as a ring, not as fire falling on a world.
            vec2 hitPt=aimPx-toward*(aimRadius*(0.30+0.62*rnd))
                +vec2(-toward.y,toward.x)*(rnd-0.5)*6.0;
            // A bolt keeps the heading it was fired with: its start is the hull's position *at the moment
            // of firing*, not the hull's position now. Using the live position made the whole line sweep
            // around as the ship drifted, which read as a curving shot.
            float launchAge=age-bAge;
            float tLaunch=clamp((launchAge-2.0)/max(0.1,life-3.4),0.0,1.0);
            tLaunch=tLaunch*tLaunch*(3.0-2.0*tLaunch);
            vec2 firingPos=snapFine(raiderPos(mix(entryP,exitP,tLaunch)*size.y,forward,sidev,id,seed,size));
            vec2 dirB=normalize(hitPt-firingPos);
            if(bAge<0.10) {
                // Measured at the fragment and kept tiny: a shot is a one-pixel streak a few pixels long,
                // not a bar across the sky. A ship is a speck next to a world; its gunfire should be too.
                vec2 relF=fragCoord-mix(firingPos,hitPt,bAge/0.10)*px;
                float alongF=dot(relF,dirB);
                if(abs(alongF)<3.5 && length(relF-dirB*alongF)<0.5)
                    color=max(color,vec3(242,160,160)/255.0);
            } else {
                float fade=(bAge-0.10)/0.12;
                vec2 rel=pixel-hitPt;
                if(((railHit ? railShieldStr : shieldStr)>0.02) && !duelling) {
                    color=depthComposite(color,operaShield(fragCoord-hitPt*px,bAge-0.10,22.0,true,color),railHit ? 1.95 : 2.0);
                    // A pixel of green, semi-transparent, only where the shot lands.
                    float hr=0.30-0.20*fade;
                    float edge=hexEdge(rel,hr);
                    if(hr>0.3) {
                        if(edge<0.7) color=mix(color,vec3(168,224,190)/255.0,0.45*(1.0-fade*0.6));
                        else if(edge<1.1 && fade<0.45)
                            color=mix(color,vec3(70,132,110)/255.0,0.20*(1.0-fade));
                    }
                } else if(duelling) {
                    // A hit on a hull meets that ship's own shield first: a small hexagon in the side's
                    // colour, semi-transparent, gone in a quarter second. Same restrained size as the
                    // planet's glint, scaled down because a hull is a fraction of a world.
                    color=depthComposite(color,operaShield(fragCoord-hitPt*px,bAge-0.10,8.0,false,color),0.72/0.36);
                    color=hullImpact(fragCoord-hitPt*px,(bAge-0.10),color);
                    float hr=0.34-0.26*fade;
                    float edge=hexEdge(rel,hr);
                    if(hr>0.4) {
                        if(edge<0.8) color=mix(color,vec3(150,220,240)/255.0,0.55*(1.0-fade*0.5));
                        else if(edge<1.5 && fade<0.5) color=mix(color,vec3(70,120,140)/255.0,0.24);
                    }
                } else {
                    // The smallest impact that still reads: a pixel and a half, plus a hairline ring.
                    float w=0.18-fade*0.22;
                    if(w>0.3 && abs(rel.x)<=w && abs(rel.y)<=w)
                        color=max(color,vec3(246,208,196)/255.0);
                    if(w>0.3 && abs(max(abs(rel.x),abs(rel.y))-(w+0.9))<0.7 && fade<0.6)
                        color=max(color,vec3(222,126,122)/255.0);
                }
            }
        }
        }
    }
    // Defensive fire: the ring's batteries keep up a steady barrage at the raiders for as long as the
    // attack lasts, so the world is visibly shooting back instead of only firing the one shot that kills.
    // The origin is the *drawn* station angle (fixed), not a rotating one, or the bolts come out of empty
    // space beside the station they are supposed to leave from.
    if(attack>0.5) {
        for(int m=0;m<min(count,3);m++) {
            vec2 e=stationPoint(0.65+float(m)*TAU/3.0);
            vec2 stLocal=e;   // inverse of infrastructure's frame (no extra scale)
            vec2 stPx=floor(target*iResolution.y)/px+stLocal*targetR*size.y;
            for(int q2=0;q2<2;q2++) {
                float phase=mod(age-float(m)*0.035-float(q2)*0.025,13.0);
                if(phase>0.16) continue;
                int tgt=int(mod(float(m)+float(q2)*2.0,float(count)));
                vec2 shipPx=snapFine(raiderPos(formation,forward,sidev,float(tgt),seed,size));
                vec2 toward=normalize(shipPx-stPx);
                // Measured at the fragment, in screen pixels rather than blocks: the ring's fire should be
                // a hairline one pixel wide, not one 4px block wide.
                vec2 relF=fragCoord-mix(stPx,shipPx,phase/0.16)*px;
                float alongF=dot(relF,toward);
                if(abs(alongF)<4.0 && length(relF-toward*alongF)<0.6)
                    color=max(color,vec3(186,244,252)/255.0);
                // Muzzle flash: a small glare at the battery as the bolt leaves.
                if(phase<0.05 && abs(fragCoord.x-stPx.x*px)<2.0 && abs(fragCoord.y-stPx.y*px)<2.0)
                    color=max(color,vec3(214,248,252)/255.0);
            }

        }
    }
    // Wrecks are independent of battery count and survive after the firing pass stops.
    for(int wreckId=0;wreckId<min(count,9);wreckId++) {
            float dead=raiderDownTime(float(wreckId),seed);
            float eAge=age-dead;
            if(eAge>=0.0 && eAge<2.0) {
                float deathTravel=clamp((dead-2.0)/max(0.1,life-3.4),0.0,1.0);
                deathTravel=deathTravel*deathTravel*(3.0-2.0*deathTravel);
                vec2 deathFormation=mix(entryP,exitP,deathTravel)*size.y;
                vec2 deathCenter=raiderPos(deathFormation,forward,sidev,float(wreckId),seed,size);
                vec2 rel=fragCoord/px-deathCenter;
                vec2 local=vec2(dot(rel,forward),dot(rel,sidev));
                float kind=mod(floor(hash21(vec2(seed*7.0,float(wreckId)+31.0))*5.0),5.0);
                color=hullWreck(local,kind,eAge,0.34,color,true);
            }
    }
    // The defending squadron: friendly hulls, their own gates, return fire at the raiders and their own
    // losses. Both sides shoot, so the engagement can go either way.
    if(defended && dCount>0) {
        float dIn=clamp((age-4.0)/4.0,0.0,1.0);
        float dOut=clamp((age-(life-2.4))/2.4,0.0,1.0);
        for(int k=0;k<min(dCount,5);k++) {
            float id=float(k);
            float down=defenderDownTime(id,seed);
            vec2 dcenter=defenderPos(dFormation,dForward,dSide,id,seed,size);
            // Gate where this ship arrived, and where it leaves.
            vec2 gOrigin=(age<life*0.5 ? dEntry : dExit)*size.y;
            vec2 gd=fragCoord-floor(gOrigin*px);
            float gspan=70.0*px;
            if(abs(gd.x)<gspan && abs(gd.y)<gspan) {
                vec2 gp=(floor(gd/2.0)+0.5)*2.0/px;
                vec2 gq=vec2(dot(gp,dForward),dot(gp,dSide));
                float shortPhase=age<life*0.5 ? clamp(dIn*16.0,0.0,1.0) : clamp(dOut*12.0,0.0,1.0);
                color=warpGate(gq,shortPhase,0.9,color);
            }
            if(age<down) {
                vec2 p3=(fragCoord/px-dcenter);
                vec2 q3=vec2(dot(p3,dForward),dot(p3,dSide));
                float depart2=clamp((dOut-0.68)/0.32,0.0,1.0);
                float lenS=mix(0.12,1.0,dIn)*max(0.22,1.0-depart2*0.90);
                float widS=mix(0.16,1.0,dIn)*max(0.06,1.0-depart2*0.94);
                vec2 s3=spriteInverse(q3,vec2(lenS,widS)*0.36);
                float kind=mod(floor(hash21(vec2(seed*5.0,id+13.0))*3.0),3.0);
                if(abs(s3.x)<48.0 && abs(s3.y)<26.0)
                    color=depthComposite(color,damagedHull(s3,kind,age+id,0.36,color,armorLight(dcenter/size.y,dForward),false,down-age),0.72/0.36);
                // Return fire at a raider.
                float fAge=mod(age-id*0.045,10.0);
                if(fAge<0.12 && count>0 && dIn>0.85) {
                    int tgt=int(floor(hash21(vec2(seed,149.0+id))*float(count)));
                    // A raider that is still off-screen is not a target: the shot would hit nothing.
                    bool tgtOk = age>3.8+0.45*float(tgt);
                    vec2 tp=snapFine(raiderPos(formation,forward,sidev,float(tgt),seed,size));
                    vec2 tw=normalize(tp-dcenter);
                    vec2 relF2=fragCoord-mix(dcenter,tp,fAge/0.12)*px;
                    float a2=dot(relF2,tw);
                    if(tgtOk && abs(a2)<3.5 && length(relF2-tw*a2)<0.5 && age<raiderDownTime(float(tgt),seed))
                        color=max(color,vec3(176,240,250)/255.0);                }
                // The bolt's arrival: the raider's shield answers while it still holds, and once it has
                // failed the shot lands on the hull.
                float hitAge=fAge-0.12;
                // Same arrival rule as the shot itself, checked here without adding a brace: a raider that
                // has not arrived must not receive an impact flash in empty space.
                int impTgt=int(floor(hash21(vec2(seed,149.0+id))*float(count)));
                if(hitAge>0.0 && hitAge<0.10 && count>0 && dIn>0.85 && age>3.8+0.45*float(impTgt)) {
                    int tgt=int(floor(hash21(vec2(seed,149.0+id))*float(count)));
                    vec2 tp=snapFine(raiderPos(formation,forward,sidev,float(tgt),seed,size));
                    vec2 rel3=pixel-tp;
                    color=depthComposite(color,operaShield(fragCoord-tp*px,hitAge,8.0,false,color),0.72/0.34);
                    color=hullImpact(fragCoord-tp*px,hitAge,color);
                    float fd=hitAge/0.10;
                    if(age<raiderDownTime(float(tgt),seed)-0.9) {
                        float hr=0.32-0.24*fd;
                        float edge=hexEdge(rel3,hr);
                        if(hr>0.4) {
                            if(edge<0.8) color=mix(color,vec3(206,116,152)/255.0,0.55*(1.0-fd*0.5));
                            else if(edge<1.5 && fd<0.5) color=mix(color,vec3(96,60,86)/255.0,0.24);
                        }
                    } else {
                        float w=0.18-fd*0.22;
                        if(w>0.3 && abs(rel3.x)<=w && abs(rel3.y)<=w)
                            color=max(color,vec3(250,220,190)/255.0);
                    }
                }
                // Defence shields fail shortly before the ship is lost: a brief hexagon, then nothing.
                float dfail=age-(down-0.9);
                if(dfail>0.0 && dfail<0.30 && hexEdge(fineLocal(fragCoord,dcenter,px),1.5+dfail*4.5)<0.9)
                    color=mix(color,vec3(190,232,246)/255.0,(1.0-dfail/0.30)*0.55);
            } else {
                float d2=age-down;
                vec2 deathFormation=mix(dEntry,dExit,clamp((down-2.6)/max(0.1,life-3.4),0.0,1.0))*size.y;
                vec2 deathCenter=defenderPos(deathFormation,dForward,dSide,id,seed,size);
                vec2 rel=fragCoord/px-deathCenter;
                vec2 local=vec2(dot(rel,dForward),dot(rel,dSide));
                float kind=mod(floor(hash21(vec2(seed*5.0,id+13.0))*3.0),3.0);
                color=hullWreck(local,kind,d2,0.36,color,false);
            }
        }
    }
    return color;
}

vec3 fleetHull(vec2 s, float kind, float age, float depth, vec3 bg) {
    return warshipArt(s,kind,age,depth,bg,normalize(vec2(-0.4,-1.0)),false);
}

vec2 operaClock(float time) {
    float slot=floor(time/150.0);
    return vec2(mod(time,150.0)-18.0,hash21(vec2(slot,921.0)));
}

vec3 operaShip(float id, bool enemy, float age) {
    float z=enemy ? 3.8+id*0.26 : 1.75+id*0.20;
    float side=enemy ? 1.0 : -1.0;
    return vec3(side*(0.75+id*0.13)+age*(enemy ? -0.006 : 0.004),
        (enemy ? -0.42 : 0.36)+(mod(id,2.0)*2.0-1.0)*id*0.12,z);
}

vec2 operaProject(vec3 p) {
    return iResolution*0.5+p.xy/max(p.z,0.1)*iResolution.y;
}

vec3 operaPulse(vec2 f, vec3 source, vec3 target, float age, bool planetary, vec3 color) {
    float flight=planetary ? 0.055 : 0.075;
    if(age<0.0 || age>flight+0.22) return color;
    vec2 a=operaProject(source), b=operaProject(target);
    vec2 delta=b-a;float distance=max(length(delta),0.001);vec2 dir=delta/distance;
    float u=clamp(age/flight,0.0,1.0);
    float z=mix(source.z,target.z,u);
    if(age<flight && z<=sceneDepth) {
        vec2 q=f-mix(a,b,u);
        float longitudinal=dot(q,dir), transverse=dot(q,vec2(-dir.y,dir.x));
        float lengthPx=planetary ? 24.0 : 9.0;
        if(abs(longitudinal)<lengthPx && abs(transverse)<0.65)
            color=max(color,vec3(156,190,176)/255.0);
        if(planetary && abs(longitudinal+14.0)<8.0 && abs(transverse)<0.55)
            color=max(color,vec3(174,143,92)/255.0);
    }
    if(age<0.035 && source.z<=sceneDepth)
        color=operaShield(f-a,age,planetary ? 11.0 : 4.0,planetary,color);
    if(age>=flight && target.z<=sceneDepth+0.02)
        color=operaShield(f-b,age-flight,planetary ? 17.0 : 8.0,planetary,color);
    return color;
}

vec3 shipEvent(vec2 fragCoord, vec3 bg) {
    vec2 event=shipSchedule(iTime);
    float age=event.x, seed=event.y;
    if(age<0.0 || iShipGain<=0.0) return bg;
    // The class decides the shape of the event: how many hulls, how far away they fly and how long
    // the flyby lasts. Grand fleets take longer because a big formation needs the time to cross.
    float cls=fleetClass(seed);
    float life = cls>1.5 ? 90.0 : 60.0;
    // Finish all staggered departures before the schedule changes its seed at a slot boundary.
    float slotEnd=age+(70.0-mod(iTime*iWarpRate,70.0))/iWarpRate;
    life=min(life,slotEnd-0.15);
    float cruiseEnd=life-(cls>1.5 ? 6.5 : 3.0);
    if(age>=life) return bg;
    float px=max(floor(iPixelSize),1.0);
    vec3 color=bg;
    float heading=(hash21(vec2(seed,3.0))-0.5)*0.8+(seed>0.60 ? 3.14159265 : 0.0);
    vec2 forward=vec2(cos(heading),sin(heading));
    vec2 side=vec2(-forward.y,forward.x);
    vec2 origin=iResolution*vec2(0.30+0.40*hash21(vec2(seed,9.0)),
        0.28+0.35*hash21(vec2(seed,42.0)));
    int count;
    if(cls<0.5) count=2+int(floor(hash21(vec2(seed,17.0))*2.99));
    else if(cls<1.5) count=4+int(floor(hash21(vec2(seed,17.0))*3.99));
    else count=12+int(floor(hash21(vec2(seed,17.0))*6.99));
    // Far-to-near order is stable. Each craft has its own pose and entry/exit point.
    for(int j=0;j<min(count,18);j++) {
        float id=float(j);
        // Grand fleets stagger a little wider, so the formation unfolds instead of popping at once.
        float t=age-id*(cls>1.5 ? 0.30 : 0.25);
        if(t<=0.0 || t>=cruiseEnd+0.1875) continue;
        float rnd=hash21(vec2(seed*17.0,id+4.0));
        // Grand fleets are all far away: the depth band is narrow and low, so every hull stays
        // small and dim and the formation reads as one distant swarm rather than a line of large
        // near ships. The floor keeps them above the size where a hull would dissolve into stars.
        // Grand fleets are far away, but "far" had reached the point where a hull was a couple of
        // dozen screen pixels and read as nothing at all. The band starts legible and still recedes.
        float depth = cls>1.5 ? 0.34+id*0.014 : 0.42+id*0.080;
        float kind;
        if(cls>1.5) {
            // A dreadnought leads, then a mix of cruisers, frigates and corvette escorts.
            kind = id<1.0 ? 3.0 : (rnd>0.62 ? 1.0 : (rnd>0.34 ? 0.0 : 4.0));
        } else {
            kind = mod(floor(hash21(vec2(seed*13.0,id+31.0))*6.0),6.0);
        }
        float spread=(mod(id,2.0)*2.0-1.0)*(cls>1.5 ? 0.014+0.007*id : 0.04+0.025*id);
        vec2 entry=origin+iResolution.y*(side*spread-forward*id*(cls>1.5 ? 0.014 : 0.037));
        // Speed is derived from the event's own length: the crossing takes the whole cruise instead of a fixed
        // number of pixels per second. With a fixed speed, the longer-lived grand fleet simply left the screen
        // in its first ten seconds and spent the rest of its life - including its warp-out - off-view, which
        // is exactly why the largest formation "never spawned".
        // The fleet must warp out *inside* the frame. At 1.15 screen heights the exit point - and so
        // the whole farewell - sat off-screen: the gate lit up in the distance and the ships had
        // already left, which read as "the effect plays but there are no ships". Half a screen height
        // keeps the crossing, the compression and the gate all in view.
        // Flybys stay put: the squadron warps in, holds station and warps out on the same spot, so the
        // gate and the ships are always in the same frame. Crossing the whole screen meant the exit -
        // and the farewell - regularly happened outside the viewport, which read as "the effect plays
        // but no ships ever appear". A few percent of drift keeps it from looking pinned.
        float speed=iResolution.y*0.045/cruiseEnd;
        vec2 exitPoint=entry+forward*speed*cruiseEnd;
        vec2 center=entry+forward*speed*min(t,cruiseEnd)
            +side*sin(t*0.32+id)*iResolution.y*0.003;
        // Materialise at a legible size. Starting at 8% meant the first second of every warp-in was
        // the gate alone with no ships to see, which is exactly what "the effect plays but no ships
        // appear" describes. 45% from the first frame reads as a squadron arriving, not as a glitch.
        float arrive=clamp(t/0.2125,0.0,1.0);
        float depart=clamp((t-cruiseEnd)/0.1875,0.0,1.0);
        center=mix(center,exitPoint,depart);
        // Load -> release -> brake: a short impulse, not a slow translation.
        float load=clamp(arrive/0.28,0.0,1.0);
        float release=clamp((arrive-0.28)/0.20,0.0,1.0);
        float settle=clamp((arrive-0.48)/0.52,0.0,1.0);
        float easeRelease=1.0-pow(1.0-release,4.0);
        float arrivalOffset=mix(-0.72,-0.95,load);
        if(arrive>=0.28) arrivalOffset=mix(-0.95,0.16,easeRelease);
        if(arrive>=0.48) arrivalOffset=0.16*pow(1.0-settle,3.0);
        float launch=clamp((depart-0.30)/0.70,0.0,1.0);
        float recoil=-0.12*sin(min(depart/0.30,1.0)*1.5707963);
        float exitOffset=recoil+3.2*pow(launch,4.0);
        float kick=px*depth*38.0;
        center+=forward*kick*(arrivalOffset+exitOffset);

        vec2 gateOrigin=center;
        // Gate work only inside its own box: with 14 craft per event this is what keeps the frame
        // cost flat, since most pixels are nowhere near any gate or hull.
        vec2 gateDelta=fragCoord-gateOrigin;
        float gateSpan=60.0*px*(0.5+depth);
        if(abs(gateDelta.x)<gateSpan && abs(gateDelta.y)<gateSpan && (!depthEnabled || 0.72/depth<=sceneDepth)) {
            vec2 gatePixel=(floor(gateDelta/2.0)+0.5)*2.0/px;
            vec2 gateQ=vec2(dot(gatePixel,forward),dot(gatePixel,side));
            float gatePhase=t<0.2125 ? arrive : depart;
            color=warpGate(gateQ,gatePhase,depth,color);
        }
        vec2 encounterClock=operaClock(iTime);
        float distantShot=mod(t,13.0)-2.0-id*0.045;
        if(id<3.0 && encounterClock.x>=0.0 && encounterClock.x<38.0 && distantShot>=0.0 && distantShot<0.30) {
            float z=0.72/depth;
            vec2 launchCenter=center-forward*speed*distantShot;
            vec3 source3=vec3((launchCenter-iResolution*0.5)/iResolution.y*z,z);
            vec3 target3=operaShip(mod(id,4.0),true,encounterClock.x-distantShot);
            color=operaPulse(fragCoord,source3,target3,distantShot,false,color);
        }
        // center is physical pixels; chunkLocal multiplies its center by px.
        vec2 pixel=((fragCoord-center)/px);
        vec2 q=vec2(dot(pixel,forward),dot(pixel,side));
        color=warpTrail(q,t<0.2125 ? arrive : depart,depth,color);
        // Warp-out compresses, it does not stretch: the old factor multiplied the hull by 3.3 at the
        // exit, so instead of pinching away the squadron smeared out of all recognition. The floor
        // keeps the last visible instant legible, exactly like the raiders' departure.
        // Vanish instead of parking at the end of the run. The old floor kept a legible speck alive
        // for the rest of the event, so a fleet that had finished travelling just sat there; letting
        // both axes go to zero means the squadron is swallowed by its own gate and is gone.
        float emergence=mix(0.012,1.0,easeRelease);
        float impulse=sin(release*3.14159265);
        float lengthScale=(emergence+0.55*impulse)*max(0.008,1.0-smoothstep(0.10,0.82,depart));
        float widthScale=mix(0.90,1.0,easeRelease)*max(0.15,1.0-pow(depart,5.0));
        // Portal clipping pulls the hull into the exit rather than deleting it whole.
        if(depart>0.0 && abs(q.x)>max(0.0,(1.0-depart)*48.0*depth)) continue;
        vec2 s=spriteInverse(q,vec2(lengthScale,widthScale)*depth);
        // 1) The bounding gate is only an optimisation: 58x30 hull units is a fraction of a pixel at
        //    depth 0.34, so a whole squadron could fall outside it and never be drawn at all. Keep a
        //    generous box so the gate can only ever skip far-away pixels, never the ship itself.
        // 2) A dark gunmetal hull on a dark nebula reads as nothing. Lift the hull's own pixels - and
        //    only those, since the art function returns the background untouched elsewhere.
        if(abs(s.x)<50.0 && abs(s.y)<20.0) {
            vec3 hull=warshipArt(s,kind,t+rnd,depth,color,armorLight(center/iResolution.y,forward),false);
            if(any(greaterThan(abs(hull-color),vec3(0.002)))) color=depthComposite(color,hull*1.35,0.72/depth);
        }
    }
    return color;
}

vec3 operaEncounter(vec2 f, vec3 color) {
    vec2 clock=operaClock(iTime);float age=clock.x;
    if(age<0.0 || age>38.0) return color;
    // Far fleet first, near fleet second; depth still decides visibility against the mural.
    for(int side=0;side<2;side++) {
        bool enemy=side==0;
        for(int j=3;j>=0;j--) {
            float id=float(j);vec3 world=operaShip(id,enemy,age);
            vec2 center=operaProject(world);
            float scale=0.72/world.z;
            if(world.z>sceneDepth) continue;
            vec3 target=operaShip(0.0,!enemy,age);
            vec2 forward=normalize(operaProject(target)-center);
            vec2 delta=(f-center)/max(floor(iPixelSize),1.0);
            vec2 local=vec2(dot(delta,forward),dot(delta,vec2(-forward.y,forward.x)));
            float enter=clamp((age-id*0.035)/0.2125,0.0,1.0);
            float leave=clamp((age-37.65-id*0.025)/0.1875,0.0,1.0);
            if(enter<=0.0 || leave>=1.0) continue;
            color=metricWake(local,age<1.0 ? enter : leave,scale,color,enemy);
            vec2 q=spriteInverse(local,vec2(max(0.012,enter*(1.0-leave)),1.0)*scale);
            if(abs(q.x)>50.0 || abs(q.y)>20.0) continue;
            vec3 hull=warshipArt(q,j==0 ? 3.0 : float(j-1),age,scale,color,vec2(-0.4,-1),enemy);
            color=depthComposite(color,hull,world.z);
        }
    }
    // One short violent exchange every 11s, with silence between salvos.
    for(int side=0;side<2;side++) for(int j=0;j<3;j++) {
        float lag=float(j)*0.055+float(side)*0.16;
        float shot=mod(age,11.0)-2.0-lag;
        if(shot<0.0 || shot>0.30) continue;
        float launch=age-shot;
        vec3 a=operaShip(float(j),side==0,launch);
        vec3 b=operaShip(float(2-j),side!=0,launch);
        color=operaPulse(f,a,b,shot,false,color);
    }
    // Planetary battery: three nearly simultaneous slugs, a much larger pressure response.
    float aspect=iResolution.x/iResolution.y;
    vec2 city=orbitLane(aspect,1.2,1.0,0.78,0.50,1.0);
    if(city.x>0.0 && city.x<aspect && city.y>0.0 && city.y<1.0) {
        vec2 anchor=city*iResolution.y;
        vec3 world=vec3((anchor-iResolution*0.5)/iResolution.y*2.0,2.0);
        for(int j=0;j<3;j++) {
            float shot=mod(age,19.0)-5.0-float(j)*0.035;
            if(shot>=0.0 && shot<0.28) {
                vec3 target=operaShip(float(j),true,age-shot);
                vec2 bearing=normalize(operaProject(target)-anchor);
                vec2 muzzle=floor(city*iResolution.y)+stationPoint(0.65+float(j)*TAU/3.0)*CITY_R*iResolution.y;
                world.xy=(muzzle-iResolution*0.5)/iResolution.y*world.z;
                color=operaPulse(f,world,target,shot,true,color);
            }
        }
    }
    return color;
}

bool gravityShot(out vec3 source, out vec3 target, out float age) {
    vec2 clock=operaClock(iTime);
    age=clock.x-9.0;
    source=operaShip(0.0,false,9.0);
    target=operaShip(0.0,true,9.0);
    return clock.y<0.32 && age>=0.0 && age<0.16;
}

void renderOperaScene(out vec4 fragColor, in vec2 fragCoord) {
    depthEnabled=true; sceneDepth=1000.0;
    float px = max(floor(iPixelSize),1.0);
    vec2 pixel = floor(fragCoord/px);
    vec2 size = iResolution/px;
    vec2 uv = (pixel+0.5)/size;
    vec2 p = (pixel+0.5)/size.y;
    vec2 screen=fragCoord/iResolution.y;
    float aspect = size.x/size.y;
    // Ink banks cross the complete canvas, leaving a quiet middle — and they are alive. The field
    // crawls in whole logical pixels, its features breathe in size, its boundary waves drift and
    // its cast slides slowly between the mural's violet and its cold teal. The crawl moves the
    // *noise* only: the band boundaries stay anchored in screen space (they compare `uv.y`), so
    // the quiet middle the text sits in can never wander away. Everything reads from the
    // quantised `pixel` via `p`, so the edges stay hard while the shape changes.
    float life = clamp(iNebulaLife,0.0,1.0);
    vec2 crawl = vec2(floor(iTime*life*0.16), floor(iTime*life*0.10));
    vec2 pc = p + crawl/size.y;
    float breathe = 1.0 + 0.16*sin(iTime*life*0.033);
    float wob = sin(iTime*life*0.026);
    float n = noise2(pc*(3.0*breathe))*0.7 + noise2(pc*(7.0*breathe)+11.0)*0.3;
    float wave = 0.72 + 0.025*sin(iTime*life*0.021)
        + (0.13+0.050*wob)*sin(pc.x*(3.7+0.28*wob))
        + (n-0.5)*0.23;
    float upperBase = 0.12 + 0.025*sin(iTime*life*0.018)
        + (0.10+0.040*wob)*sin(pc.x*(3.1+0.20*wob)+1.5*sin(iTime*life*0.013));
    float lower = (uv.y-wave)*8.0;
    float upper = (upperBase+(n-0.5)*0.22-uv.y)*8.0;
    float detailN=noise2(pc*19.0+31.0);
    float bank = max(lower,upper) + (detailN-0.5)*0.18;
    // The ramp is offset down by roughly the half level the dither adds on average, so the banks
    // end up the same width as the solid version while their edge fades instead of stepping.
    float t = clamp((bank+0.21)*2.3*iNebula,0.0,5.0);
    float kf = floor(t);
    // Ordered dither with a hashed jitter: pure Bayer reads as a regular screen-door pattern, pure
    // hash as noise. A mix keeps the pixel-art ramp while losing the regularity.
    float thr = bayer4(pixel)*0.65 + hash21(pixel+3.0)*0.35;
    float up = (fract(t) > thr) ? 1.0 : 0.0;
    float k = kf + up;
    vec3 color = ink(k);
    // Star dust: a sparse sprinkle of single logical pixels inside the banks - the other half of the
    // pixel-art nebula vocabulary, and what gives the surface something to catch the eye.
    if(k>=2.0 && hash21(pixel+7.0)>0.9975)
        color=max(color, vec3(148,162,178)/255.0*max(iStarGain,0.6));
    // Sparse ridges only, following the noise. The old parallel contour ribbons read like a
    // topographic map rather than a nebula, so they are gone.
    if (k>=2.0 && detailN>0.72 && n>0.55 && mod(floor(bank*5.0),4.0)==0.0) color = ink(k+1.0);
    // Cast drift: the ink keeps its value but changes temperature as it crawls. Weighted by `k`, so
    // the quiet middle - and the text sitting on it - cannot shift at all. The dithered cells take a
    // small extra violet cast, which keeps the ramp from reading as a flat poster step.
    float cast=0.5+0.5*sin(iTime*life*0.030 + noise2(pc*2.2)*2.6);
    if(k>=2.0) {
        vec3 warm=vec3(44,34,56)/255.0, cool=vec3(26,48,54)/255.0;
        color=mix(color,mix(warm,cool,cast),0.22);
        if(up>0.5) color=mix(color,warm,0.18);
    }
    vec2 center = orbitLane(aspect,1.2,1.0,0.78,0.50,1.0);       // hero: in frame about half its cycle
    vec2 gas = orbitLane(aspect,4.10,0.87,0.62,0.30,3.2);        // upper lane, rare visitor
    vec2 ochre = orbitLane(aspect,2.30,0.73,0.86,0.72,3.8);      // lower lane
    vec2 ice = orbitLane(aspect,5.40,1.35,0.55,0.14,4.4);        // high and quicker
    vec2 lava = orbitLane(aspect,0.60,0.55,0.70,0.86,5.0);       // slowly along the bottom edge
    // A world far away, slow and only briefly in frame. Drawn first and hazed, so every other body
    // crosses in front of it.
    vec2 farBody = orbitLane(aspect,3.30,0.14,0.30,0.60,2.4);
    vec2 moon = center+vec2(0.27*cos(iTime*iOrbitSpeed*0.009+3.3),
        0.24*sin(iTime*iOrbitSpeed*0.009+3.3));
    vec2 q = bodyLocal(screen,center,CITY_R);
    vec2 gq=bodyLocal(screen,gas,0.15);
    vec2 gr=detailLocal(fragCoord,gas,0.15,2.0);
    vec2 railQ=detailLocal(fragCoord,center,CITY_R,2.0);
    vec2 railFine=detailLocal(fragCoord,center,CITY_R,1.0);
    vec3 beforeFar=color;
    color=planet(screen,farBody,0.042,4.0,color,pixel);
    // Haze: at that distance the body is dimmed and tinted by everything between it and us.
    color=mix(beforeFar,color,0.70);
    // The star field is the background, so it is painted *here* - after the distant world and before
    // every near body. Order is what does the occluding: a planet paints over the stars with its own
    // disk, and the sky beside it keeps them. The old version suppressed stars inside a radius of
    // 1.75 planet radii, which left a starless halo around every body that read as a shadow cast onto
    // the sky; drawing them afterwards instead painted stars over the planets.
    {
        float starCloud=noise2(pixel*0.0031 + 4.7);
        color=max(color,stars(pixel,29.0,0.0,1.0,starCloud)+stars(pixel,47.0,1.0,1.0,starCloud)
            +stars(pixel,71.0,2.2,2.0,starCloud)+stars(pixel,17.0,1.6,1.0,starCloud));
        // The finest layer: single *physical* pixels of dust. Everything else in the mural lives on
        // the 4px block grid; this is a deliberate exception, still hard-edged (no AA, no partial
        // coverage) but fine enough to read as grain between the blocky stars.
        color=starDust(fragCoord,color);
    }
    // Direction from the city world to the scene's fixed lamp, in the planet's own frame. Length is
    // checked because normalise() at exactly zero would hand NaN to the eclipse and the shading.
    vec2 toLampCity=vec2(aspect*0.32,-0.35)-center;
    float toLampCityLen=length(toLampCity);
    vec2 cityLamp=toLampCityLen>1e-4 ? toLampCity/toLampCityLen : vec2(0.0,1.0);
    // Direction from the ringed planet to the scene's fixed lamp, in the planet's own frame: the
    // ring's shaded far side and the ring's shadow across the disk both come from it. The length is
    // checked because normalise() at exactly zero would hand NaN to everything downstream.
    vec2 toLamp=vec2(aspect*0.32,-0.35)-gas;
    float toLampLen=length(toLamp);
    vec2 gasLight=toLampLen>1e-4 ? toLamp/toLampLen : vec2(0.0,1.0);
    if(gr.y<0.27*gr.x) color=depthComposite(color,ring(gr,color,gasLight),2.02);
    color=planet(screen,gas,0.15,0.0,color,pixel);
    // Ring shadow across the disk: the ring's plane crosses it along this band, displaced away
    // from the lamp, and only where the surface is lit enough to show it.
    if(dot(gq,gq)<=1.0 && illumination(gq,gas)>-0.05) {
        float shadowBand=abs(gq.y-0.27*gq.x-0.12*dot(gasLight,normalize(vec2(-0.27,1.0))));
        if(shadowBand<0.085) color*=0.62;
    }
    if(gr.y>=0.27*gr.x) color=depthComposite(color,ring(gr,color,gasLight),1.98);
    color=planet(screen,ochre,0.074,1.0,color,pixel);
    color=planet(screen,ice,0.095,2.0,color,pixel);
    color=planet(screen,lava,0.062,3.0,color,pixel);
    color=planet(screen,moon,0.025,0.0,color,pixel);
    // The planet shades the moon in return: the moon is dark while it sits inside the planet's
    // shadow cylinder, which is what makes an eclipse read as a pair of events.
    vec2 moonLocalShadow=(moon-center)/CITY_R;
    float moonAlong=dot(moonLocalShadow,cityLamp);
    float moonPerp=length(moonLocalShadow-cityLamp*moonAlong);
    if(moonAlong<0.0 && moonPerp<1.05 && distance(screen,moon)<0.027) color*=0.35;
    // One read of the incursion clock, shared by the city world's shield and the raiders below.
    vec2 incClock=incursionSchedule(iTime);
    float incLife=130.0+40.0*hash21(vec2(incClock.y,61.0));
    float incAttack=(incClock.x>3.0 && incClock.x<incLife-3.4) ? incClock.x-3.0 : -1.0;
    vec2 shield=shieldState(incAttack,incClock.y);
    // The orbital ring carries a shield of its own, on its own cycle, so the two never fail together.
    vec2 shieldRail=shieldState(incAttack*0.93+1.7,incClock.y+7.0);
    if(abs(q.x)<1.8 && abs(q.y)<1.5 && (!depthEnabled || sceneDepth>=1.95)) {
        float pixelWidth=1.0/(size.y*CITY_R);
        // The city world carries its own lit-limb halo, drawn before the body so the orbit
        // structures stay in front of it.
        float qlen2=dot(q,q);
        float halo=1.0+1.6*pixelWidth;
        if(qlen2>1.0 && qlen2<halo*halo) {
            float cl=illumination(q,center);
            float cb=lightBand(cl);
            float chalo = cl > 0.15 ? (cb > 3.0 ? 1.0 : 0.45) : (cb < 1.0 ? 0.22 : 0.30);
            color=max(color,vec3(34,56,70)/255.0*(iRim*chalo));
        }
        color=depthComposite(color,infrastructure(railQ,railFine,color,0.0,pixelWidth),2.05);
        if(qlen2<=1.0 && (!depthEnabled || sceneDepth>=2.0)) {
            color=cityPlanet(q,center,pixel);
            if(depthEnabled) sceneDepth=2.0;
            // Solar eclipse: the moon's shadow lands where the ray from the lamp through the moon
            // meets the planet, so the spot is the projection of the moon onto the surface, not the
            // moon's own position (the moon orbits about 1.4 planet radii out). The quadratic is the
            // ray/sphere intersection; the discriminant tests whether that ray passes the planet.
            vec2 moonLocal=(moon-center)/CITY_R;
            float along=dot(moonLocal,cityLamp);
            float disc=along*along-(dot(moonLocal,moonLocal)-1.0);
            if(along>0.0 && disc>0.0) {
                vec2 shadowPoint=moonLocal-cityLamp*(along-sqrt(disc));
                if(length(q-shadowPoint)<0.16) color*=0.42;
            }
        }
        color=depthComposite(color,infrastructure(railQ,railFine,color,1.0,pixelWidth),1.95);
        // The shield is not drawn as a bubble around the world: it only shows where shots hit it, as a
        // small semi-transparent green hexagon at the point of contact (see the raider fire code).
        // The ring's own shield is the one structure that is visible as a shape.
        // The orbit ring is shielded too, but that shield is only ever visible as the hexagon glint at the
        // point of contact - no outline is drawn around the rail or the world.
    }
    color*=iSceneGain;
    // Foreground points never paint across the silhouettes of the planets.
    // Foreground points never paint across the silhouettes of the planets. The distant world is
    // deliberately left out of this test: stars in front of it are what sell its distance.
    color=shipEvent(fragCoord,color);
    color=depthComposite(color,asteroidGroup(fragCoord,pixel,size,color),2.7);
    color=patrolPass(fragCoord,pixel,size,color);
    color=depthComposite(color,structurePass(fragCoord,pixel,size,color),2.3);
    color=incursionEvent(fragCoord,pixel,size,center,CITY_R,shield.x,shieldRail.x,color);
    color=operaEncounter(fragCoord,color);
    color=cometPixel(fragCoord,pixel,size,color);
    color=meteorPixel(fragCoord,pixel,size,color);
    fragColor=vec4(color*max(iBrightness,0.0),1.0);
}

void mainImage(out vec4 fragColor,in vec2 fragCoord) {
    renderOperaScene(fragColor,fragCoord);
    float surfaceDepth=sceneDepth;
    vec3 a3,b3;float age;
    if(!gravityShot(a3,b3,age)) return;
    vec2 a=operaProject(a3),b=operaProject(b3);
    vec2 v=b-a;float len=max(length(v),1.0);vec2 dir=v/len;
    vec2 normal=vec2(-dir.y,dir.x);
    float along=dot(fragCoord-a,dir), across=dot(fragCoord-a,normal);
    float head=clamp(age/0.035,0.0,1.0)*len;
    if(along<0.0 || along>head || abs(across)>24.0) return;
    float z=mix(a3.z,b3.z,clamp(along/len,0.0,1.0));
    if(surfaceDepth<z-0.02) return;
    // Re-evaluate the actual procedural scene through a localized deflection field.
    // Foreground occluders are tested before the second evaluation.
    float envelope=sin(clamp(age/0.16,0.0,1.0)*3.14159265);
    float bend=sign(across)*min(12.0,55.0/(abs(across)+3.0))*envelope;
    renderOperaScene(fragColor,fragCoord+normal*bend);
    // Subpixel coverage for a one-physical-pixel black core, even on a diagonal.
    float coverage=1.0-smoothstep(0.20,0.80,abs(across));
    fragColor.rgb=mix(fragColor.rgb,vec3(0),coverage*envelope);
}
