"""Split the largest function in the starbound shader, to find out whether function size drives the
compile cliff.

Measured: par-term has no size guard anywhere, the pipeline thread never reports (neither success nor
failure) even after 95 s on the 104 KB file, and the working ceiling sits at ~70 KB GLSL. The next
question is *what* about the size costs so much. DX12 compiles super-linearly in function size, and
`incursionEvent` alone is 293 lines / 17.5 KB - a third of the shader's biggest three functions. So:
extract its self-contained ring-battery barrage into its own function, changing nothing else, and see
whether the same total size suddenly compiles.

Output is a *new* file; the installed shader is left alone until the result is known.
"""

import re
import sys

SRC = r"C:\Users\jky72\par-term\galaxy-work\shaders\kanagawa-starbound.glsl"
DST = r"C:\Users\jky72\par-term\galaxy-work\shaders\zz-split1.glsl"

START_MARK = "    // Defensive fire:"
END_MARK = "    // Wrecks are independent of battery count"


def main():
    try:
        with open(SRC, "rb") as handle:
            text = handle.read().decode("utf-8")
    except OSError as exc:
        print(f"FAIL: cannot read {SRC}: {exc}")
        sys.exit(1)

    crlf = "\r\n" in text
    text = text.replace("\r\n", "\n")

    start = text.find(START_MARK)
    end = text.find(END_MARK, start)
    if start < 0 or end < 0:
        print(f"FAIL: markers not found (start={start}, end={end})")
        sys.exit(1)
    block = text[start:end]

    # Inner body of `if(attack>0.5) { ... }`, without the guard or the trailing brace.
    brace = block.find("if(attack>0.5) {")
    if brace < 0:
        print("FAIL: guard not found inside the block")
        sys.exit(1)
    inner = block[brace + len("if(attack>0.5) {") :]
    inner = inner.rstrip()
    if not inner.endswith("}"):
        print("FAIL: block does not end with a closing brace")
        sys.exit(1)
    inner = inner[:-1].rstrip("\n")

    helper = (
        "// The orbital ring's batteries: their own barrage, extracted from `incursionEvent`. The\n"
        "// shader is at the ceiling of what the DX12 shader compiler will finish, and a single\n"
        "// 300-line function is the kind of thing that costs super-linearly there - smaller functions\n"
        "// compile individually and the features stay exactly as they were.\n"
        "vec3 ringBarrage(vec3 color, vec2 fragCoord, float px, vec2 size, vec2 target, float targetR,\n"
        "                 float age, float seed, float count, vec2 formation, vec2 forward, vec2 sidev,\n"
        "                 float attack) {\n"
        "    if(attack<=0.5) return color;\n"
        f"{inner}\n"
        "    return color;\n"
        "}\n\n"
    )

    call = (
        "    color=ringBarrage(color,fragCoord,px,size,target,targetR,age,seed,float(count),"
        "formation,forward,sidev,attack);\n"
    )

    # Put the helper immediately before the function it came from.
    anchor = "vec3 incursionEvent("
    position = text.find(anchor)
    if position < 0:
        print("FAIL: incursionEvent not found")
        sys.exit(1)
    text = text[:position] + helper + text[position:]
    text = text[:start] + call + text[end:]

    # The extracted body referred to the enclosing locals; make sure the parameter names match them.
    missing = [
        name
        for name in (
            "px",
            "size",
            "target",
            "targetR",
            "age",
            "seed",
            "count",
            "formation",
            "forward",
            "sidev",
            "attack",
        )
        if not re.search(rf"\b{name}\b", inner)
    ]

    out = text.replace("\n", "\r\n") if crlf else text
    try:
        with open(DST, "wb") as handle:
            handle.write(out.encode("utf-8"))
    except OSError as exc:
        print(f"FAIL: cannot write {DST}: {exc}")
        sys.exit(1)

    print(
        f"ok: wrote {DST} ({len(out.encode('utf-8')) / 1024:.1f} KB, was {len(text.encode('utf-8')) / 1024:.1f} KB)"
    )
    print(
        f"    extracted {len(inner.splitlines())} lines into ringBarrage(); unused params: {missing or 'none'}"
    )


if __name__ == "__main__":
    main()
