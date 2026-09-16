/*! par-term shader metadata
name: Kanagawa - Starbound
author: Codex
description: Flat retro space mural, ink-blue nebula banks, cut-paper planets and quiet pixel stars. Texture-free; banded day/night lighting with a real terminator, restrained lit-limb atmospheres, ring shadows, coast-hugging city lights, eclipses, comets, depth-layered star drifts, breathing nebula banks and fleets that range from a lone squadron to a grand fleet warping in at a distance.
version: 4.7.0
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
vec2 orbitLane(float aspect, float phase, float rate, float amp, float mid, float spanScale) {
    float span=(aspect+2.0*amp+0.6)*spanScale;
    float start=fract(phase/TAU);
    float x=mod(start+iTime*iOrbitSpeed*rate*0.0022/spanScale, 1.0)*span-(amp+0.2);
    return vec2(x,mid);
}
float illumination(vec2 q, vec2 center) {
    vec2 lamp=vec2(iResolution.x/iResolution.y*0.32,-0.35);
    vec3 light=normalize(vec3(lamp-center,0.42));
    vec3 normal=vec3(q,sqrt(max(0.0,1.0-dot(q,q))));
    return dot(normal,light);
}
// One lighting model for every body. `illumination` is the raw Lambert dot against the scene's
// fixed lamp; this quantises it into five flat bands centred on the real terminator (dot = 0)
// instead of on hand-picked cut points. Band 0 is night, band 1 is the narrow twilight strip
// where the sun is setting, and 2..4 are the day side in three steps. The mural stays poster-flat,
// but the day/night boundary now sits where the light says it does, and every zone has a name the
// callers can draw with.
float lightBand(float d) {
    if (d < -0.06) return 0.0;
    if (d <  0.06) return 1.0;
    if (d <  0.34) return 2.0;
    if (d <  0.62) return 3.0;
    return 4.0;
}
// Each sprite owns its 4px grid. Its origin moves in physical 1px increments;
// it is no longer trapped on the background's fixed 4px grid.
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
// 2x2 and 4x4 ordered dither thresholds. Dithering a band boundary is the traditional pixel-art way
// to fake a smooth ramp: the cells stay hard pixels, but at a distance the ramp reads as a gradient
// instead of a poster step. Sampled on the logical pixel grid, so the pattern is part of the art.
float bayer2(vec2 a) { a=floor(a); return fract(a.x/2.0 + a.y*a.y*0.75); }
float bayer4(vec2 a) { return bayer2(0.5*a)*0.25 + bayer2(a); }
// Discrete palette: no bloom, continuous gradients or screen-space dithering.
vec3 ink(float k) {
    if (k < 1.0) return vec3(0.0);
    if (k < 2.0) return vec3(12, 14, 23) / 255.0;
    if (k < 3.0) return vec3(22, 27, 43) / 255.0;
    if (k < 4.0) return vec3(32, 42, 61) / 255.0;
    if (k < 5.0) return vec3(45, 61, 78) / 255.0;
    return vec3(65, 82, 99) / 255.0;
}
// Distance to the boundary of a regular hexagon of radius r: zero on the edge. The three dot products
// are the hexagon's own normals, so this is exact enough for a one-pixel outline and cheap.
float hexEdge(vec2 v, float r) {
    float d=max(max(abs(v.x),abs(v.x*0.5+v.y*0.8660254)),abs(v.x*0.5-v.y*0.8660254));
    return abs(d-r);
}
// Fast movers are placed on the logical pixel grid before they are drawn, exactly the way `bodyLocal`
// places the planets. Without this their silhouette lands between pixels, so every frame boils it a
// fraction of a pixel - the crawl that read as a smear at speed.
vec2 snapPixel(vec2 v) { return floor(v)+0.5; }
// Snap to the physical pixel grid rather than the 4px block grid. The block grid is right for objects
// drawn as blocks, but at the belt's speed it made every rock advance in visible 4px jumps with a still
// frame in between - 4px, 0px, 4px - which reads as stutter. Field sampling is still on the block grid,
// so the shape stays pixel art while the motion becomes smooth.
vec2 snapFine(vec2 v) { float p=max(floor(iPixelSize),1.0); return floor(v*p)/p; }
// Quantise a 0..1 weight into `steps` levels with a dithered edge. Same idea as the nebula ramp: the
// cells stay hard pixels, but at a distance the level change reads as a soft band rather than a line.
float ditherLevel(float v, vec2 pixel, float steps) {
    float x = clamp(v,0.0,1.0)*steps;
    float lo = floor(x);
    float thr = bayer4(pixel)*0.65 + hash21(pixel+3.0)*0.35;
    return (lo + (fract(x) > thr ? 1.0 : 0.0))/steps;
}
// Forward declarations: the event code below uses the fleet's own hulls and gates, which are defined
// further down with the rest of the fleet. Declared here, above every user, or GLSL has no prototype.
vec3 warpGate(vec2 q, float phase, float depth, vec3 bg);
vec3 fleetHull(vec2 s, float kind, float age, float depth, vec3 bg);
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
    float stripe = floor(ribbons * 18.0);
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
        float crack=abs(fract(surface.y*6.0+surface.x*1.5)-0.5);
        if(band>1.5 && crack<0.05) c=mix(c, vec3(150,168,178)/255.0, 0.55);
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
    c = mix(c, vec3(104,74,54)/255.0, 0.80*warm*iRim);
    if (r2 > 1.0 - 2.0*limb) {
        if (band > 3.0) c = mix(c, vec3(83,116,130)/255.0, 0.35*iRim);
        else if (band > 1.5) c = mix(c, vec3(58,80,94)/255.0, 0.30*iRim);
        else c = mix(c, vec3(30,46,60)/255.0, 0.35*iRim);
    }
    return c;
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
    float cloud=noise2((sc+vec2(q.y*0.35,0.0))*3.6+31.0);
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
    if(cloud>0.76) albedo=mix(albedo, vec3(140,148,150)/255.0, 0.70);
    else if(cloud>0.58) albedo=mix(albedo, vec3(112,120,124)/255.0, 0.58);
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
        if(j==1) {hub=vec2(-0.38,0.20); radius=0.24;}
        if(j==2) {hub=vec2(0.18,-0.53); radius=0.19;}
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
            vec3 core=vec3(118,122,118)/255.0;
            vec3 pave=vec3(132,136,132)/255.0;
            vec3 concrete=vec3(92,96,96)/255.0;
            vec3 kerb=vec3(70,74,76)/255.0;
            if(metropolis>0.0) albedo=mix(albedo, mRing>0.5 ? kerb : concrete, 0.70*iCityGain);
            if(mCore>0.5) albedo=mix(albedo, core, 0.65*iCityGain);
            if(mSpoke>0.5) albedo=mix(albedo, pave, 0.70*iCityGain);
            if(mLink>0.5) albedo=mix(albedo, pave, 0.55*iCityGain);
            if(tower) albedo=mix(albedo, vec3(124,128,124)/255.0, 0.55*iCityGain);
            else if(road) albedo=mix(albedo, vec3(108,112,110)/255.0, 0.45*iCityGain);
        } else {
            float night=band<0.5 ? 1.25 : 0.50;
            lights=max(lights, neon*level*night*iCityGain);
        }
    }
    // Quantised lighting of that one surface, dithered so the five steps read as a ramp: the
    // terminator is a soft band of hard pixels, not a drawn edge. The night half keeps a cold cast.
    float lit = 0.18 + 0.82*ditherLevel(clamp((light+0.10)*1.25, 0.0, 1.0), pixel, 8.0);
    vec3 c = albedo*lit;
    if(light<0.06) c=mix(c, c*vec3(0.78,0.90,1.15), 0.55);
    c=max(c, lights);
    // The same three-zone limb as the natural bodies: a dithered sunset cast, a lit inner rim, and a
    // faint cool rim on the night side so the unlit half keeps its silhouette.
    float rq=dot(q,q);
    float warm = ditherLevel(clamp(1.0 - abs(light)*4.0, 0.0, 1.0), pixel, 3.0);
    c = mix(c, vec3(108,78,56)/255.0, 0.80*warm*iRim);
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
vec3 infrastructure(vec2 q, vec3 bg, float front, float pixelWidth) {
    // Back rail before the body, front rail afterwards: no see-through structures.
    vec2 e=vec2(q.x+0.30*q.y,q.y-0.30*q.x)/1.09;
    bool frontHalf=e.y>=0.0;
    vec3 c=bg;
    if(frontHalf == (front>0.5)) {
        float rail=length(e/vec2(1.52,0.42));
        if(abs(rail-1.0)<pixelWidth*1.5) c=vec3(43,67,79)/255.0;
    }
    for(int j=0;j<3;j++) {
        float a=0.65+float(j)*TAU/3.0;
        vec2 anchor=stationPoint(a);
        vec2 foot=anchor*0.53;
        bool isFront=sin(a)>=0.0;
        if(isFront != (front>0.5)) continue;
        if(segmentDistance(q,foot,anchor)<pixelWidth*0.65) c=vec3(54,72,85)/255.0;
        vec2 d=abs(q-anchor);
        if(d.x<0.07 && d.y<0.035) c=vec3(65,91,107)/255.0;
        float lift=0.5+0.5*sin(iTime*iCityFlow*0.13+float(j)*2.1);
        vec2 cabin=mix(foot,anchor,lift);
        if(max(abs(q.x-cabin.x),abs(q.y-cabin.y))<pixelWidth*1.2)
            c=vec3(128,143,128)/255.0*iCityGain;
    }
    for(int j=0;j<3;j++) {
        float a=iTime*iCityFlow*0.022+float(j)*TAU/3.0;
        if((sin(a)>=0.0) != (front>0.5)) continue;
        vec2 ship=stationPoint(a);
        if(max(abs(q.x-ship.x),abs(q.y-ship.y))<pixelWidth*1.5)
            c=vec3(122,167,160)/255.0*iCityGain;
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
// The finest layer: single physical pixels of dust, sampled in screen space rather than on the
// logical block grid. It is the one element that is not quantised to iPixelSize, and it is still
// hard-edged - just finer grain between the blocky stars.
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
// Stateless comet schedule: long quiet stretches, then one streak. Same deterministic idea as the
// ship schedule, over a longer period, and it goes quiet together with the ships when the event
// frequency control is turned off.
vec2 cometSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/240.0);
    float seed=hash21(vec2(slot,137.0));
    if(seed<0.38) return vec2(-100.0,seed);
    float delay=20.0+150.0*hash21(vec2(slot,53.0));
    return vec2((mod(clock,240.0)-delay)/iWarpRate,seed);
}
// A comet: a hard-edged head with a stepped tail, all quantised to the logical pixel grid so the
// streak is as crisp as the stars it crosses.
vec3 cometPixel(vec2 pixel, vec2 size, vec3 color) {
    // `px` cancels in the ratio, so this is the same aspect mainImage works with.
    float aspect=size.x/size.y;
    vec2 ev=cometSchedule(iTime);
    float age=ev.x, seed=ev.y;
    // Duration and tail length vary per event, so a comet is not the same streak every time.
    float life=6.0+6.0*hash21(vec2(seed,23.0));
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
    vec2 head=snapFine(mix(start,endp,progress)*size.y);
    vec2 dir=normalize(endp-start);   // the same direction in logical pixels (uniform scaling)
    vec2 rel=pixel-head;
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
        vec2 dd=pixel-bp;
        float sz=f<0.18 ? 2.0 : (f<0.45 ? 1.0 : 0.5);
        if(abs(dd.x)>sz || abs(dd.y)>sz) continue;
        vec3 tone = f<0.18 ? vec3(190,214,232)/255.0
            : (f<0.42 ? vec3(128,158,182)/255.0
            : (f<0.70 ? vec3(78,102,128)/255.0 : vec3(44,60,84)/255.0));
        color=max(color,tone*max(iStarGain,0.70)*(1.0-progress*0.35));
    }
    return color;
}
// Fleet class from the event seed: a lone squadron (0), a standard task force (1), or a grand fleet
// warping in out at a distance (2). Deterministic per event slot, like everything else here.
float fleetClass(float seed) {
    float r=hash21(vec2(seed,211.0));
    if(r<0.30) return 0.0;
    if(r<0.82) return 1.0;
    return 2.0;
}
// A shooting star: a fraction of a second across the sky, one pixel wide with a short trail. Its own
// schedule is much shorter than a comet's (45 s slots, about half of them quiet), so these punctuate
// the scene without turning into a show.
vec2 meteorSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/45.0);
    float seed=hash21(vec2(slot,613.0));
    if(seed<0.45) return vec2(-100.0,seed);
    float delay=4.0+34.0*hash21(vec2(slot,17.0));
    return vec2((mod(clock,45.0)-delay)/iWarpRate,seed);
}
vec3 meteorPixel(vec2 pixel, vec2 size, vec3 color) {
    float aspect=size.x/size.y;
    vec2 ev=meteorSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=0.55+0.55*hash21(vec2(seed,29.0));
    if(age>life) return color;
    float progress=age/life;
    // Four crossings, so it does not always cut the same way. Entry and exit are in screen units.
    float run=hash21(vec2(seed,19.0));
    vec2 start,endp;
    if(run<0.34)      { start=vec2(-0.10,0.05+0.40*hash21(vec2(seed,7.0))); endp=vec2(aspect+0.10,0.45+0.45*hash21(vec2(seed,11.0))); }
    else if(run<0.62) { start=vec2(aspect+0.10,0.05+0.40*hash21(vec2(seed,7.0))); endp=vec2(-0.10,0.45+0.45*hash21(vec2(seed,11.0))); }
    else if(run<0.82) { start=vec2(0.10+0.80*hash21(vec2(seed,7.0)),-0.08); endp=vec2(0.10+0.80*hash21(vec2(seed,11.0)),1.08); }
    else              { start=vec2(-0.10,0.70+0.28*hash21(vec2(seed,7.0))); endp=vec2(aspect+0.10,0.06+0.30*hash21(vec2(seed,11.0))); }
    vec2 head=snapFine(mix(start,endp,progress)*size.y);
    vec2 dir=normalize(endp-start);
    vec2 rel=pixel-head;
    // Head: a single logical pixel, brighter than anything else in the sky.
    if(abs(rel.x)<1.0 && abs(rel.y)<1.0)
        return max(color,vec3(238,244,252)/255.0*max(iStarGain,0.8));
    // Trail: beads on the lattice, like the comet's, so a fast streak does not crawl sideways.
    vec2 dirPx=normalize(vec2(floor(dir.x*4.0+0.5)*0.25,floor(dir.y*4.0+0.5)*0.25)+vec2(0.0,1e-4));
    float tail=10.0+12.0*hash21(vec2(seed,37.0));
    for(int k=1;k<=8;k++) {
        float f=float(k)/8.0;
        vec2 bp=snapFine(head-dirPx*(tail*f));
        vec2 dd=pixel-bp;
        if(abs(dd.x)>0.5 || abs(dd.y)>0.5) continue;
        vec3 tone = f<0.4 ? vec3(186,206,228)/255.0 : vec3(98,120,148)/255.0;
        color=max(color,tone*max(iStarGain,0.7)*(1.0-progress*0.35));
    }
    return color;
}
// A patrol: hulls that simply cruise across on the planets' slow lane with no warp gates at all - motion
// to live with rather than an event. Position is snapped to the physical pixel grid like every other
// moving object, so it glides instead of stepping.
vec2 patrolSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/260.0);
    float seed=hash21(vec2(slot,5077.0));
    if(seed<0.35) return vec2(-100.0,seed);
    float delay=8.0+40.0*hash21(vec2(slot,59.0));
    return vec2((mod(clock,260.0)-delay)/iWarpRate,seed);
}
vec3 patrolPass(vec2 pixel, vec2 size, vec3 color) {
    float aspect=size.x/size.y;
    vec2 ev=patrolSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=150.0+40.0*hash21(vec2(seed,67.0));
    if(age>life) return color;
    float progress=age/life;
    float lane=0.10+0.80*hash21(vec2(seed,13.0));
    vec2 start=vec2(-0.14,lane);
    vec2 endp=vec2(aspect+0.14,lane);
    int count=1+int(floor(hash21(vec2(seed,71.0))*2.99));
    for(int k=0;k<3;k++) {
        if(k>=count) continue;
        float id=float(k);
        float r1=hash21(vec2(seed*17.0,id+3.0));
        // A gentle weave, so a patrol does not look like it is running on rails.
        float weave=sin(progress*8.2+id*2.1)*0.012+sin(progress*17.0+id)*0.005;
        vec2 p2p=mix(start,endp,progress)*size.y+vec2(0.0,weave*size.y)
            -vec2(1.0,0.0)*id*(0.05+0.02*r1)*size.y;
        vec2 d=pixel-snapFine(p2p);
        if(abs(d.x)>46.0 || abs(d.y)>26.0) continue;
        // The fleet's own hulls, unscaled: a patrol is not warping, so nothing compresses.
        float kind=mod(floor(hash21(vec2(seed*7.0,id+11.0))*3.0),3.0);
        color=fleetHull(d/0.95,kind,age*0.5+id,0.95,color);
    }
    return color;
}
// A drifting structure: a stargate or a station, crossing on the planets' slow lane rather than with
// the fast traffic. Slot and life are sized so a pass finishes inside its slot - a life longer than the
// slot would cut the structure off mid-flight when `age` wraps.
vec2 structureSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/150.0);
    float seed=hash21(vec2(slot,3079.0));
    if(seed<0.35) return vec2(-100.0,seed);
    float delay=5.0+35.0*hash21(vec2(slot,41.0));
    return vec2((mod(clock,150.0)-delay)/iWarpRate,seed);
}
vec3 structurePass(vec2 pixel, vec2 size, vec3 color) {
    float aspect=size.x/size.y;
    vec2 ev=structureSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    // Slow: a couple of minutes to cross, the way the planets move.
    float life=70.0+35.0*hash21(vec2(seed,53.0));
    if(age>life) return color;
    float progress=age/life;
    float lane=0.12+0.76*hash21(vec2(seed,11.0));
    vec2 center=snapFine(mix(vec2(-0.12,lane),vec2(aspect+0.12,lane),progress)*size.y
        +vec2(0.0,sin(progress*6.2831853)*0.008*size.y));
    float r=(0.036+0.024*hash21(vec2(seed,23.0)))*size.y;   // logical pixels
    vec2 d=pixel-center;
    if(abs(d.x)>r*1.8 || abs(d.y)>r*1.8) return color;
    if(hash21(vec2(seed,31.0))<0.5) {
        // Stargate: two hard rings, four pylons, and a slow dithered shimmer in the mouth.
        float rr=length(d);
        if(abs(rr-r)<1.7) color=max(color,vec3(96,140,166)/255.0);
        if(abs(rr-r*0.66)<1.5) color=max(color,vec3(132,180,200)/255.0);
        for(int k=0;k<4;k++) {
            float a=float(k)*1.5707963+0.4;
            vec2 dd=d-vec2(cos(a),sin(a))*r*0.83;
            if(abs(dd.x)<2.4 && abs(dd.y)<2.4) color=max(color,vec3(74,106,128)/255.0);
        }
        if(rr<r*0.62) {
            float li=ditherLevel(0.22+0.40*(0.5+0.5*sin(iTime*0.35+seed*20.0)), pixel, 4.0);
            color=max(color,mix(vec3(26,44,62)/255.0, vec3(118,172,194)/255.0, li));
        }
    } else {
        // Station, built the way the planets are: one light direction, a small cool-grey palette, and
        // detail that reads at a glance - a banded spine, a spun habitation ring whose lit windows orbit
        // with it, framed solar wings on struts, docking arms with lit ports, a red/teal navigation pair
        // and a blinking beacon mast.
        vec3 dark=vec3(46,50,58)/255.0, mid=vec3(78,84,94)/255.0, lit=vec3(114,120,130)/255.0;
        vec3 bright=vec3(152,158,166)/255.0, win=vec3(198,176,120)/255.0;
        float glow=abs(d.x*0.7+d.y*1.2);                    // light from the upper left
        // Spine: segment bands, brighter on the lit side.
        if(abs(d.x)<2.6 && abs(d.y)<r*1.05) {
            vec3 tone=lit;
            if(d.x>0.4) tone=bright;
            else if(d.x<-0.4) tone=mid;
            if(mod(floor(d.y/3.5),2.0)<1.0) tone=dark;
            color=max(color,tone);
        }
        // Hub: where the mast, the arms and the ring meet.
        if(abs(d.x)<r*0.30 && abs(d.y)<r*0.17) color=max(color,mid);
        if(abs(d.x)<r*0.19 && abs(d.y)<r*0.10) color=max(color,lit);
        // Habitation ring: it spins, so its windows orbit the station.
        float ringD=abs(length(d)-r*0.62);
        if(ringD<1.8) {
            color=max(color, glow<r*0.35 ? bright : mid);
            float ang2=atan(d.y,d.x)-iTime*0.35-seed*9.0;
            if(mod(floor(ang2*3.8),3.0)<1.0) color=max(color,win);
        }
        // Solar wings: strut, frame, and a checkered panel face.
        for(int w=0;w<2;w++) {
            float sy=(w==0 ? 1.0 : -1.0);
            vec2 q=vec2(d.x,d.y-sy*r*0.74);
            if(abs(q.x)<1.3 && abs(q.y)<r*0.32) color=max(color,mid);
            float px1=r*1.55, py=r*0.31;
            if(abs(q.x)>r*0.30 && abs(q.x)<px1 && abs(q.y)<py) {
                vec3 panel=vec3(40,58,88)/255.0;
                if(mod(floor(q.x/2.0)+floor(q.y/2.0),2.0)<1.0) panel=vec3(58,82,118)/255.0;
                color=max(color,panel);
                if(abs(q.x)<r*0.30+1.3 || abs(q.x)>px1-1.3 || abs(q.y)>py-1.3) color=max(color,lit);
            }
        }
        // Docking arms with pods, lit ports, and a red / teal navigation pair.
        for(int w=0;w<2;w++) {
            float sx=(w==0 ? 1.0 : -1.0);
            vec2 q=vec2(d.x-sx*r*0.66,d.y);
            if(abs(q.y)<1.3 && abs(q.x)<r*0.42) color=max(color,mid);
            if(abs(q.x-r*0.48)<3.2 && abs(q.y)<3.2) {
                color=max(color, glow<2.0 ? lit : mid);
                if(abs(q.x-r*0.48)<1.5 && abs(q.y)<1.5) color=max(color,win);
            }
            if(abs(q.x-r*0.56)<1.2 && abs(q.y)<1.2)
                color=max(color, w==0 ? vec3(195,64,67)/255.0 : vec3(106,149,137)/255.0);
        }
        // Beacon mast, with a slow blink at the tip.
        if(abs(d.x)<0.9 && d.y<-r*1.0 && d.y>-r*1.45) color=max(color,mid);
        if(length(d-vec2(0.0,-r*1.48))<1.7 && 0.5+0.5*sin(iTime*1.6+seed*10.0)>0.45)
            color=max(color,vec3(226,120,110)/255.0);
        // Lit windows in the spine's unbanded segments.
        if(abs(d.x)<2.6 && abs(d.y)<r*1.0 && mod(floor(d.y/3.5),2.0)>=1.0
            && hash21(floor(d/3.0)+vec2(seed*13.0))>0.55)
            color=max(color,win);
    }
    return color;
}
// A drifting asteroid group: a belt of small rocks that sweeps past far faster than any planet, on its
// own schedule (150 s slots, a little under half of them quiet).
vec2 asteroidSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/150.0);
    float seed=hash21(vec2(slot,941.0));
    if(seed<0.42) return vec2(-100.0,seed);
    float delay=10.0+110.0*hash21(vec2(slot,37.0));
    return vec2((mod(clock,150.0)-delay)/iWarpRate,seed);
}
vec3 asteroidGroup(vec2 pixel, vec2 size, vec3 color) {
    float aspect=size.x/size.y;
    vec2 ev=asteroidSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=30.0+15.0*hash21(vec2(seed,53.0));
    if(age>life) return color;
    float progress=age/life;
    // A shallow lane across the sky, travelling the scene's direction. `life` is short compared with a
    // planet's crossing, so the belt reads as fast even though it is drawn at the same scale.
    float lane=0.10+0.80*hash21(vec2(seed,11.0));
    vec2 start=vec2(-0.18, lane);
    vec2 endp=vec2(aspect+0.18, lane+(hash21(vec2(seed,23.0))-0.5)*0.30);
    vec2 center=mix(start,endp,progress)*size.y;
    vec2 dir=normalize(endp-start);
    vec2 side=vec2(-dir.y,dir.x);
    int count=14+int(floor(hash21(vec2(seed,71.0))*12.0));
    for(int j=0;j<26;j++) {
        if(j>=count) continue;
        float id=float(j);
        float r1=hash21(vec2(seed*13.0,id+5.0));
        float r2=hash21(vec2(seed*29.0,id+9.0));
        // Rocks trail the group centre, strung out along the direction of travel and spread across it,
        // with the belt opening up a little as it crosses.
        vec2 rock = snapFine(center - dir*(r1*0.30+progress*0.16)*size.x*0.45 + side*(r2-0.5)*0.30*size.y);
        vec2 d = pixel-rock;
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
        float lobe=0.76+0.24*(0.5+0.5*sin(ang*3.0+float(id)*2.1))*(0.55+0.45*cos(ang*5.0+float(id)*1.3));
        float rr=wr*lobe;
        float dd=dot(d,d);
        if(dd > rr*rr) continue;
        float g = d.x*0.7 + d.y*1.2;
        vec3 tone = vec3(88,90,96)/255.0;
        if(g < -wr*0.30) tone = vec3(124,126,132)/255.0;
        else if(g > wr*0.35) tone = vec3(50,52,60)/255.0;
        if(dd > (rr-1.8)*(rr-1.8) && g < 0.0) tone = vec3(150,152,156)/255.0;   // rim light
        // Two craters fixed to the rock itself, not to the grid: a lattice would slide across the
        // surface as the rock travelled.
        if(length(d-vec2(wr*0.34,wr*0.16))<wr*0.30 || length(d+vec2(wr*0.30,wr*0.34))<wr*0.22)
            tone = vec3(36,38,46)/255.0;
        color=max(color,tone);
    }
    return color;
}
// (Hulls and gates are declared above, with the other helpers: the patrol below uses them.)
// The city world's shield, read off the incursion clock: it forms, strains as hits land, fails, stays
// down, then comes back. No state is kept between frames - it is all a function of event time.
// x = strength (0 = down), y = the flash left over from the break.
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
// Raiders are shot down one at a time by the orbital ring, so the volley thins out as it runs.
// The timings are scaled to a 30-40 second engagement, not the old 13-second dash.
float raiderDownTime(float id, float seed) {
    return 8.0+2.6*id+1.6*hash21(vec2(seed,97.0+id));
}
// The defending squadron loses ships too, on its own timetable.
float defenderDownTime(float id, float seed) {
    return 12.0+2.8*id+1.6*hash21(vec2(seed,131.0+id));
}
vec2 defenderPos(vec2 formation, vec2 forward, vec2 sidev, float id, float seed, vec2 size) {
    float r1=hash21(vec2(seed*23.0,id+7.0));
    return formation+sidev*(r1-0.5)*0.12*size.y-forward*id*0.030*size.y;
}
vec2 raiderPos(vec2 formation, vec2 forward, vec2 sidev, float id, float seed, vec2 size) {
    float r1=hash21(vec2(seed*11.0,id+5.0));
    return formation+sidev*(r1-0.5)*0.11*size.y-forward*id*0.035*size.y;
}
// A hostile incursion: an alien squadron warps in, fires on a world, and warps back out. It keeps its
// own long slot (roughly every 5-10 minutes) so it stays an event rather than the new normal.
vec2 incursionSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/200.0);
    float seed=hash21(vec2(slot,1597.0));
    if(seed<0.30) return vec2(-100.0,seed);
    float delay=10.0+80.0*hash21(vec2(slot,29.0));
    return vec2((mod(clock,200.0)-delay)/iWarpRate,seed);
}
// Alien hulls: angular and spined, lit in crimson rather than the fleet's teal, so the two sides can
// never be confused at a glance.
vec3 alienHull(vec2 s, float kind, float age, float depth, vec3 bg) {
    float sy=abs(s.y);
    bool hull=false;
    if(kind<0.5) {
        // Scythe: a swept arrowhead with a rear spine.
        hull=(s.x>=-20.0 && s.x<=26.0 && sy<=max(1.0,7.0-(s.x+20.0)*0.18))
            || (s.x>=-26.0 && s.x<=-4.0 && sy>=6.0 && sy<=10.0);
    } else if(kind<1.5) {
        // Crab: a broad body with two forward claws.
        hull=(s.x>=-18.0 && s.x<=20.0 && sy<8.0)
            || (s.x>10.0 && s.x<28.0 && sy>3.0 && sy<9.0)
            || (s.x>10.0 && s.x<28.0 && sy<-3.0 && sy>-9.0);
    } else if(kind<2.5) {
        // Spire: narrow and tall, like a hive.
        hull=(s.x>=-14.0 && s.x<=14.0 && sy<14.0)
            || (s.x>=-8.0 && s.x<=8.0 && sy<22.0)
            || (s.x>-20.0 && s.x<20.0 && sy<3.0);
    } else if(kind<3.5) {
        // Manta: a wide delta with swept wings and a notched tail.
        hull=(s.x>=-16.0 && s.x<=22.0 && sy<=max(2.0,13.0-(s.x+16.0)*0.28))
            || (s.x>=-24.0 && s.x<=-8.0 && sy>=9.0 && sy<=14.0)
            || (s.x>=-24.0 && s.x<=-8.0 && sy<=2.0);
    } else {
        // Hive mother: an elongated pod carrier with hangar bays along the spine.
        hull=(s.x>=-40.0 && s.x<=34.0 && sy<9.0)
            || (s.x>=-30.0 && s.x<18.0 && sy>11.0 && sy<17.0)
            || (s.x>-34.0 && s.x<-24.0 && sy<20.0)
            || (s.x>-6.0 && s.x<8.0 && sy<20.0);
    }
    vec3 c=bg;
    if(hull) {
        vec3 shell=vec3(64,48,78)/255.0;
        if(s.y<0.0) shell=vec3(102,70,106)/255.0;
        if(sy<2.0) shell=vec3(142,90,114)/255.0;
        if(mod(floor(s.x)+30.0,7.0)<1.0 && sy>2.0) shell=vec3(44,32,54)/255.0;
        // Crimson sensor band and gun ports: what makes it read as hostile.
        if(s.x>-6.0 && s.x<10.0 && sy<2.5 && mod(floor(s.x),3.0)<1.0)
            shell=vec3(220,84,94)/255.0;
        if(kind>3.5 && sy>11.0 && sy<17.0 && mod(floor(s.x)+14.0,5.0)<2.0)
            shell=vec3(198,68,104)/255.0;
        if(kind>2.5 && kind<3.5 && sy>4.0 && sy<9.0 && mod(floor(s.x)+20.0,4.0)<1.0)
            shell=vec3(188,64,92)/255.0;
        c=shell*(0.66+0.34*depth);
    }
    float engineX=kind>3.5 ? -40.0 : (kind>2.5 ? -24.0 : (kind>1.5 ? -14.0 : (kind>0.5 ? -18.0 : -20.0)));
    float flame=3.0+2.0*sin(age*3.1);
    if(s.x<engineX && s.x>engineX-flame*1.6 && (abs(sy-2.0)<1.4 || abs(sy-6.0)<1.4))
        c=max(c,vec3(214,84,132)/255.0*depth);
    return c;
}
// The fleet's warp ring, recoloured for the other side.
vec3 alienGate(vec2 q, float phase, float depth, vec3 bg) {
    if(phase<=0.0 || phase>=1.0) return bg;
    float opening=sin(phase*3.14159265);
    float r=length(q/vec2(2.0+11.0*opening,4.0+23.0*opening));
    vec3 c=bg;
    if(r<0.82) c*=0.35;
    if(abs(r-1.0)<0.075) c=max(c,vec3(196,64,96)/255.0*opening);
    if(abs(r-1.26)<0.04) c=max(c,vec3(148,66,178)/255.0*opening);
    if(abs(q.y)<1.0 && abs(q.x)<(11.0+36.0*opening))
        c=max(c,vec3(214,86,104)/255.0*opening);
    return c;
}
// One incursion: warp in (2 s), volley at the target world, warp out (2.4 s). Everything is a pure
// function of shader time - gunfire included - so the event needs no state across frames.
vec3 incursionEvent(vec2 fragCoord, vec2 pixel, vec2 size, vec2 target, float targetR, float shieldStr, float railShieldStr, vec3 color) {
    float aspect=size.x/size.y;
    vec2 ev=incursionSchedule(iTime);
    float age=ev.x, seed=ev.y;
    if(age<0.0) return color;
    float life=30.0+10.0*hash21(vec2(seed,61.0));
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
    for(int j=0;j<9;j++) {
        if(j>=count) continue;
        float id=float(j);
        // Shot-down raiders are gone before they can fire again.
        if(age>raiderDownTime(id,seed)) continue;
        // Each craft arrives on its own beat rather than the whole line popping in at once.
        float inS=clamp((age-1.6-id*0.45)/2.2,0.0,1.0);
        if(inS<=0.0) continue;
        vec2 center=snapFine(raiderPos(formation,forward,sidev,id,seed,size));
        // Gates: they open where the squadron entered, and again where it leaves.
        float gatePhase=age<life*0.6 ? inS : outP;
        vec2 gateOrigin=(age<life*0.5 ? entryP : exitP)*size.y;
        vec2 gd=fragCoord-floor(gateOrigin);
        float gspan=70.0*px;
        if(abs(gd.x)<gspan && abs(gd.y)<gspan) {
            vec2 gp=floor(gd/px)+0.5;
            vec2 gq=vec2(dot(gp,forward),dot(gp,sidev));
            color=alienGate(gq,gatePhase,0.9,color);
        }
        vec2 p2=floor((fragCoord-floor(center))/px)+0.5;
        vec2 q2=vec2(dot(p2,forward),dot(p2,sidev));
        float lenS=mix(0.10,1.0,inS)*(1.0+outP*3.0);
        float widS=mix(0.16,1.0,inS)*max(0.04,1.0-outP);
        vec2 s2=q2/(vec2(lenS,widS)*0.9);
        float kind=mod(floor(hash21(vec2(seed*7.0,id+31.0))*5.0),5.0);
        if(abs(s2.x)<30.0 && abs(s2.y)<24.0)
            color=alienHull(s2,kind,age+id,0.9,color);
        // Raider shields fail shortly before the hull is lost.
        float rfail=age-(raiderDownTime(id,seed)-0.9);
        if(rfail>0.0 && rfail<0.30 && hexEdge(pixel-center,2.4+rfail*7.0)<1.0)
            color=mix(color,vec3(214,150,186)/255.0,(1.0-rfail/0.30)*0.6);
        // Gunfire and impacts, on a fixed cadence per ship so the volley reads as a rhythm.
        if(attack>0.5) {
            // Where a bolt stops is what the shield is *for*: while it holds, the shots end at the
            // bubble and the glints land on it instead of on the city. Half the squadron trades fire
            // with the defending ships rather than the planet.
            float stopR = shieldStr>0.02 ? 1.06 : 1.0;
            vec2 aimPx=tgtPx;
            float aimRadius=targetR*size.y*stopR;
            bool duelling = defended && dCount>0 && mod(id,2.0)>0.5;
            bool railHit = mod(id,4.0)>2.5;
            if(duelling) {
                float k=mod(id,float(dCount));
                aimPx=snapPixel(defenderPos(dFormation,dForward,dSide,k,seed,size));
                aimRadius=0.0;
            } else if(railHit) {
                // Some of the squadron goes after the orbital ring instead, which has its own shield.
                float a=hash21(vec2(seed,173.0+id))*6.2831853;
                vec2 er=vec2(1.52*cos(a),0.42*sin(a));
                aimPx=snapPixel(tgtPx+vec2(er.x-0.30*er.y,er.y+0.30*er.x)*1.09*targetR*size.y);
                aimRadius=0.0;
            }
            vec2 toward=normalize(aimPx-center);
        // Fire: three thin bolts per ship. The bombardment has to read as heavy, but each trace stays
        // narrow - a planet is a hundred times a hull's width, so a fat beam would look like a beam of
        // paint. Volume comes from the number of shots, not their size.
        for(int b=0;b<3;b++) {
            float bAge=mod(age-id*0.19-float(b)*0.38,1.15);
            if(bAge>0.70) continue;
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
            vec2 firingPos=snapPixel(raiderPos(mix(entryP,exitP,tLaunch)*size.y,forward,sidev,id,seed,size));
            vec2 dirB=normalize(hitPt-firingPos);
            if(bAge<0.42) {
                vec2 ppos=mix(firingPos,hitPt,bAge/0.42);
                vec2 rel=pixel-ppos;
                float along=dot(rel,dirB);
                if(abs(along)<11.0 && length(rel-dirB*along)<0.5)
                    color=max(color,vec3(242,160,160)/255.0);
            } else {
                float fade=(bAge-0.42)/0.28;
                vec2 rel=pixel-hitPt;
                if(((railHit ? railShieldStr : shieldStr)>0.02) && !duelling) {
                    // Small and semi-transparent, and only at the point of contact.
                    float hr=1.9-1.3*fade;
                    float edge=hexEdge(rel,hr);
                    if(hr>0.5) {
                        if(edge<0.9) color=mix(color,vec3(168,224,190)/255.0,0.50*(1.0-fade*0.6));
                        else if(edge<1.9 && fade<0.45)
                            color=mix(color,vec3(70,132,110)/255.0,0.24*(1.0-fade));
                    }
                } else if(duelling) {
                    // A hit on a hull meets that ship's own shield first: a small hexagon in the side's
                    // colour, semi-transparent, gone in a quarter second. Same restrained size as the
                    // planet's glint, scaled down because a hull is a fraction of a world.
                    float hr=3.0-2.0*fade;
                    float edge=hexEdge(rel,hr);
                    if(hr>0.5) {
                        if(edge<0.9) color=mix(color,vec3(150,220,240)/255.0,0.55*(1.0-fade*0.5));
                        else if(edge<2.2 && fade<0.5) color=mix(color,vec3(70,120,140)/255.0,0.24);
                    }
                } else {
                    // The smallest impact that still reads: a pixel and a half, plus a hairline ring.
                    float w=1.2-fade*1.4;
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
        for(int m=0;m<3;m++) {
            if(m>=count) continue;
            vec2 e=stationPoint(0.65+float(m)*TAU/3.0);
            vec2 stLocal=vec2(e.x-0.30*e.y,e.y+0.30*e.x)*1.09;
            vec2 stPx=target*size.y+stLocal*targetR*size.y;
            for(int q2=0;q2<2;q2++) {
                float phase=mod(age-float(m)*0.31-float(q2)*0.62,1.25);
                if(phase>0.55) continue;
                int tgt=int(mod(float(m)+float(q2)*2.0,float(count)));
                vec2 shipPx=snapFine(raiderPos(formation,forward,sidev,float(tgt),seed,size));
                vec2 toward=normalize(shipPx-stPx);
                vec2 rel=pixel-mix(stPx,shipPx,phase/0.55);
                float along=dot(rel,toward);
                if(abs(along)<9.0 && length(rel-toward*along)<0.7)
                    color=max(color,vec3(186,244,252)/255.0);
                // Muzzle flash: a small glare at the battery as the bolt leaves.
                if(phase<0.12 && abs(pixel.x-stPx.x)<2.5 && abs(pixel.y-stPx.y)<2.5)
                    color=max(color,vec3(214,248,252)/255.0);
            }
            // And the raider comes apart where it is hit. The burst holds for six tenths of a second
            // and shrinks slowly enough to be seen: a flash that lasts two frames is not an explosion.
            vec2 shipPx=snapFine(raiderPos(formation,forward,sidev,float(m),seed,size));
            float eAge=age-raiderDownTime(float(m),seed);
            if(eAge>0.0 && eAge<0.60) {
                vec2 rel=pixel-shipPx;
                float fade=eAge/0.60;
                float w=2.8-fade*3.2;
                if(w>0.3 && abs(rel.x)<=w && abs(rel.y)<=w)
                    color=max(color,vec3(250,222,186)/255.0*(1.0-fade*0.5));
                float ring=w+1.0;
                if(abs(max(abs(rel.x),abs(rel.y))-ring)<1.3 && fade<0.6)
                    color=max(color,vec3(246,152,96)/255.0);
            }
        }
    }
    // The defending squadron: friendly hulls, their own gates, return fire at the raiders and their own
    // losses. Both sides shoot, so the engagement can go either way.
    if(defended && dCount>0) {
        float dIn=clamp((age-2.6)/1.2,0.0,1.0);
        float dOut=clamp((age-(life-2.4))/2.4,0.0,1.0);
        for(int k=0;k<5;k++) {
            if(k>=dCount) continue;
            float id=float(k);
            float down=defenderDownTime(id,seed);
            vec2 dcenter=snapFine(defenderPos(dFormation,dForward,dSide,id,seed,size));
            // Gate where this ship arrived, and where it leaves.
            vec2 gOrigin=(age<life*0.5 ? dEntry : dExit)*size.y;
            vec2 gd=fragCoord-floor(gOrigin);
            float gspan=70.0*px;
            if(abs(gd.x)<gspan && abs(gd.y)<gspan) {
                vec2 gp=floor(gd/px)+0.5;
                vec2 gq=vec2(dot(gp,dForward),dot(gp,dSide));
                color=warpGate(gq, age<life*0.5 ? dIn : dOut, 0.9, color);
            }
            if(age<down) {
                vec2 p3=floor((fragCoord-floor(dcenter))/px)+0.5;
                vec2 q3=vec2(dot(p3,dForward),dot(p3,dSide));
                float lenS=mix(0.12,1.0,dIn)*(1.0+dOut*2.0);
                float widS=mix(0.16,1.0,dIn)*max(0.06,1.0-dOut);
                vec2 s3=q3/(vec2(lenS,widS)*0.9);
                float kind=mod(floor(hash21(vec2(seed*5.0,id+13.0))*3.0),3.0);
                if(abs(s3.x)<42.0 && abs(s3.y)<24.0)
                    color=fleetHull(s3,kind,age+id,0.92,color);
                // Return fire at a raider.
                float fAge=mod(age-id*0.23,1.05);
                if(fAge<0.45 && count>0) {
                    int tgt=int(floor(hash21(vec2(seed,149.0+id))*float(count)));
                    vec2 tp=snapFine(raiderPos(formation,forward,sidev,float(tgt),seed,size));
                    vec2 tw=normalize(tp-dcenter);
                    vec2 rel2=pixel-mix(dcenter,tp,fAge/0.45);
                    float a2=dot(rel2,tw);
                    if(abs(a2)<8.0 && length(rel2-tw*a2)<0.5)
                        color=max(color,vec3(176,240,250)/255.0);
                }
                // The bolt's arrival: the raider's shield answers while it still holds, and once it has
                // failed the shot lands on the hull.
                float hitAge=fAge-0.45;
                if(hitAge>0.0 && hitAge<0.25 && count>0) {
                    int tgt=int(floor(hash21(vec2(seed,149.0+id))*float(count)));
                    vec2 tp=snapFine(raiderPos(formation,forward,sidev,float(tgt),seed,size));
                    vec2 rel3=pixel-tp;
                    float fd=hitAge/0.25;
                    if(age<raiderDownTime(float(tgt),seed)-0.9) {
                        float hr=2.8-1.8*fd;
                        float edge=hexEdge(rel3,hr);
                        if(hr>0.5) {
                            if(edge<0.9) color=mix(color,vec3(206,116,152)/255.0,0.55*(1.0-fd*0.5));
                            else if(edge<2.0 && fd<0.5) color=mix(color,vec3(96,60,86)/255.0,0.24);
                        }
                    } else {
                        float w=1.2-fd*1.3;
                        if(w>0.3 && abs(rel3.x)<=w && abs(rel3.y)<=w)
                            color=max(color,vec3(250,220,190)/255.0);
                    }
                }
                // Defence shields fail shortly before the ship is lost: a brief hexagon, then nothing.
                float dfail=age-(down-0.9);
                if(dfail>0.0 && dfail<0.30 && hexEdge(pixel-dcenter,2.4+dfail*7.0)<1.0)
                    color=mix(color,vec3(190,232,246)/255.0,(1.0-dfail/0.30)*0.6);
            } else {
                // A defender lost: its own burst, in the friendly palette.
                float d2=age-down;
                if(d2<0.6) {
                    vec2 rel3=pixel-dcenter;
                    float fade2=d2/0.6;
                    float w2=2.8-fade2*3.2;
                    if(w2>0.3 && abs(rel3.x)<=w2 && abs(rel3.y)<=w2)
                        color=max(color,vec3(226,244,250)/255.0*(1.0-fade2*0.5));
                    float ring2=w2+1.0;
                    if(abs(max(abs(rel3.x),abs(rel3.y))-ring2)<1.3 && fade2<0.6)
                        color=max(color,vec3(126,206,226)/255.0);
                }
            }
        }
    }
    return color;
}
// Stateless seeded event schedule: stable throughout an event, no per-frame lottery.
// Fixed 180s slots with randomized delays and skipped slots produce quiet intervals.
vec2 shipSchedule(float time) {
    if(iWarpRate<=0.0) return vec2(-100.0,0.0);
    float clock=time*iWarpRate;
    float slot=floor(clock/180.0);
    float seed=hash21(vec2(slot,81.0));
    if(seed<0.22) return vec2(-100.0,seed);
    float delay=18.0+70.0*hash21(vec2(slot,19.0));
    // Frequency changes spacing only; every flyby still lasts 16 real seconds.
    return vec2((mod(clock,180.0)-delay)/iWarpRate,seed);
}
vec3 warpGate(vec2 q, float phase, float depth, vec3 bg) {
    if(phase<=0.0 || phase>=1.0) return bg;
    float opening=sin(phase*3.14159265);
    vec2 radius=vec2(2.0+11.0*opening,4.0+23.0*opening)*depth;
    float r=length(q/radius);
    vec3 c=bg;
    // Hard-edged contracting/expanding contours suggest local space deformation.
    if(r<0.82) c*=0.40;
    if(abs(r-1.0)<0.07 || abs(r-1.24)<0.035)
        c=max(c,vec3(78,143,161)/255.0*iShipGain*opening);
    if(abs(r-0.86)<0.045)
        c=max(c,vec3(139,117,167)/255.0*iShipGain*opening);
    if(abs(q.y)<1.0 && abs(q.x)<(10.0+35.0*opening)*depth)
        c=max(c,vec3(114,166,175)/255.0*iShipGain*opening);
    return c;
}
vec3 fleetHull(vec2 s, float kind, float age, float depth, vec3 bg) {
    float sy=abs(s.y);
    bool hull=false;
    if(kind<0.5) {
        // Needle frigate, separated rear nacelles.
        hull=(s.x>=-25.0 && s.x<=32.0 && sy<=max(1.0,5.0-max(s.x-13.0,0.0)*0.19))
            || (s.x>=-23.0 && s.x<=-3.0 && sy>=9.0 && sy<=12.0)
            || (s.x>=-18.0 && s.x<=-12.0 && sy<=11.0);
    } else if(kind<1.5) {
        // Broad cruiser with twin forward prongs and an inset bridge.
        hull=(s.x>=-25.0 && s.x<=18.0 && sy<10.0)
            || (s.x>8.0 && s.x<31.0 && sy>4.0 && sy<8.0)
            || (s.x>-20.0 && s.x<0.0 && sy<15.0);
    } else if(kind<2.5) {
        // Long carrier spine, armored hangar banks and projecting flight deck.
        hull=(s.x>-34.0 && s.x<35.0 && sy<4.0)
            || (s.x>-25.0 && s.x<20.0 && sy>6.0 && sy<13.0)
            || (s.x>-20.0 && s.x<-12.0 && sy<13.0);
    } else if(kind<3.5) {
        // Dreadnought: one long armoured slab, a stepped bow, outrigger pods and a bridge tower.
        // The biggest hull in the fleet and the brightest, so it is what the eye lands on.
        hull=(s.x>-44.0 && s.x<46.0 && sy<12.0)
            || (s.x>20.0 && s.x<46.0 && sy<7.0-(s.x-20.0)*0.16)
            || (s.x>-30.0 && s.x<10.0 && sy>13.0 && sy<18.0)
            || (s.x>-16.0 && s.x<16.0 && sy<20.0);
    } else if(kind<4.5) {
        // Corvette: a short dart, flown in numbers by the grand fleets.
        hull=(s.x>=-12.0 && s.x<=13.0 && sy<=max(1.0,4.0-max(s.x-4.0,0.0)*0.22))
            || (s.x>=-11.0 && s.x<=0.0 && sy>=5.0 && sy<=7.0);
    } else {
        // Transport: a fat stepped hull with container bays along the spine.
        hull=(s.x>-22.0 && s.x<22.0 && sy<11.0)
            || (s.x>-26.0 && s.x<-22.0 && sy<4.0)
            || (s.x>22.0 && s.x<27.0 && sy<4.0);
    }
    vec3 c=bg;
    if(hull) {
        vec3 metal=vec3(44,55,68)/255.0;
        if(s.y<0.0) metal=vec3(73,83,91)/255.0;
        if(sy<2.0) metal=vec3(91,95,94)/255.0;
        if(mod(floor(s.x)+40.0,9.0)<1.0 && sy>2.0) metal=vec3(30,40,52)/255.0;
        if(s.x>-14.0 && s.x<-5.0 && sy<3.0) metal=vec3(94,101,103)/255.0;
        if(s.x>-5.0 && s.x<18.0 && sy>3.0 && sy<5.0 && mod(floor(s.x),4.0)<1.0)
            metal=vec3(157,133,91)/255.0;
        if(kind>1.5 && kind<2.5 && sy>7.0 && sy<11.0 && mod(floor(s.x)+30.0,8.0)<3.0)
            metal=vec3(24,36,48)/255.0;
        if(kind>2.5 && kind<3.5) {
            // Dreadnought: gold-lit spine over a dark armoured belt.
            if(sy<3.0) metal=vec3(104,108,106)/255.0;
            if(mod(floor(s.x)+46.0,7.0)<1.0 && sy>3.0) metal=vec3(22,32,44)/255.0;
            if(s.x>-16.0 && s.x<10.0 && sy>13.0 && sy<18.0) metal=vec3(52,66,84)/255.0;
            if(abs(sy-12.5)<1.0) metal=vec3(157,133,91)/255.0;
        }
        if(kind>4.5) {
            // Transport: the cargo bays read as a lattice of lighter blocks.
            if(mod(floor(s.x)+22.0,6.0)<3.0 && mod(floor(s.y)+11.0,6.0)<3.0)
                metal=vec3(78,88,96)/255.0;
        }
        c=metal*iShipGain*(0.62+0.38*depth);
    }
    float engineX=-25.0;
    if(kind>1.5 && kind<2.5) engineX=-34.0;
    else if(kind>2.5 && kind<3.5) engineX=-44.0;
    else if(kind>3.5 && kind<4.5) engineX=-12.0;
    else if(kind>4.5) engineX=-26.0;
    float flame=3.0+2.0*sin(age*2.1);
    if(s.x<engineX && s.x>engineX-flame && (abs(sy-2.0)<1.0 || abs(sy-7.0)<1.0))
        c=max(c,vec3(78,137,153)/255.0*iShipGain*depth);
    return c;
}
vec3 shipEvent(vec2 fragCoord, vec3 bg) {
    vec2 event=shipSchedule(iTime);
    float age=event.x, seed=event.y;
    if(age<0.0 || iShipGain<=0.0) return bg;
    // The class decides the shape of the event: how many hulls, how far away they fly and how long
    // the flyby lasts. Grand fleets take longer because a big formation needs the time to cross.
    float cls=fleetClass(seed);
    float life = cls>1.5 ? 22.0 : 16.0;
    float cruiseEnd = life-4.0;
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
    for(int j=0;j<18;j++) {
        if(j>=count) continue;
        float id=float(j);
        // Grand fleets stagger a little wider, so the formation unfolds instead of popping at once.
        float t=age-id*(cls>1.5 ? 0.30 : 0.25);
        if(t<=0.0 || t>=cruiseEnd+2.6) continue;
        float rnd=hash21(vec2(seed*17.0,id+4.0));
        // Grand fleets are all far away: the depth band is narrow and low, so every hull stays
        // small and dim and the formation reads as one distant swarm rather than a line of large
        // near ships. The floor keeps them above the size where a hull would dissolve into stars.
        float depth = cls>1.5 ? 0.18+id*0.012 : 0.48+id*0.15;
        float kind;
        if(cls>1.5) {
            // A dreadnought leads, then a mix of cruisers, frigates and corvette escorts.
            kind = id<1.0 ? 3.0 : (rnd>0.62 ? 1.0 : (rnd>0.34 ? 0.0 : 4.0));
        } else {
            kind = mod(floor(hash21(vec2(seed*13.0,id+31.0))*6.0),6.0);
        }
        float spread=(mod(id,2.0)*2.0-1.0)*(cls>1.5 ? 0.014+0.007*id : 0.04+0.025*id);
        vec2 entry=origin+iResolution.y*(side*spread-forward*id*(cls>1.5 ? 0.014 : 0.037));
        float speed=iResolution.y*(0.008+0.005*depth);
        vec2 exitPoint=entry+forward*speed*cruiseEnd;
        vec2 center=snapFine(entry+forward*speed*min(t,cruiseEnd)
            +side*sin(t*0.32+id)*iResolution.y*0.003);
        float arrive=clamp(t/1.8,0.0,1.0);
        float depart=clamp((t-cruiseEnd)/2.8,0.0,1.0);
        center=mix(center,exitPoint,depart);
        vec2 gateOrigin=t<6.0 ? entry : exitPoint;
        // Gate work only inside its own box: with 14 craft per event this is what keeps the frame
        // cost flat, since most pixels are nowhere near any gate or hull.
        vec2 gateDelta=fragCoord-floor(gateOrigin);
        float gateSpan=60.0*px*(0.5+depth);
        if(abs(gateDelta.x)<gateSpan && abs(gateDelta.y)<gateSpan) {
            vec2 gatePixel=floor(gateDelta/px)+0.5;
            vec2 gateQ=vec2(dot(gatePixel,forward),dot(gatePixel,side));
            float gatePhase=t<1.8 ? arrive : depart;
            color=warpGate(gateQ,gatePhase,depth,color);
        }
        vec2 pixel=floor((fragCoord-floor(center))/px)+0.5;
        vec2 q=vec2(dot(pixel,forward),dot(pixel,side));
        float lengthScale=mix(0.08,1.0,arrive)*(1.0+depart*2.3);
        float widthScale=mix(0.12,1.0,arrive)*max(0.035,1.0-depart);
        // Portal clipping pulls the hull into the exit rather than deleting it whole.
        if(depart>0.0 && abs(q.x)>max(0.0,(1.0-depart)*48.0*depth)) continue;
        vec2 s=q/(vec2(lengthScale,widthScale)*depth);
        if(abs(s.x)<48.0 && abs(s.y)<22.0)
            color=fleetHull(s,kind,t+rnd,depth,color);
    }
    return color;
}
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
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
    if(gq.y<0.27*gq.x) color=ring(gq,color,gasLight);
    color=planet(screen,gas,0.15,0.0,color,pixel);
    // Ring shadow across the disk: the ring's plane crosses it along this band, displaced away
    // from the lamp, and only where the surface is lit enough to show it.
    if(dot(gq,gq)<=1.0 && illumination(gq,gas)>-0.05) {
        float shadowBand=abs(gq.y-0.27*gq.x-0.12*dot(gasLight,normalize(vec2(-0.27,1.0))));
        if(shadowBand<0.085) color*=0.62;
    }
    if(gq.y>=0.27*gq.x) color=ring(gq,color,gasLight);
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
    float incLife=13.0+4.0*hash21(vec2(incClock.y,61.0));
    float incAttack=(incClock.x>2.0 && incClock.x<incLife-2.4) ? incClock.x-2.0 : -1.0;
    vec2 shield=shieldState(incAttack,incClock.y);
    // The orbital ring carries a shield of its own, on its own cycle, so the two never fail together.
    vec2 shieldRail=shieldState(incAttack*0.93+1.7,incClock.y+7.0);
    if(abs(q.x)<1.8 && abs(q.y)<1.5) {
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
        color=infrastructure(q,color,0.0,pixelWidth);
        if(qlen2<=1.0) {
            color=cityPlanet(q,center,pixel);
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
        color=infrastructure(q,color,1.0,pixelWidth);
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
    color=asteroidGroup(pixel,size,color);
    color=patrolPass(pixel,size,color);
    color=structurePass(pixel,size,color);
    color=incursionEvent(fragCoord,pixel,size,center,CITY_R,shield.x,shieldRail.x,color);
    color=cometPixel(pixel,size,color);
    color=meteorPixel(pixel,size,color);
    fragColor=vec4(color*max(iBrightness,0.0),1.0);
}
