/*! par-term shader metadata
name: Kanagawa - Starbound
author: Codex
description: Flat retro space mural, ink-blue nebula banks, cut-paper planets and quiet pixel stars. Texture-free; lit-limb atmospheres, ring shadows, coast-hugging city lights and layered star drifts.
version: 1.6.0
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

const float TAU = 6.28318530718;
// Closed scenic orbits extend beyond the viewport; no on-screen teleport/reset.
vec2 orbit(float aspect, float phase, float rate, float height) {
    float a=phase+iTime*iOrbitSpeed*TAU/1080.0*rate;
    return vec2(aspect*(0.5+0.86*cos(a)),0.5+height*sin(a));
}
float illumination(vec2 q, vec2 center) {
    vec2 lamp=vec2(iResolution.x/iResolution.y*0.32,-0.35);
    vec3 light=normalize(vec3(lamp-center,0.42));
    vec3 normal=vec3(q,sqrt(max(0.0,1.0-dot(q,q))));
    return dot(normal,light);
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
    vec2 q = bodyLocal(p,center,radius);
    float r2 = dot(q,q);
    // Atmosphere: a hard two-step ring hugging the lit limb. `bodyLocal` normalises by the radius,
    // so one physical pixel is this much of `q`; the halo is a couple of pixels wide and stays a
    // drawn edge, never a bloom (no gradients and no AA anywhere in this mural).
    float limb = 2.0/(iResolution.y*max(radius,1e-4));
    if (r2 > 1.0 + 3.0*limb) return bg;
    float lightSide = illumination(q,center);
    if (r2 > 1.0 && lightSide > 0.10)
        return max(bg, vec3(58,96,112)/255.0*(lightSide > 0.45 ? 1.0 : 0.55));
    float angle=iTime*iSurfaceSpeed*0.018;
    vec2 surface=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*q;
    float ribbons = surface.y + 0.18*surface.x + 0.07*sin(surface.x*5.0)
        + 0.025*sin(surface.x*15.0+surface.y*6.0);
    float stripe = floor(ribbons * 18.0);
    float detail = noise2(surface*5.0 + kind*13.0);
    // A drawn crescent boundary with three flat shades, not a lit 3-D sphere.
    vec3 c = vec3(17,21,31)/255.0;
    if (lightSide > -0.10) c = vec3(34,44,60)/255.0;
    if (lightSide > 0.26) c = vec3(54,72,87)/255.0;
    if (lightSide > 0.26 && mod(stripe,4.0)<1.0) c = vec3(74,91,104)/255.0;
    if (lightSide > 0.26 && detail>0.67) c = vec3(62,81,91)/255.0;
    // Long cloud ribbons with discrete breaks and a small oval storm.
    if (lightSide > 0.26 && mod(stripe,7.0)==2.0 && detail>0.35)
        c=vec3(83,101,111)/255.0;
    if (lightSide > 0.26 && mod(stripe,9.0)==5.0)
        c=vec3(42,58,74)/255.0;
    vec2 storm=(surface-vec2(0.43,0.17))/vec2(0.25,0.085);
    float swirl=dot(storm,storm);
    if(lightSide>0.26 && swirl<1.0) c=vec3(91,96,92)/255.0;
    if(lightSide>0.26 && swirl<0.40) c=vec3(47,63,75)/255.0;
    if(r2>0.94 && lightSide>0.50) c=vec3(89,109,117)/255.0;
    if (kind > 0.5) {
        c = vec3(26,22,31)/255.0;
        if (lightSide > 0.0) c = vec3(66,45,49)/255.0;
        if (lightSide > 0.35) c = vec3(98,69,62)/255.0;
        if (lightSide > 0.35 && detail>0.62) c = vec3(121,88,70)/255.0;
        float land=noise2(surface*12.0+17.0);
        if(lightSide>0.35 && land>0.65) c=vec3(79,53,49)/255.0;
        vec2 crater=surface-vec2(0.40,-0.24);
        float cr=length(crater/vec2(0.23,0.19));
        if(lightSide>0.35 && cr<1.0) c=vec3(135,98,76)/255.0;
        if(lightSide>0.35 && cr<0.70) c=vec3(72,48,46)/255.0;
    }
    // One brighter step on the inner limb: the atmosphere again, this time the part seen against
    // the planet itself rather than against space.
    if (r2 > 1.0 - 3.0*limb && lightSide > 0.30) c = max(c, vec3(83,120,133)/255.0*0.85);
    return c;
}
vec3 cityPlanet(vec2 q, vec2 center) {
    float light=illumination(q,center);
    float angle=iTime*iSurfaceSpeed*0.009;
    vec2 s=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*q;
    vec3 c=vec3(13,19,29)/255.0;
    if(light>0.0) c=vec3(28,39,53)/255.0;
    if(light>0.38) c=vec3(44,57,70)/255.0;
    float land=noise2(s*4.0+9.0);
    if(land>0.60) c+=vec3(5,6,6)/255.0;
    // Settlements hug the coast. The land mask's edge is where a night map of Earth lights up and
    // the interior stays dark, so the lights read as a map instead of an even sprinkle.
    bool nearCoast=abs(land-0.60)<0.06;
    // Three readable megacities: concentric districts, radial avenues, long links.
    float metropolis=0.0;
    float traffic=0.0;
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
            float pulse=0.5+0.5*sin(r*24.0-iTime*iCityFlow*0.65+float(j)*2.0);
            traffic=max(traffic,pulse);
        }
    }
    // Links use Cartesian distance; no angular seam can cut across the planet.
    vec2 roadA=vec2(-0.38,0.20), roadB=vec2(0.40,0.40), roadC=vec2(0.18,-0.53);
    vec2 ab=roadB-roadA, bc=roadC-roadB;
    float dAB=length(s-roadA-ab*clamp(dot(s-roadA,ab)/dot(ab,ab),0.0,1.0));
    float dBC=length(s-roadB-bc*clamp(dot(s-roadB,bc)/dot(bc,bc),0.0,1.0));
    if(min(dAB,dBC)<0.013) {metropolis=1.0; traffic=0.5+0.5*sin(dot(s,vec2(29,17))-iTime*iCityFlow);}
    // Smaller settlements support the major silhouettes without filling the disk.
    vec2 lots=floor(s*65.0);
    float seed=hash21(lots+18.0);
    float belt=abs(fract((s.y+0.12*sin(s.x*6.0))*8.0)-0.5);
    float district=noise2(s*11.0+6.0);
    bool road=belt<0.09 && district>(nearCoast ? 0.20 : 0.42);
    bool tower=seed>(nearCoast ? 0.70 : 0.84) && district>0.50;
    if(road || tower || metropolis>0.0) {
        float route=floor(s.y*8.0);
        float signal=0.5+0.5*sin(s.x*26.0-iTime*iCityFlow*0.65+route*2.7);
        if(metropolis>0.0) signal=traffic;
        float level=signal>0.85 ? 1.0 : (signal>0.48 ? 0.72 : 0.48);
        vec3 neon=vec3(85,151,145)/255.0;
        if(seed>0.72) neon=vec3(158,115,161)/255.0;
        if(seed>0.92) neon=vec3(187,157,102)/255.0;
        if(metropolis>0.0) neon=vec3(194,167,112)/255.0;
        float night=light<0.0 ? 1.65 : (light<0.38 ? 0.65 : 0.20);
        c=max(c,neon*level*night*iCityGain);
    }
    if(dot(q,q)>0.965 && light>0.05) c=vec3(55,80,93)/255.0;
    if(dot(q,q)>0.988 && light>0.30) c=vec3(86,124,138)/255.0;
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
vec3 stars(vec2 pixel, float cellSize, float moving, float boost) {
    vec2 pos = pixel + vec2(floor(iTime*iDrift*0.30)*moving, 0.0);
    vec2 id = floor(pos/cellSize);
    float seed = hash21(id + 93.1 + moving*51.0);
    vec2 origin = floor(vec2(hash21(id+2.3),hash21(id+7.1))*(cellSize-7.0))+3.0;
    vec2 d = mod(pos,cellSize)-origin;
    float radius = seed>0.985 ? 2.0*boost : 0.0;
    bool hit = abs(d.x)<0.5 && abs(d.y)<0.5;
    if (radius>0.0) hit = (abs(d.x)<0.5 && abs(d.y)<=radius) || (abs(d.y)<0.5 && abs(d.x)<=radius);
    // Density drifts in slow clouds, so the field keeps quiet voids and crowded drifts instead of
    // an even sprinkle. It is read from `pixel`, not from the drifted position, so it is stable
    // in time while the stars themselves still step across it.
    float cloud = noise2(pixel*0.0031 + 4.7);
    if (!hit || seed < 0.30 || seed > 0.30 + 0.95*cloud) return vec3(0);
    float phase = iTime*(0.28+hash21(id+21.0)*0.55)+seed*63.0;
    float pulse = pow(0.5+0.5*sin(phase),3.0);
    float level = floor((0.60+iTwinkle*(pulse-0.35))*5.0)/5.0;
    vec3 color = vec3(163,177,190)/255.0;
    if(seed>0.70) color=vec3(192,166,119)/255.0;
    if(seed>0.86) color=vec3(149,127,166)/255.0;
    return color*max(level,0.12)*iStarGain;
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
    } else {
        // Long carrier spine, armored hangar banks and projecting flight deck.
        hull=(s.x>-34.0 && s.x<35.0 && sy<4.0)
            || (s.x>-25.0 && s.x<20.0 && sy>6.0 && sy<13.0)
            || (s.x>-20.0 && s.x<-12.0 && sy<13.0);
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
        if(kind>1.5 && sy>7.0 && sy<11.0 && mod(floor(s.x)+30.0,8.0)<3.0)
            metal=vec3(24,36,48)/255.0;
        c=metal*iShipGain*(0.62+0.38*depth);
    }
    float engineX=kind>1.5 ? -34.0 : -25.0;
    float flame=3.0+2.0*sin(age*2.1);
    if(s.x<engineX && s.x>engineX-flame && (abs(sy-2.0)<1.0 || abs(sy-7.0)<1.0))
        c=max(c,vec3(78,137,153)/255.0*iShipGain*depth);
    return c;
}
vec3 shipEvent(vec2 fragCoord, vec3 bg) {
    vec2 event=shipSchedule(iTime);
    float age=event.x, seed=event.y;
    if(age<0.0 || age>=16.0 || iShipGain<=0.0) return bg;
    float px=max(floor(iPixelSize),1.0);
    vec3 color=bg;
    float heading=(hash21(vec2(seed,3.0))-0.5)*0.8+(seed>0.60 ? 3.14159265 : 0.0);
    vec2 forward=vec2(cos(heading),sin(heading));
    vec2 side=vec2(-forward.y,forward.x);
    vec2 origin=iResolution*vec2(0.30+0.40*hash21(vec2(seed,9.0)),
        0.28+0.35*hash21(vec2(seed,42.0)));
    int count=3+int(floor(seed*2.99));
    // Far-to-near order is stable. Each craft has its own pose and entry/exit point.
    for(int j=0;j<5;j++) {
        if(j>=count) continue;
        float id=float(j);
        float t=age-id*0.25;
        if(t<=0.0 || t>=14.8) continue;
        float rnd=hash21(vec2(seed*17.0,id+4.0));
        float depth=0.48+id*0.15;
        float kind=mod(floor(seed*11.0)+id,3.0);
        float spread=(mod(id,2.0)*2.0-1.0)*(0.04+0.025*id);
        vec2 entry=origin+iResolution.y*(side*spread-forward*id*0.037);
        float speed=iResolution.y*(0.008+0.005*depth);
        vec2 exitPoint=entry+forward*speed*12.0;
        vec2 center=entry+forward*speed*min(t,12.0)
            +side*sin(t*0.32+id)*iResolution.y*0.003;
        float arrive=clamp(t/1.8,0.0,1.0);
        float depart=clamp((t-12.0)/2.8,0.0,1.0);
        center=mix(center,exitPoint,depart);
        vec2 gateOrigin=t<6.0 ? entry : exitPoint;
        vec2 gatePixel=floor((fragCoord-floor(gateOrigin))/px)+0.5;
        vec2 gateQ=vec2(dot(gatePixel,forward),dot(gatePixel,side));
        float gatePhase=t<1.8 ? arrive : depart;
        color=warpGate(gateQ,gatePhase,depth,color);
        vec2 pixel=floor((fragCoord-floor(center))/px)+0.5;
        vec2 q=vec2(dot(pixel,forward),dot(pixel,side));
        float lengthScale=mix(0.08,1.0,arrive)*(1.0+depart*2.3);
        float widthScale=mix(0.12,1.0,arrive)*max(0.035,1.0-depart);
        vec2 s=q/(vec2(lengthScale,widthScale)*depth);
        // Portal clipping pulls the hull into the exit rather than deleting it whole.
        if(depart>0.0 && abs(q.x)>max(0.0,(1.0-depart)*48.0*depth)) continue;
        if(abs(s.x)<42.0 && abs(s.y)<18.0)
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
    // Large static ink banks cross the complete canvas, leaving a quiet middle.
    float n = noise2(p*3.0)*0.7 + noise2(p*7.0+11.0)*0.3;
    float wave = 0.72 + 0.13*sin(p.x*3.7) + (n-0.5)*0.23;
    float lower = (uv.y-wave)*8.0;
    float upper = (0.12+0.10*sin(p.x*3.1+1.5)+(n-0.5)*0.22-uv.y)*8.0;
    float detailN=noise2(p*19.0+31.0);
    float bank = max(lower,upper) + (detailN-0.5)*0.18;
    float k = floor(clamp((bank+0.45)*2.3*iNebula,0.0,5.0));
    vec3 color = ink(k);
    // Sparse broken ridges, kept to the outer banks.
    if (k>=2.0 && n>0.59 && mod(floor(bank*8.0),5.0)==0.0) color = ink(k+1.0);
    // Interrupted contour ribbons hug the banks; the quiet middle stays empty.
    float contour=fract(bank*3.0+0.22*noise2(p*11.0));
    if(k>=2.0 && contour<0.12 && detailN>0.42) color=ink(min(k+1.0,5.0));
    if(k>=2.0 && contour>0.85 && n<0.48) color=ink(k-1.0);
    if(k>=2.0 && n>0.57 && detailN>0.54)
        color=mix(color,vec3(48,37,57)/255.0,0.35);
    vec2 center = orbit(aspect,1.2,1.0,0.29);
    vec2 ochre = orbit(aspect,1.95,0.73,-0.33);
    vec2 gas = orbit(aspect,-0.24,0.87,0.36);
    vec2 moon = center+vec2(0.27*cos(iTime*iOrbitSpeed*0.009+3.3),
        0.24*sin(iTime*iOrbitSpeed*0.009+3.3));
    vec2 q = bodyLocal(screen,center,0.205);
    vec2 gq=bodyLocal(screen,gas,0.15);
    // Direction from the ringed planet to the scene's fixed lamp, in the planet's own frame: the
    // ring's shaded far side and the ring's shadow across the disk both come from it. The length is
    // checked because normalise() at exactly zero would hand NaN to everything downstream.
    vec2 toLamp=vec2(aspect*0.32,-0.35)-gas;
    float toLampLen=length(toLamp);
    vec2 gasLight=toLampLen>1e-4 ? toLamp/toLampLen : vec2(0.0,1.0);
    if(gq.y<0.27*gq.x) color=ring(gq,color,gasLight);
    color=planet(screen,gas,0.15,0.0,color);
    // Ring shadow across the disk: the ring's plane crosses it along this band, displaced away
    // from the lamp, and only where the surface is lit enough to show it.
    if(dot(gq,gq)<=1.0 && illumination(gq,gas)>-0.05) {
        float shadowBand=abs(gq.y-0.27*gq.x-0.12*dot(gasLight,normalize(vec2(-0.27,1.0))));
        if(shadowBand<0.085) color*=0.62;
    }
    if(gq.y>=0.27*gq.x) color=ring(gq,color,gasLight);
    color=planet(screen,ochre,0.074,1.0,color);
    color=planet(screen,moon,0.025,0.0,color);
    if(abs(q.x)<1.8 && abs(q.y)<1.5) {
        float pixelWidth=1.0/(size.y*0.205);
        // The city world carries its own lit-limb halo, drawn before the body so the orbit
        // structures stay in front of it.
        float qlen2=dot(q,q);
        float halo=1.0+2.5*pixelWidth;
        if(qlen2>1.0 && qlen2<halo*halo) {
            float cl=illumination(q,center);
            if(cl>0.10) color=max(color,vec3(52,88,105)/255.0*(cl>0.45 ? 1.0 : 0.55));
        }
        color=infrastructure(q,color,0.0,pixelWidth);
        if(qlen2<=1.0) color=cityPlanet(q,center);
        color=infrastructure(q,color,1.0,pixelWidth);
    }
    color*=iSceneGain;
    // Foreground points never paint across the silhouettes of the planets.
    bool empty = length(q)>1.75 && length(gq)>1.95 && distance(screen,ochre)>0.08
        && distance(screen,moon)>0.03;
    if(empty) color=max(color,stars(pixel,29.0,0.0,1.0)+stars(pixel,47.0,1.0,1.0)
        +stars(pixel,71.0,1.0,2.0));
    color=shipEvent(fragCoord,color);
    fragColor=vec4(color*max(iBrightness,0.0),1.0);
}
