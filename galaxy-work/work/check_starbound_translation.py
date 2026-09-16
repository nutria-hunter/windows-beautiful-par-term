"""Verify actual GLSL local blocks survive physical 1px sprite translations."""
import json
from pathlib import Path
import numpy as np
import render_check as harness


def main():
    import moderngl
    root=Path(__file__).resolve().parents[1]
    src=(root/'shaders'/'kanagawa-starbound.glsl').read_text(encoding='utf-8')
    src=src.replace('void mainImage(', 'void unusedMain(')
    src+='''
uniform float iTestOffset;
void mainImage(out vec4 c,in vec2 f) {
    vec2 center=vec2((320.0+iTestOffset)/iResolution.y,0.5);
    vec2 q=bodyLocal(f/iResolution.y,center,0.20);
    c=vec4(0,0,0,1);
    if(dot(q,q)<1.0) c=vec4(cityPlanet(q,vec2(320.0/iResolution.y,0.5)),1);
}
'''
    ctx=moderngl.create_standalone_context(require=330)
    p=harness.build(ctx,src,640,360)
    p['iSurfaceSpeed'].value=0
    p['iCityFlow'].value=0
    p['iTestOffset'].value=0
    a=np.asarray(harness.shade(ctx,p,640,360,12.0))
    b4=a.reshape(90,4,160,4,3)
    assert np.all(b4==b4[:,:1,:,:1,:]), 'City is not made of flat 4px blocks'
    p['iTestOffset'].value=1
    b=np.asarray(harness.shade(ctx,p,640,360,12.0))
    assert np.array_equal(a[:,:-1],b[:,1:]), '1px shift changed the sprite texture'
    assert not np.array_equal(a,b), 'Still trapped on 4px grid'
    result={'city_local_blocks_are_4px':True,'physical_1px_translation_exact':True,
            'note':'No AA/subpixel interpolation; rendering at 120fps does not guarantee 120 distinct poses per second.'}
    (root/'outputs'/'starbound'/'translation-checks.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))
    p.release(); ctx.release()


if __name__=='__main__':
    main()
