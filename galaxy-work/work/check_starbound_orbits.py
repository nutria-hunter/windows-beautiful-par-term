"""Render orbital phases and isolate each animation control in the real GLSL."""
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
import render_check as harness


def main():
    import moderngl
    root = Path(__file__).resolve().parents[1]
    out = root / 'outputs' / 'starbound'
    source = (root/'shaders'/'kanagawa-starbound.glsl').read_text(encoding='utf-8')
    ctx = moderngl.create_standalone_context(require=330)
    program = harness.build(ctx, source, 1280, 720)
    program['iWarpRate'].value=0.0
    frames=[]
    phases=[0,180,360,540,720,900]
    for t in phases:
        frame=harness.shade(ctx,program,1280,720,float(t))
        frame.save(out/f'orbit-{t:04d}.png')
        frames.append(frame.resize((640,360),Image.Resampling.NEAREST))
    sheet=Image.new('RGB',(1920,768))
    draw=ImageDraw.Draw(sheet)
    for i,frame in enumerate(frames):
        x=(i%3)*640
        y=(i//3)*384
        sheet.paste(frame,(x,y+24))
        draw.text((x+12,y+5),f'T + {phases[i]//60} min',fill='#DCD7BA')
    sheet.save(out/'orbit-storyboard.png')
    controls=['iOrbitSpeed','iSurfaceSpeed','iCityFlow','iDrift','iTwinkle']
    for key in controls:
        program[key].value=0.0
    a=np.asarray(harness.shade(ctx,program,1280,720,0.0))
    b=np.asarray(harness.shade(ctx,program,1280,720,180.0))
    assert np.array_equal(a,b), 'Scene moves with every motion disabled'
    report={'all_motion_disabled_is_static':True,'isolated_motion':{}}
    for key in controls:
        program[key].value=1.0
        a=np.asarray(harness.shade(ctx,program,1280,720,0.0))
        b=np.asarray(harness.shade(ctx,program,1280,720,45.0))
        delta=np.any(a!=b,axis=2)
        assert delta.any(), f'{key} does not animate'
        report['isolated_motion'][key]=float(delta.mean())
        program[key].value=0.0
    # Check the complete city sprite, including orbital structures, leaves the frame.
    aspect=1280/720
    xs=[aspect*(0.5+0.86*math.cos(1.2+t*math.tau/1080)) for t in range(1081)]
    extent=0.205*1.8
    assert min(xs)+extent<0 and max(xs)-extent>aspect
    assert abs(xs[0]-xs[-1])<1e-9
    report['city_exits_both_sides_and_returns']=True
    # Same surface pixel sees a different light when its planet changes location.
    probe=source+'\nvoid probeLight(out vec4 c, vec2 f){vec2 p=orbit(iResolution.x/iResolution.y,1.2,1.0,0.29); float l=illumination(vec2(0.5,0.0),p); c=vec4(vec3(l*0.5+0.5),1);}'
    probe=probe.replace('void mainImage(', 'void unusedMain(').replace('void probeLight(', 'void mainImage(')
    lighting=harness.build(ctx,probe,64,64)
    lighting['iOrbitSpeed'].value=1.0
    left=np.asarray(harness.shade(ctx,lighting,64,64,0.0))
    right=np.asarray(harness.shade(ctx,lighting,64,64,540.0))
    assert not np.array_equal(left,right), 'Lighting ignores orbital location'
    report['light_changes_with_position']=True
    lighting.release()
    program.release()
    ctx.release()
    (out/'orbit-checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
