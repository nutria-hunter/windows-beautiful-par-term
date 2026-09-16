/*! par-term shader metadata
name: Kanagawa - Starbound
author: Codex
description: Flat retro space mural, ink-blue nebula banks, cut-paper planets and quiet pixel stars. Texture-free.
version: 1.4.0
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
    if (r2 > 1.0) return bg;
    float angle=iTime*iSurfaceSpeed*0.018;
    vec2 surface=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*q;
    float ribbons = surface.y + 0.18*surface.x + 0.07*sin(surface.x*5.0)
        + 0.025*sin(surface.x*15.0+surface.y*6.0);
    float stripe = floor(ribbons * 18.0);
    float detail = noise2(surface*5.0 + kind*13.0);
    // A drawn crescent boundary with three flat shades, not a lit 3-D sphere.
    float lightSide = illumination(q,center);
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
    bool road=belt<0.09 && district>0.32;
    bool tower=seed>0.79 && district>0.50;
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
vec3 ring(vec2 q, vec3 bg) {
    vec2 r = vec2(q.x + 0.72*q.y, q.y - 0.27*q.x);
    float e = length(r/vec2(1.90,0.34));
    if (e < 0.70 || e > 1.0) return bg;
    float band = floor((e-0.70)*65.0);
    if (band == 6.0 || band == 7.0 || band == 14.0) return bg;
    float fleck=hash21(floor(r*95.0));
    float tone=mod(band,4.0)/3.0;
    if(fleck>0.83) tone=max(0.0,tone-0.33);
    return mix(vec3(38,49,60),vec3(100,104,89),tone)/255.0;
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
vec3 shipEvent(vec2 fragCoord, vec3 bg) {
    vec2 event=shipSchedule(iTime);
    float age=event.x, seed=event.y;
    if(age<0.0 || age>=16.0 || iShipGain<=0.0) return bg;
    float px=max(floor(iPixelSize),1.0);
    float direction=seed>0.60 ? -1.0 : 1.0;
    vec2 center=vec2(iResolution.x*(0.30+0.40*seed),
        iResolution.y*(0.29+0.25*hash21(vec2(seed,42.0))));
    center.x+=direction*(age-8.0)*3.0;
    // Pixel sprite translated in physical pixels, matching the planets.
    vec2 q=floor((fragCoord-floor(center))/px);
    q.x*=direction;
    q.y+=floor(q.x*0.125);
    if(abs(q.x)>95.0 || abs(q.y)>22.0) return bg;
    vec3 color=bg;
    float ay=abs(q.y);
    // Arrival gate and departure trail stay local; no full-screen flash.
    if(age<1.3) {
        float aperture=floor(sin(age/1.3*3.14159265)*16.0);
        if(abs(q.x-23.0)<=1.0 && ay<aperture)
            color=max(color,vec3(90,146,153)/255.0*iShipGain);
    }
    float launch=max(age-13.5,0.0);
    float offset=floor(launch*launch*26.0);
    vec2 s=q-vec2(offset,0.0);
    float sy=abs(s.y);
    bool spine=s.x>=-25.0 && s.x<=32.0 && sy<=floor(5.0-(max(s.x-13.0,0.0)*0.19));
    bool stern=s.x>=-28.0 && s.x<=-12.0 && sy<=8.0;
    bool wings=s.x>=-23.0 && s.x<=-2.0 && sy>=10.0 && sy<=13.0;
    bool struts=s.x>=-17.0 && s.x<=-12.0 && sy<=12.0;
    bool hull=spine || stern || wings || struts;
    // Materialize from bow to stern rather than fading the entire sprite.
    if(age<1.3 && s.x<32.0-age/1.3*62.0) hull=false;
    if(hull) {
        vec3 metal=vec3(48,58,70)/255.0;
        if(s.y<0.0) metal=vec3(74,83,89)/255.0;
        if(sy<2.0 && s.x>-12.0) metal=vec3(90,93,91)/255.0;
        if(mod(s.x+35.0,9.0)<1.0 && sy>2.0) metal=vec3(34,44,57)/255.0;
        // Raised bridge, inset gold windows, separated rear engine pods.
        if(s.x>-14.0 && s.x<-5.0 && sy<3.0) metal=vec3(92,98,99)/255.0;
        if(s.x>-3.0 && s.x<19.0 && sy==3.0 && mod(s.x,4.0)<1.0)
            metal=vec3(150,128,88)/255.0;
        if((s.x==-28.0 && sy<7.0) || (s.x==-23.0 && sy>=10.0))
            metal=vec3(78,144,155)/255.0;
        color=metal*iShipGain;
    }
    float exhaust=3.0+floor((0.5+0.5*sin(age*2.5))*2.0)+launch*7.0;
    if(age>1.3 && s.x<-28.0 && s.x>-28.0-exhaust && (sy==3.0 || sy==6.0))
        color=max(color,vec3(52,96,118)/255.0*iShipGain);
    if(launch>0.0 && q.x<offset-24.0 && q.x>max(-80.0,offset-95.0)
        && (ay==0.0 || ay==2.0)) {
        float fade=1.0-floor(clamp(launch/2.5,0.0,1.0)*4.0)/4.0;
        color=max(color,vec3(94,144,161)/255.0*iShipGain*fade);
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
    if(gq.y<0.27*gq.x) color=ring(gq,color);
    color=planet(screen,gas,0.15,0.0,color);
    if(gq.y>=0.27*gq.x) color=ring(gq,color);
    color=planet(screen,ochre,0.074,1.0,color);
    color=planet(screen,moon,0.025,0.0,color);
    if(abs(q.x)<1.8 && abs(q.y)<1.5) {
        float pixelWidth=1.0/(size.y*0.205);
        color=infrastructure(q,color,0.0,pixelWidth);
        if(dot(q,q)<=1.0) color=cityPlanet(q,center);
        color=infrastructure(q,color,1.0,pixelWidth);
    }
    color*=iSceneGain;
    // Foreground points never paint across the silhouettes of the planets.
    bool empty = length(q)>1.75 && length(gq)>1.95 && distance(screen,ochre)>0.08
        && distance(screen,moon)>0.03;
    if(empty) color=max(color,stars(pixel,29.0,0.0)+stars(pixel,47.0,1.0));
    color=shipEvent(fragCoord,color);
    fragColor=vec4(color*max(iBrightness,0.0),1.0);
}
