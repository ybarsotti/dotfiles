#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ffmpeg -y -loglevel error \
  -i out/tour.mp4 \
  -c:v libx264 -preset medium -crf 20 -vf "scale=in_range=full:out_range=tv,format=yuv420p" \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000" \
  -ar 48000 -ac 2 -c:a aac -b:a 192k -movflags +faststart \
  out/tour-final.mp4

ffprobe -v error -show_entries stream=codec_name,width,height,sample_rate,channels -of csv=p=0 out/tour-final.mp4
ffmpeg -i out/tour-final.mp4 -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume"
