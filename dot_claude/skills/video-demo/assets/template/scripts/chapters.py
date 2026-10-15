"""One still per chapter of the rendered tour into work/verify/chapters.png (run by verify.sh)."""
import json, math, subprocess, sys

file = sys.argv[1]
manifest = json.load(open("src/manifest.json"))
# Mirrors FPS, LEAD_IN, TAIL and TRANSITION in src/timing.ts.
FPS, LEAD, TAIL, TR = 30, 0.5, 0.7, 14
start = 0
names = []
for index, segment in enumerate(manifest["segments"]):
    frames = math.ceil((LEAD + segment["duration"] + TAIL) * FPS)
    at = (start + min(frames - 20, int(frames * 0.55))) / FPS
    out = f"work/verify/{index + 1:02d}-{segment['id']}.png"
    subprocess.run(["ffmpeg", "-nostdin", "-y", "-loglevel", "error", "-ss", f"{at:.3f}", "-i", file, "-frames:v", "1", "-vf", "scale=640:-2", out], check=True)
    names.append(out)
    print(f"{segment['id']:18s} still at {at:7.2f}s")
    start += frames - TR
inputs = sum([["-i", name] for name in names], [])
subprocess.run(["ffmpeg", "-nostdin", "-y", "-loglevel", "error", *inputs, "-filter_complex", "".join(f"[{i}]" for i in range(len(names))) + f"xstack=inputs={len(names)}:layout=" + "|".join(f"{(i % 3) * 640}_{(i // 3) * 360}" for i in range(len(names))), "work/verify/chapters.png"], check=True)
print("work/verify/chapters.png")
