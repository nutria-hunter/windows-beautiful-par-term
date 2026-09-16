"""Pick capture times for the shader's two events, replicating the shader's own arithmetic.

The comet schedule and the eclipse geometry are deterministic, so the times can be found up front
instead of hunting through renders. Aspect and orbit constants mirror the shader.

Note on the eclipse metric: the shadow lands ON the sphere, so "distance from the planet centre"
is always one radius and says nothing. The meaningful number is how far the moon sits from the
lamp axis (`perp`): at 0 the bite is as central as this shallow light allows, at 1 it only
grazes the limb. The lamp's z is small, so the sub-solar point is always near the limb.

Usage: python find_events.py
"""

import math

TAU = 6.28318530718
ASPECT = 3840 / 2160
CITY_R = 0.19
ORBIT_PHASE = 1.2
ORBIT_RATE = 1.0
ORBIT_HEIGHT = 0.25
MOON_ANGLE0 = 3.3
MOON_RATE = 0.009


def fract(value):
    return value - math.floor(value)


def hash21(x, y):
    """The shader's hash21, so the schedule matches frame for frame."""
    q = [fract(x * 0.1031), fract(y * 0.1030), fract(x * 0.0973)]
    d = q[0] * (q[1] + 33.33) + q[1] * (q[2] + 33.33) + q[2] * (q[0] + 33.33)
    q = [v + d for v in q]
    return fract((q[0] + q[1]) * q[2])


def city_center(t):
    a = ORBIT_PHASE + t * TAU / 1080.0 * ORBIT_RATE
    return (ASPECT * (0.5 + 0.78 * math.cos(a)), 0.5 + ORBIT_HEIGHT * math.sin(a))


def comet_age(t):
    """Seconds into a comet event, or -1 while the sky is quiet."""
    slot = math.floor(t / 240.0)
    if hash21(slot, 137.0) < 0.38:
        return -1.0
    return (t - 240.0 * slot) - (20.0 + 150.0 * hash21(slot, 53.0))


def eclipse_perp(t):
    """Moon offset from the lamp axis in planet radii, or None when no shadow can land."""
    cx, cy = city_center(t)
    th = t * MOON_RATE + MOON_ANGLE0
    ml = (0.27 * math.cos(th) / CITY_R, 0.24 * math.sin(th) / CITY_R)
    lamp = (ASPECT * 0.32 - cx, -0.35 - cy)
    ln = math.hypot(*lamp)
    ld = (lamp[0] / ln, lamp[1] / ln)
    along = ml[0] * ld[0] + ml[1] * ld[1]
    perp_vec = (ml[0] - ld[0] * along, ml[1] - ld[1] * along)
    if along <= 0.0:
        return None
    return math.hypot(*perp_vec)


def main():
    for i in range(40000):
        t = i * 0.5
        age = comet_age(t)
        if 0.0 <= age <= 9.0:
            print(f"comet: t={t:.1f}s (age {age:.1f}s), repeats every 240s")
            break

    best = None
    on_disk = 0
    for i in range(40000):
        t = i * 0.5
        p = eclipse_perp(t)
        if p is None:
            continue
        if p < 1.0:
            on_disk += 1
        if p < 0.35:
            cx, cy = city_center(t)
            # The bite has to be on a planet that is fully framed, or the event happens off-screen.
            framed = 0.2 < cx < ASPECT - 0.2 and 0.2 < cy < 0.8
            if framed and (best is None or t < best[0]):
                best = (t, p)
    span = 40000 * 0.5
    print(
        f"eclipse: first framed bite t={best[0]:.1f}s (moon {best[1]:.3f} radii off the lamp axis)"
        if best
        else "eclipse: none framed"
    )
    print(
        f"eclipse: shadow lands on the disk for {on_disk / (span / 0.5) * 100:.0f}% of the time"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
