"""Split `incursionEvent`'s ring-battery barrage out by matching braces.

Replaces the whole `if(attack>0.5) { ... }` statement with a call, so no fragment of the original can
survive (the first attempt trimmed a brace by hand and the loader rejected the result with
`UnknownVariable("w")`).
"""

import sys

SRC = r"C:\Users\jky72\par-term\galaxy-work\shaders\kanagawa-starbound.glsl"
DST = r"C:\Users\jky72\par-term\galaxy-work\shaders\zz-split2.glsl"
GUARD = "if(attack>0.5) {"
FUNC = "vec3 incursionEvent("

HELPER = """// The orbital ring's batteries. Extracted from `incursionEvent` unchanged in behaviour: the shader
// sits at the ceiling of what the DX12 shader compiler will finish, and one 300-line function costs
// far more there than the same work split across several smaller ones.
vec3 ringBarrage(vec3 color, vec2 fragCoord, float px, vec2 size, vec2 target, float targetR,
                 float age, float seed, float count, vec2 formation, vec2 forward, vec2 sidev) {
{body}
    return color;
}

"""

CALL = (
    "color=ringBarrage(color,fragCoord,px,size,target,targetR,age,seed,float(count),"
    "formation,forward,sidev);"
)


def match_brace(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unbalanced braces")


def main():
    try:
        with open(SRC, "rb") as handle:
            raw = handle.read().decode("utf-8")
    except OSError as exc:
        print(f"FAIL: cannot read {SRC}: {exc}")
        sys.exit(1)

    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")

    guard = text.find(GUARD)
    function = text.find(FUNC)
    if guard < 0 or function < 0:
        print(f"FAIL: guard={guard}, function={function}")
        sys.exit(1)

    brace_open = text.index("{", guard)
    brace_close = match_brace(text, brace_open)
    body = text[brace_open + 1 : brace_close].strip("\n")

    text = text[:function] + HELPER.replace("{body}", body) + text[function:]

    # Locate the guard again: everything before the function definition is unaffected by the insert,
    # but the guard itself has shifted by the helper's length.
    guard = text.index(GUARD, text.find(FUNC))
    brace_open = text.index("{", guard)
    brace_close = match_brace(text, brace_open)
    text = text[:guard] + CALL + text[brace_close + 1 :]

    out = text.replace("\n", "\r\n") if crlf else text
    try:
        with open(DST, "wb") as handle:
            handle.write(out.encode("utf-8"))
    except OSError as exc:
        print(f"FAIL: cannot write {DST}: {exc}")
        sys.exit(1)

    print(
        f"ok: {DST} ({len(out.encode('utf-8')) / 1024:.1f} KB), body {len(body.splitlines())} lines"
    )


if __name__ == "__main__":
    main()
