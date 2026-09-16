#!/usr/bin/env bash
# Verify the IME composition overlay against a par-term binary, without a human at the keyboard.
#
# Three cases, because the overlay has three ways to disappear and each has been a real bug:
#   1. winit's own preedit  - the original source (`PAR_TERM_IME_PREEDIT`).
#   2. the Imm32 reader     - ours, and the one a real IME feeds (`PAR_TERM_IME_IMM_PREEDIT`).
#   3. the Imm32 reader with the terminal cursor HIDDEN - what a TUI does (pi draws its own caret
#      and turns DECTCEM off), which is exactly where the composition used to vanish entirely.
#
# Each case shoots the window twice (no seed, then seeded) and the analysis reports the ink the
# seeded run added. Run it from galaxy-work/work; pass a binary as $1 (default: the installed one).
set -uo pipefail

EXE_ARG="${1:-C:\\Users\\jky72\\par-term\\par-term.exe}"
WORK="C:\\Users\\jky72\\par-term\\galaxy-work\\work"
HIDDEN="$WORK\\hidden-cursor-child.mjs"
status=0

run_case() {
  local tag="$1"
  shift
  echo "=== $tag ==="
  powershell -NoProfile -File ./preedit_shot.ps1 -Exe "$EXE_ARG" "$@" -Tag "$tag" >/dev/null 2>&1
  python analyze_preedit_shot.py "$tag" | tail -4
  if ! python analyze_preedit_shot.py "$tag" | grep -q 'verdict: PASS'; then
    echo "  -> FAILED"
    status=1
  fi
}

run_case ime_win
run_case ime_imm -Imm
run_case ime_hidden -Imm -Child "$HIDDEN"

echo
if [ "$status" -eq 0 ]; then
  echo "ALL PASS: the composition is drawn in all three cases"
else
  echo "AT LEAST ONE CASE FAILED"
fi
exit "$status"
