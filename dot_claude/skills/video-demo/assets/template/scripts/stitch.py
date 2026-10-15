import json
import sys
from pathlib import Path

from PIL import Image

WIDTH, HEIGHT = 2880, 1800


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit("usage: stitch.py <tiles dir> <scenes.json> <output dir>")
    tiles, scenes, output = Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text()), Path(sys.argv[3])
    output.mkdir(parents=True, exist_ok=True)
    left, top = WIDTH // 2, HEIGHT // 2
    boxes = [(0, 0, left, top), (left, 0, WIDTH - left, top), (0, top, left, HEIGHT - top), (left, top, WIDTH - left, HEIGHT - top)]
    for name, files in scenes.items():
        if len(files) != 4:
            sys.exit(f"{name}: expected 4 tiles (top left, top right, bottom left, bottom right)")
        canvas = Image.new("RGB", (WIDTH, HEIGHT))
        for file, (x, y, width, height) in zip(files, boxes):
            canvas.paste(Image.open(tiles / file).convert("RGB").resize((width, height), Image.LANCZOS), (x, y))
        canvas.save(output / f"{name}.png", optimize=True)
        print(f"{name}: {', '.join(files)}")


main()
