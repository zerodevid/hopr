#!/usr/bin/env bash
#
# Records a clean, fixed-duration screen clip for the Hopr product video.
#
#   ./record-demo.sh <name> [seconds]
#
# Examples:
#   ./record-demo.sh hint   10
#   ./record-demo.sh scroll 9
#   ./record-demo.sh search 10
#
# Output → video/public/footage/<name>.mov   (where the Remotion build reads it)
#
# First run will trigger a one-time macOS prompt:
#   System Settings → Privacy & Security → Screen Recording → enable your Terminal.
# Approve it, then run the command again.
#
set -euo pipefail

NAME="${1:?usage: ./record-demo.sh <hint|scroll|search|...> [seconds]}"
DUR="${2:-10}"

DIR="$(cd "$(dirname "$0")" && pwd)/public/footage"
mkdir -p "$DIR"
OUT="$DIR/${NAME}.mov"

echo ""
echo "  ●  Recording '${NAME}'  —  ${DUR}s  →  public/footage/${NAME}.mov"
echo "     Tip: clean desktop, single app, hide private windows."
echo ""

for i in 3 2 1; do
  printf "     starting in %s...\r" "$i"
  say "$i" >/dev/null 2>&1 || true
  sleep 1
done

echo "     ● REC — do the demo now!            "
say "recording" >/dev/null 2>&1 || true

# -v video, -V<sec> fixed duration, -x no UI sound, -C capture cursor
screencapture -x -C -v -V"${DUR}" "$OUT"

echo ""
echo "  ✓  Saved → ${OUT}"
say "done" >/dev/null 2>&1 || true

# Quick sanity probe (needs ffprobe; ignore if missing)
if command -v ffprobe >/dev/null 2>&1; then
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate \
    -show_entries format=duration -of default=noprint_wrappers=1 "$OUT" || true
fi
