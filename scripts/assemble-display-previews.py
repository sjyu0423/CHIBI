#!/usr/bin/env python3
"""Assemble display-size comparison sheets from scripts/render-display-previews.sh output.

Every sheet shows pixels 1:1 (head crops are nearest-neighbor enlargements), so the 2x sheets
are what a Retina display shows at actual size when viewed at 50%.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SIZES = ["small", "medium", "large"]
LIGHT, DARK = (236, 232, 224), (30, 30, 34)
LABEL_HEIGHT, GAP = 18, 8


def composite(image, background):
    base = Image.new("RGBA", image.size, background + (255,))
    base.alpha_composite(image)
    return base.convert("RGB")


def detail_energy(image):
    """Mean absolute Laplacian on a light background: higher means busier, noisier pixels."""
    gray = np.asarray(composite(image, LIGHT).convert("L"), dtype=np.float64)
    lap = (4 * gray[1:-1, 1:-1] - gray[:-2, 1:-1] - gray[2:, 1:-1] - gray[1:-1, :-2]
           - gray[1:-1, 2:])
    return float(np.abs(lap).mean())


def head_crop(image):
    w, h = image.size
    return image.crop((int(w * 0.2), int(h * 0.1), int(w * 0.8), int(h * 0.5)))


def grid(rows, labels, path):
    """rows: list of (row label, [images]); images in a column share one option label."""
    columns = len(labels)
    cell_w = max(img.width for _, images in rows for img in images)
    width = 90 + columns * (cell_w + GAP)
    height = LABEL_HEIGHT + sum(max(img.height for img in images) + GAP for _, images in rows)
    sheet = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(sheet)
    for column, label in enumerate(labels):
        draw.text((90 + column * (cell_w + GAP) + 2, 3), label, fill="black")
    y = LABEL_HEIGHT
    for row_label, images in rows:
        draw.text((4, y + 4), row_label, fill="black")
        for column, img in enumerate(images):
            sheet.paste(img, (90 + column * (cell_w + GAP), y))
        y += max(img.height for img in images) + GAP
    sheet.save(path, optimize=True)


def main():
    stills, output = Path(sys.argv[1]), Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    options = sorted({p.stem.split("-", 1)[1] for p in stills.glob("*.png")},
                     key=lambda name: (name != "original-direct", name != "original-resampled", name))
    summary = {"options": options, "stills": {}}

    for scale in ("1x", "2x"):
        rows, zoom_rows = [], []
        zoom = 3 if scale == "1x" else 2
        for size in SIZES:
            images = [Image.open(stills / f"{size}@{scale}-{option}.png").convert("RGBA")
                      for option in options]
            for option, image in zip(options, images):
                alpha = np.asarray(image)[..., 3]
                edge = max(alpha[0].max(), alpha[-1].max(), alpha[:, 0].max(), alpha[:, -1].max())
                ys, xs = np.nonzero(alpha > 8)
                summary["stills"][f"{size}@{scale}-{option}"] = {
                    "size": list(image.size),
                    "bounds": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                    "edgeAlphaMax": int(edge),
                    "clipped": bool(edge > 8),
                    "detailEnergy": round(detail_energy(image), 2),
                }
            rows.append((f"{size} light", [composite(i, LIGHT) for i in images]))
            rows.append((f"{size} dark", [composite(i, DARK) for i in images]))
            crops = [composite(head_crop(i), LIGHT) for i in images]
            zoom_rows.append((f"{size} head x{zoom}", [
                c.resize((c.width * zoom, c.height * zoom), Image.NEAREST) for c in crops]))
        grid(rows, options, output / f"display-{scale}.png")
        grid(zoom_rows, options, output / f"head-zoom-{scale}.png")

    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    for name, info in summary["stills"].items():
        print(f"{name:32s} energy {info['detailEnergy']:6.2f} edge {info['edgeAlphaMax']:3d} "
              f"bounds {info['bounds']}")


if __name__ == "__main__":
    main()
