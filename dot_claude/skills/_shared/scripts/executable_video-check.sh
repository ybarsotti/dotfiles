#!/usr/bin/env bash
# Checks that a video shows something happening, before it goes into a PR or a report.
# A video of a screen where nothing moves (the data arrived through the database, the page
# waited, the recording missed the action) fails.
#
# Usage: video-check.sh <video>...
# Exit 0 when every video passes. Exit 1 names each video that fails, with its frozen share.
# MAX_FROZEN (default 60) is the highest percent of the duration that may show a still frame.
set -euo pipefail

MAX_FROZEN="${MAX_FROZEN:-60}"
status=0
for v in "$@"; do
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$v")"
  # A still frame counts when it lasts 2 s or more. Noise 0.003 ignores a blinking cursor.
  frozen="$(ffmpeg -hide_banner -nostats -i "$v" -vf freezedetect=n=0.003:d=2 -map 0:v:0 -f null - 2>&1 \
    | awk -F'freeze_duration: ' '/freeze_duration/ {s += $2} END {print s + 0}')"
  # A freeze that runs to the end of the video has no freeze_end line; count it from its start.
  tail_start="$(ffmpeg -hide_banner -nostats -i "$v" -vf freezedetect=n=0.003:d=2 -map 0:v:0 -f null - 2>&1 \
    | awk -F'freeze_(start|end): ' '/freeze_start/ {s=$2; open=1} /freeze_end/ {open=0} END {if (open) print s}')"
  if [ -n "$tail_start" ]; then
    frozen="$(awk -v f="$frozen" -v d="$dur" -v t="$tail_start" 'BEGIN {print f + d - t}')"
  fi
  pct="$(awk -v f="$frozen" -v d="$dur" 'BEGIN {printf "%d", (d > 0 ? 100 * f / d : 100)}')"
  if [ "$pct" -gt "$MAX_FROZEN" ]; then
    echo "FAIL $v: ${pct}% of ${dur%.*} s is a still frame. Record the action itself through the UI."
    status=1
  else
    echo "ok   $v: ${pct}% still"
  fi
done
exit "$status"
