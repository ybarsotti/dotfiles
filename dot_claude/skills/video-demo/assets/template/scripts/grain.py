from pathlib import Path
import numpy as np
from PIL import Image
OUT = Path(__file__).resolve().parent.parent / "public" / "grain"
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(1080)
for index in range(8):
    noise = rng.normal(128, 38, (512, 512)).clip(0, 255).astype(np.uint8)
    rgba = np.dstack([noise, noise, noise, np.full((512, 512), 255, np.uint8)])
    Image.fromarray(rgba, "RGBA").save(OUT / f"g{index}.png")
print("8 grain tiles")
