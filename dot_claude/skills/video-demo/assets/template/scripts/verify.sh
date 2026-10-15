#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
FILE="${1:-out/tour-final.mp4}"

echo "## streams"
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels -of csv=p=0 "$FILE"
echo "## duration"
ffprobe -v error -show_entries format=duration,size -of csv=p=0 "$FILE"
echo "## loudness"
ffmpeg -i "$FILE" -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume"

mkdir -p work/verify
uv run --no-project python scripts/chapters.py "$FILE"
