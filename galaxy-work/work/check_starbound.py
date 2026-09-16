"""Isolated Starbound render checks; does not modify active app configuration."""
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
import render_check as harness


def main():
    import moderngl
    root = Path(__file__).resolve().parents[1]
    out = root / 'outputs' / 'starbound'
    out.mkdir(exist_ok=True)
    source = (root / 'shaders' / 'kanagawa-starbound.glsl').read_text(encoding='utf-8')
    ctx = moderngl.create_standalone_context(require=330)
    report = {}
    for w, h in [(3840, 2160), (1280, 720), (1300, 900), (900, 1300)]:
        program = harness.build(ctx, source, w, h)
        a = np.asarray(harness.shade(ctx, program, w, h, 12.0))
        b = np.asarray(harness.shade(ctx, program, w, h, 19.0))
        changed = np.any(a != b, axis=2)
        assert changed.any(), 'Animation is frozen'
        # Every complete logical pixel must have identical output throughout.
        px = int(harness.default_of(source, 'iPixelSize'))
        # Background owns a fixed grid; translating sprites own offset grids.
        # Verify the common grid on a diagnostic frame with sprites removed.
        bg_source = source.replace('    vec2 center = orbit(aspect,1.2,1.0,0.29);',
            '    fragColor=vec4(color*max(iBrightness,0.0),1.0); return;\n    vec2 center = orbit(aspect,1.2,1.0,0.29);')
        bg_program = harness.build(ctx, bg_source, w, h)
        # Background-only compiler removes time; render helper expects it.
        fb=ctx.simple_framebuffer((w,h),components=3)
        fb.use()
        vao=ctx.vertex_array(bg_program,[])
        vao.render(vertices=3)
        bg=np.frombuffer(fb.read(components=3),dtype=np.uint8).reshape(h,w,3)[::-1]
        block = bg[:h//px*px, :w//px*px].reshape(h//px,px,w//px,px,3)
        assert np.all(block == block[:, :1, :, :1, :]), 'Non-flat background pixels'
        vao.release(); fb.release(); bg_program.release()
        for key in ('iOrbitSpeed', 'iSurfaceSpeed', 'iCityFlow', 'iWarpRate'):
            if key in program:
                program[key].value = 0.0
        program['iDrift'].value = 0.0
        still_a = np.asarray(harness.shade(ctx, program, w, h, 12.0))
        still_b = np.asarray(harness.shade(ctx, program, w, h, 19.0))
        assert np.any(still_a != still_b), 'Stationary stars do not twinkle'
        # This limit applies to stars, not the newly requested moving planets.
        assert np.any(still_a != still_b, axis=2).mean() < 0.03
        program['iTwinkle'].value = 0.0
        fixed_a = np.asarray(harness.shade(ctx, program, w, h, 12.0))
        fixed_b = np.asarray(harness.shade(ctx, program, w, h, 19.0))
        assert np.array_equal(fixed_a, fixed_b), 'Disabled animation still changes'
        report[f'{w}x{h}'] = dict(changed_fraction=float(changed.mean()), **harness.stats(a.astype(float)))
        image = Image.fromarray(a)
        image.save(out / f'background-{w}x{h}.png')
        if w == 3840:
            image.resize((1920,1080), Image.Resampling.NEAREST).save(out / 'preview.png')
        if w == 1280:
            # Explicit mockup: composited text, not a live terminal screenshot.
            draw = ImageDraw.Draw(image)
            font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 19)
            rows = [('Kanagawa / Starbound  -  text readability mockup', '#DCD7BA'),
                    ('PS C:\\workspace> git status', '#DCD7BA'),
                    ('On branch main', '#98BB6C'), ('Your branch is up to date.', '#7E9CD8'),
                    ('', '#DCD7BA'), ('def render_scene(time, palette):', '#957FB8'),
                    ('    # calm space, crisp letters', '#727169'),
                    ('    return stars.twinkle(time)', '#7AA89F')]
            for y in range(22, h-20, 220):
                for i,(line,color) in enumerate(rows):
                    draw.text((24,y+i*24),line,font=font,fill=color)
            image.save(out / 'text-mockup.png')
        program.release()
    ctx.release()
    (out/'checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    shutil.copy2(root/'outputs'/'validation.json',out/'performance.json')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
