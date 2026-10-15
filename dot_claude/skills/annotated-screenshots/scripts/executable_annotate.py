#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10.1"]
# ///
"""Draw highlight boxes, numbered callouts and a caption banner on screenshots.

Usage: annotate.py SPEC.json [--only OUT_NAME]

The spec lists shots. Every coordinate in the spec is in CSS pixels; the
script multiplies it by `scale` (the device scale factor of the capture).
Paths in the spec resolve against the directory of the spec file. See
references/spec.md for the full format.
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = {
    "bold": [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ],
    "regular": [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ],
}
TONES = {
    "green": (22, 163, 74),
    "amber": (217, 119, 6),
    "red": (220, 38, 38),
    "blue": (37, 99, 235),
    "purple": (124, 58, 237),
}
SOURCE_COLORS = {"live": (134, 239, 172), "fixture": (252, 211, 77)}
SOURCE_PREFIX = {"live": "LIVE APP", "fixture": "COMPONENT RENDER WITH FIXTURE DATA"}
BANNER_BG = (17, 24, 39)
DIM_ALPHA = 70  # 0 = no dimming outside the boxes, 255 = black.
PILL_H = 32  # Callout pill height in CSS px.


def load_font(kind, size):
    for path in FONT_CANDIDATES[kind]:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def pad(box, p):
    return (box[0] - p, box[1] - p, box[2] + p, box[3] + p)


def shift(values, dx, dy):
    return [v - (dx if i % 2 == 0 else dy) for i, v in enumerate(values)]


def default_label_at(box, label_width, image_width):
    """Place a callout right of the box, else left, else above, else under (CSS px).

    Beside the box, the pill is centered on it vertically.
    """
    x0, y0, x1, y1 = box
    mid_y = y0 + (y1 - y0) / 2 - PILL_H / 2
    if x1 + 24 + label_width < image_width:
        return (x1 + 24, mid_y)
    if x0 - 24 - label_width > 0:
        return (x0 - 24 - label_width, mid_y)
    if y0 - 16 - PILL_H >= 0:
        return (x0, y0 - 16 - PILL_H)
    return (x0, y1 + 16)


def annotate(shot, root, scale):
    s = shot.get("scale", scale)
    src = root / shot["src"]
    if not src.exists():
        sys.exit(f"error: src not found: {src}")
    img = Image.open(src).convert("RGB")
    marks = [dict(m) for m in shot.get("marks", [])]
    crop = shot.get("crop")
    if crop:
        x0, y0, x1, y1 = crop
        img = img.crop((x0 * s, y0 * s, x1 * s, y1 * s))
        for m in marks:
            m["box"] = shift(m["box"], x0, y0)
            if "label_at" in m:
                m["label_at"] = shift(m["label_at"], x0, y0)
    w, h = img.size
    has_banner = bool(shot.get("title") or shot.get("source"))
    banner_h = 60 * s if has_banner else 0
    canvas = Image.new("RGB", (w, h + banner_h), BANNER_BG)
    canvas.paste(img, (0, 0))

    # Dim everything except the highlighted boxes.
    dim = Image.new("L", (w, h), shot.get("dim", DIM_ALPHA))
    dim_draw = ImageDraw.Draw(dim)
    for m in marks:
        dim_draw.rounded_rectangle(
            [v * s for v in pad(m["box"], 3)], radius=8 * s, fill=0
        )
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(overlay).bitmap((0, 0), dim, fill=(15, 23, 42, 255))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), overlay)
    draw = ImageDraw.Draw(canvas)

    f_label, f_num = load_font("bold", 15 * s), load_font("bold", 14 * s)
    callouts = []
    for n, m in enumerate(marks, 1):
        tone_name = m.get("tone", "green")
        if tone_name not in TONES:
            sys.exit(f"error: unknown tone {tone_name!r}; valid tones: {', '.join(TONES)}")
        tone = TONES[tone_name]
        box = [v * s for v in pad(m["box"], 3)]
        pill_w = draw.textlength(m["label"], font=f_label) + 48 * s
        if "label_at" in m:
            lx, ly = (v * s for v in m["label_at"])
        else:
            lx, ly = (v * s for v in default_label_at(m["box"], pill_w / s, w / s))
        # Keep the pill inside the image and off the banner.
        lx = max(0, min(lx, w - pill_w))
        ly = max(0, min(ly, h - PILL_H * s))
        pill = (lx, ly, lx + pill_w, ly + PILL_H * s)
        callouts.append((n, m, tone, box, pill))
        # Leader line: from the pill edge to the nearest point of the box.
        cx, cy = (pill[0] + pill[2]) / 2, (pill[1] + pill[3]) / 2
        px, py = min(max(cx, box[0]), box[2]), min(max(cy, box[1]), box[3])
        sx = min(max(px, pill[0] + 15 * s), pill[2] - 15 * s)
        sy = min(max(py, pill[1]), pill[3])
        draw.line([(sx, sy), (px, py)], fill=tone, width=max(2, round(2.5 * s)))
    for _, _, tone, box, _ in callouts:
        draw.rounded_rectangle(box, radius=8 * s, outline=tone, width=round(3.5 * s))
    for n, m, tone, _, pill in callouts:
        bx, by = pill[0], pill[1]
        draw.rounded_rectangle(
            pill, radius=16 * s, fill=BANNER_BG, outline=tone, width=2 * s
        )
        draw.ellipse((bx + 6 * s, by + 6 * s, bx + 26 * s, by + 26 * s), fill=tone)
        draw.text(
            (bx + 16 * s, by + 16 * s), str(n), font=f_num, fill="white", anchor="mm"
        )
        draw.text(
            (bx + 33 * s, by + 16 * s),
            m["label"],
            font=f_label,
            fill="white",
            anchor="lm",
        )

    if has_banner:
        if shot.get("title"):
            draw.text(
                (20 * s, h + 12 * s),
                shot["title"],
                font=load_font("bold", 17 * s),
                fill="white",
            )
        source = shot.get("source")
        if source:
            line = SOURCE_PREFIX.get(source, source.upper())
            if shot.get("source_note"):
                line += " · " + shot["source_note"]
            draw.text(
                (20 * s, h + 37 * s),
                line,
                font=load_font("regular", 13 * s),
                fill=SOURCE_COLORS.get(source, (203, 213, 225)),
            )

    out = root / shot["out"]
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out)
    # Print the legend so the notes that go with the image use the same numbers.
    print(f"{out}  {canvas.size[0]}x{canvas.size[1]}")
    for n, m, *_ in callouts:
        print(f"  {n}. {m['label']}")


def main():
    parser = argparse.ArgumentParser(
        description="Annotate screenshots from a JSON spec (see references/spec.md)."
    )
    parser.add_argument("spec", type=Path, help="path to spec.json")
    parser.add_argument("--only", metavar="OUT_NAME", help="redraw only the shot whose out file has this name")
    args = parser.parse_args()
    spec_path = args.spec.resolve()
    spec = json.loads(spec_path.read_text())
    TONES.update({k: tuple(v) for k, v in spec.get("tones", {}).items()})
    shots = [s for s in spec["shots"] if not args.only or Path(s["out"]).name == args.only]
    if not shots:
        sys.exit(f"error: no shot has out file named {args.only!r}")
    for shot in shots:
        annotate(shot, spec_path.parent, spec.get("scale", 2))


if __name__ == "__main__":
    main()
