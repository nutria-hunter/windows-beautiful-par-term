"""Make fleet crossings actually leave the frame, instead of warping out mid-screen.

Confirmed by reading the code: `shipEvent` derived its speed from a fixed `iResolution.y*0.045`, so
a crossing covered about 4.5% of a screen height and the whole warp-out - compression plus gate -
played out in the middle of the frame. The user's requirement is the opposite: every moving body
must travel clear of the viewport before it is retired.

Kept as a script because the shader is checked out CRLF, where a multi-line editor match fails.
"""

import sys

PATH = r"C:\Users\jky72\par-term\galaxy-work\shaders\kanagawa-starbound.glsl"

# Where a per-crossing travel distance can live, next to the other geometry helpers.
HELPER_ANCHOR = """vec2 snapFine(vec2 v) { float p=max(floor(iPixelSize),1.0); return floor(v*p)/p; }
"""

HELPER_NEW = """vec2 snapFine(vec2 v) { float p=max(floor(iPixelSize),1.0); return floor(v*p)/p; }
// Distance from `from`, along `dir`, until the point is `margin` outside the viewport rectangle (all
// in the same units: the block frame `size` uses). Crossings use it so a formation leaves the frame
// instead of ending its life wherever a fixed step happened to stop. Floored at zero because `from`
// can already sit outside on one axis.
float exitDistance(vec2 from, vec2 dir, vec2 viewport, float margin) {
    vec2 d=max(abs(dir),vec2(1e-4));
    vec2 edge=vec2(dir.x>0.0 ? viewport.x+margin-from.x : -margin-from.x,
                   dir.y>0.0 ? viewport.y+margin-from.y : -margin-from.y);
    return max(0.0,min(edge.x/d.x,edge.y/d.y));
}
"""

SPEED_ANCHOR = """        float speed=iResolution.y*0.045/cruiseEnd;
        vec2 exitPoint=entry+forward*speed*cruiseEnd;
"""

SPEED_NEW = """        // How far this hull has to travel to be clear of the frame, not a fixed 4.5% of a screen
        // height: a fixed step ended every flyby - compression, gate and all - in the middle of the
        // view, and the hulls then blinked out there. Distance to the edge plus a margin keeps the
        // farewell in the last part of the crossing instead of in the middle of the sky.
        float travel=exitDistance(entry,forward,iResolution,iResolution.y*0.14);
        float speed=travel/cruiseEnd;
        vec2 exitPoint=entry+forward*speed*cruiseEnd;
"""

MARGIN_ANCHOR = """    vec2 entryP=vec2(-0.16,lane);
    vec2 exitP=vec2(aspect+0.16,lane+(hash21(vec2(seed,43.0))-0.5)*0.10);
"""

MARGIN_NEW = """    // Wide enough for the whole formation: trailing hulls sit up to ~0.2 behind the leader, so a
    // 0.16 margin left the last raider just inside the right edge when the event retired it.
    vec2 entryP=vec2(-0.42,lane);
    vec2 exitP=vec2(aspect+0.42,lane+(hash21(vec2(seed,43.0))-0.5)*0.10);
"""


def main():
    try:
        with open(PATH, "rb") as handle:
            raw = handle.read()
    except OSError as exc:
        print(f"FAIL: cannot read {PATH}: {exc}")
        sys.exit(1)

    crlf = raw.count(b"\r\n") > 0
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for anchor, replacement, label in (
        (HELPER_ANCHOR, HELPER_NEW, "exitDistance helper"),
        (SPEED_ANCHOR, SPEED_NEW, "fleet crossing distance"),
        (MARGIN_ANCHOR, MARGIN_NEW, "incursion entry/exit margin"),
    ):
        if text.count(anchor) != 1:
            print(f"FAIL: {label}: anchor found {text.count(anchor)}x")
            sys.exit(1)
        text = text.replace(anchor, replacement)

    out = text.replace("\n", "\r\n") if crlf else text
    try:
        with open(PATH, "wb") as handle:
            handle.write(out.encode("utf-8"))
    except OSError as exc:
        print(f"FAIL: cannot write {PATH}: {exc}")
        sys.exit(1)
    print(f"ok: applied 3 edits ({'CRLF' if crlf else 'LF'})")


if __name__ == "__main__":
    main()
