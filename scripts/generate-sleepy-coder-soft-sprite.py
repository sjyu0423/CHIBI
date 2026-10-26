#!/usr/bin/env python3
"""Derive the small-size "soft" Sleepy Coder variant from the approved full-body sprite.

Only neutral (low-saturation) hair pixels change: the bright gloss bands are compressed toward
the base hair tone and the lavender cel shadows are lifted slightly. Eyes, skin, blush, hoodie,
socks, shoes, ink lines, and alpha are left byte-identical. Run after
generate-sleepy-coder-full-sprite.py; requires Pillow and NumPy.
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CHARACTER = ROOT / "Sources/CHIBIApp/Resources/Characters/sleepy-coder"
SOURCE = CHARACTER / "full-body.png"
OUTPUT = CHARACTER / "full-body-soft.png"

LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float64)

# Luminance tone curve for hair pixels (piecewise linear, continuous, monotonic). Ink lines
# (below 120) and the base hair tone (215-226) are unchanged; cel shadows (~165) lift by 12 and
# gloss highlights (~244) drop by about half their contrast against the base.
CURVE_IN = np.array([0.0, 120.0, 165.0, 215.0, 226.0, 255.0])
CURVE_OUT = np.array([0.0, 120.0, 177.0, 215.0, 226.0, 240.5])

# Neutral-color weight: hair is ~0.03-0.08 saturation, skin and blush are ~0.2 and above.
SATURATION_FULL, SATURATION_NONE = 0.10, 0.18

# Hair ends above the hoodie drawstrings; shoes and socks are far below this line.
HAIR_LIMIT_Y, HAIR_FEATHER = 0.555, 0.02

# Eye boxes (x0, y0, x1, y1) in full-body.png pixels: eye whites and catchlights stay exact.
EYE_BOXES = [(200, 538, 376, 684), (528, 533, 706, 684)]
EYE_FEATHER = 10.0


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def box_distance(height, width, box):
    """Distance in pixels from each pixel to the box (0 inside)."""
    x0, y0, x1, y1 = box
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float64)
    dx = np.maximum(np.maximum(x0 - xs, xs - x1), 0.0)
    dy = np.maximum(np.maximum(y0 - ys, ys - y1), 0.0)
    return np.hypot(dx, dy)


def hair_weight(rgb, height, width):
    high, low = rgb.max(axis=-1), rgb.min(axis=-1)
    saturation = np.where(high > 0, (high - low) / np.maximum(high, 1.0), 0.0)
    weight = 1.0 - smoothstep(SATURATION_FULL, SATURATION_NONE, saturation)

    rows = (np.arange(height, dtype=np.float64) / height)[:, None]
    weight *= 1.0 - smoothstep(HAIR_LIMIT_Y - HAIR_FEATHER, HAIR_LIMIT_Y, rows)

    for box in EYE_BOXES:
        weight *= smoothstep(0.0, EYE_FEATHER, box_distance(height, width, box))
    return weight


def soften(image):
    pixels = np.asarray(image.convert("RGBA")).astype(np.float64)
    rgb, alpha = pixels[..., :3], pixels[..., 3]
    height, width = alpha.shape

    luminance = rgb @ LUMA
    shift = np.interp(luminance, CURVE_IN, CURVE_OUT) - luminance
    weight = hair_weight(rgb, height, width) * (alpha > 0)
    softened = np.clip(rgb + (weight * shift)[..., None], 0.0, 255.0)

    result = pixels.copy()
    result[..., :3] = np.where((weight > 0)[..., None], np.rint(softened), rgb)
    return Image.fromarray(result.astype(np.uint8), "RGBA"), weight


def main():
    source = Image.open(SOURCE)
    softened, weight = soften(source)
    softened.save(OUTPUT, optimize=True)

    before = np.asarray(source.convert("RGBA"))
    after = np.asarray(softened)
    changed = np.any(before != after, axis=-1)
    assert np.array_equal(before[..., 3], after[..., 3]), "alpha must not change"
    print(f"wrote {OUTPUT.relative_to(ROOT)} {softened.size[0]}x{softened.size[1]}")
    print(f"changed pixels: {int(changed.sum())} ({changed.mean():.1%}); "
          f"max channel delta {int(np.abs(before.astype(int) - after.astype(int)).max())}")
    for index, (x0, y0, x1, y1) in enumerate(EYE_BOXES):
        assert not changed[y0:y1, x0:x1].any(), f"eye box {index} changed"
    assert not changed[int(source.height * HAIR_LIMIT_Y):].any(), "pixels below the hair changed"


if __name__ == "__main__":
    main()
