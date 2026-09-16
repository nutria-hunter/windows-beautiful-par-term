"""Exercise the actual GLSL event scheduler and isolated ship lifecycle."""
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import render_check as h


def main():
    import moderngl
    root=Path(__file__).resolve().parents[1]
    out=root/'outputs'/'starbound'
    src=(root/'shaders'/'kanagawa-starbound.glsl').read_text(encoding='utf-8')
    ctx=moderngl.create_standalone_context(require=330)
    renamed=src.replace('void mainImage(', 'void unusedMain(')
    sched=h.build(ctx,renamed+'\nvoid mainImage(out vec4 c,in vec2 f){c=vec4(shipSchedule(iTime),0,1);}',1,1)
    tex=ctx.texture((1,1),4,dtype='f4'); fb=ctx.framebuffer([tex]); vao=ctx.vertex_array(sched,[])
    starts=[]
    for slot in range(20):
        sched['iTime'].value=float(slot*180)
        fb.use(); vao.render(vertices=3)
        value=np.frombuffer(fb.read(components=4,dtype='f4'),dtype=np.float32)
        if value[0]>-99:
            starts.append(slot*180-float(value[0]))
    assert len(starts)>3 and len(starts)<20
    assert np.ptp(np.diff(starts))>1, 'Timing is not varied'
    assert min(np.diff(starts))>16, 'Events overlap'
    start=starts[0]
    ship=h.build(ctx,renamed+'\nvoid mainImage(out vec4 c,in vec2 f){c=vec4(shipEvent(f,vec3(0)),1);}',1280,720)
    ages=[-0.1,0.65,5.0,13.8,14.5,16.1]
    sheet=Image.new('RGB',(1920,528))
    draw=ImageDraw.Draw(sheet)
    areas=[]
    for i,age in enumerate(ages):
        img=h.shade(ctx,ship,1280,720,start+age)
        arr=np.asarray(img)
        area=float(np.any(arr!=0,axis=2).mean())
        areas.append(area)
        if age<0 or age>16: assert area==0,'Ship remains outside its event'
        else: assert 0<area<0.025,'Event invisible or too large'
        # Center crop shows the actual logical sprite without resampling.
        crop=img.crop((320,240,960,480))
        x=i%3*640; y=i//3*264
        sheet.paste(crop,(x,y+24))
        draw.text((x+10,y+5),f'Event +{age:.2f}s',fill='#DCD7BA')
    sheet.save(out/'ship-lifecycle.png')
    ship['iWarpRate'].value=0.0
    assert np.asarray(h.shade(ctx,ship,1280,720,start+5)).max()==0
    full=h.build(ctx,src,3840,2160)
    image=h.shade(ctx,full,3840,2160,start+5)
    image.resize((1920,1080),Image.Resampling.NEAREST).save(out/'ship-preview.png')
    variants=h.build(ctx,src,1280,720)
    variation=Image.new('RGB',(1280,720))
    for i,t in enumerate(starts[:4]):
        frame=h.shade(ctx,variants,1280,720,t+5)
        variation.paste(frame.resize((640,360),Image.Resampling.NEAREST),((i%2)*640,(i//2)*360))
    variation.save(out/'fleet-variants.png')
    variants.release()
    # Timer query during an active event, not just the fast inactive path.
    bench=ctx.simple_framebuffer((3840,2160)); bench.use()
    bv=ctx.vertex_array(full,[]); full['iTime'].value=start+5
    times=[]
    for i in range(14):
        query=ctx.query(time=True)
        with query: bv.render(vertices=3)
        ctx.finish()
        if i>=4: times.append(query.elapsed/1e6)
    report={'first_event_seconds':start,'starts_first_hour':starts,
            'lifecycle_pixel_fractions':areas,'disable_is_black':True,
            'active_4k_gpu_ms_median':float(np.median(times))}
    (out/'ship-checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))
    bv.release(); bench.release(); full.release(); ship.release()
    vao.release(); fb.release(); tex.release(); sched.release(); ctx.release()


if __name__=='__main__':
    main()
