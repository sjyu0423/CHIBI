#!/usr/bin/env python3
"""Evaluate blinking with the registered closed-eye overlays on the approved full-body sprite.

The overlays come from the separate facial-assets/parts sheets. Hiding the sprite's open eyes
requires an eyelid patch, so this composites what a runtime blink would display: a skin-colored
lid over each eye plus the scaled closed-eye overlay. The result is compared with the approved
art at 1:1 and at the on-screen Medium scale. This is a review aid only; nothing here ships.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CHARACTERS = ROOT / "Sources/CHIBIApp/Resources/Characters/sleepy-coder"
OUTPUT = ROOT / "assets/previews/experiments/blink-overlay-experiment.png"

# Eye boxes in full-body.png pixels (white, iris, and upper lash line), measured from the iris.
EYES = {
  "left": ((210, 548, 366, 674), "eye-left-closed.png"),
  "right": ((538, 543, 696, 674), "eye-right-closed.png"),
}
SKIN_SAMPLE = (470, 615)
ON_SCREEN_SCALE = 0.41 * 210 / 640
BACKGROUND = (236, 232, 224, 255)


def blink_composite(sprite: Image.Image) -> Image.Image:
  result = sprite.copy()
  skin = sprite.getpixel(SKIN_SAMPLE)
  for box, overlay_name in EYES.values():
    left, top, right, bottom = box
    lid = Image.new("L", sprite.size, 0)
    ImageDraw.Draw(lid).ellipse(box, fill=255)
    lid = lid.filter(ImageFilter.GaussianBlur(2))
    patch = Image.new("RGBA", sprite.size, skin[:3] + (255,))
    result = Image.composite(patch, result, lid)

    overlay = Image.open(CHARACTERS / overlay_name).convert("RGBA")
    width = right - left
    overlay = overlay.resize(
      (width, round(overlay.height * width / overlay.width)), Image.Resampling.LANCZOS)
    result.alpha_composite(
      overlay, (left, top + round((bottom - top) * 0.62) - overlay.height // 2))
  return result


def on_background(image: Image.Image) -> Image.Image:
  canvas = Image.new("RGBA", image.size, BACKGROUND)
  canvas.alpha_composite(image)
  return canvas.convert("RGB")


def main() -> None:
  sprite = Image.open(CHARACTERS / "full-body.png").convert("RGBA")
  blink = blink_composite(sprite)
  face = (150, 420, 810, 860)
  closeups = [on_background(image).crop(face) for image in (sprite, blink)]
  small = [
    on_background(image).resize(
      (round(image.width * ON_SCREEN_SCALE * 2), round(image.height * ON_SCREEN_SCALE * 2)),
      Image.Resampling.LANCZOS)
    for image in (sprite, blink)
  ]
  gap = 24
  width = closeups[0].width * 2 + small[0].width * 2 + gap * 5
  height = max(closeups[0].height, small[0].height) + gap * 2 + 20
  sheet = Image.new("RGB", (width, height), (250, 250, 250))
  draw = ImageDraw.Draw(sheet)
  x = gap
  labels = ["approved (1:1)", "overlay blink (1:1)", "approved (Medium @2x)", "overlay blink"]
  for label, image in zip(labels, closeups + small):
    sheet.paste(image, (x, gap + 20))
    draw.text((x, gap), label, fill=(0, 0, 0))
    x += image.width + gap
  OUTPUT.parent.mkdir(parents=True, exist_ok=True)
  sheet.save(OUTPUT, optimize=True)
  print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
  main()
