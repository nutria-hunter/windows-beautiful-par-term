"""Find a mid-flyby capture time for each fleet class, using the shader's own schedule.

The ship event is deterministic (180 s slots, hash-chosen delay and skip, one of three fleet
classes per slot), so the interesting moments can be computed instead of hunted for.

Usage: python find_fleets.py
"""

import math

CLASS_NAMES = {0.0: "squadron", 1.0: "task force", 2.0: "grand fleet"}


def fract(value):
    return value - math.floor(value)


def hash21(x, y):
    q = [fract(x * 0.1031), fract(y * 0.1030), fract(x * 0.0973)]
    d = q[0] * (q[1] + 33.33) + q[1] * (q[2] + 33.33) + q[2] * (q[0] + 33.33)
    q = [v + d for v in q]
    return fract((q[0] + q[1]) * q[2])


def fleet_class(seed):
    r = hash21(seed, 211.0)
    if r < 0.30:
        return 0.0
    if r < 0.82:
        return 1.0
    return 2.0


def ship_age(t):
    """(age, seed, class) while a flyby is running, else None."""
    slot = math.floor(t / 180.0)
    seed = hash21(slot, 81.0)
    if seed < 0.22:
        return None
    age = (t - 180.0 * slot) - (18.0 + 70.0 * hash21(slot, 19.0))
    cls = fleet_class(seed)
    life = 22.0 if cls > 1.5 else 16.0
    if 0.0 <= age < life:
        return (age, seed, cls)
    return None


def main():
    found = {}
    for i in range(40000):
        t = i * 0.5
        hit = ship_age(t)
        if hit is None:
            continue
        age, seed, cls = hit
        life = 22.0 if cls > 1.5 else 16.0
        # Mid-flyby: formation fully unfolded, not yet compressing into the exit gate.
        if not (life * 0.35 < age < life * 0.65):
            continue
        if cls not in found:
            found[cls] = (t, age, seed, life)
    for cls in (0.0, 1.0, 2.0):
        if cls in found:
            t, age, seed, life = found[cls]
            print(
                f"{CLASS_NAMES[cls]:11s}: t={t:7.1f}s  age={age:5.1f}s of {life:.0f}s  seed={seed:.3f}"
            )
        else:
            print(f"{CLASS_NAMES[cls]:11s}: none in the first 20000s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
