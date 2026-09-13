"""Print many lines, to make the terminal produce scrollback."""

import sys

count = 200
if len(sys.argv) > 1:
    try:
        count = int(sys.argv[1])
    except ValueError:
        print(f"count must be an integer, got {sys.argv[1]!r}")
        raise SystemExit(2) from None

for i in range(1, count + 1):
    print(f"scrollback line {i}")
