#!/usr/bin/env python3
"""Assemble rendered animation frames into reviewable GIFs, filmstrips, and warp comparisons.

Input is the work directory written by AnimationPreviewRenderer.swift. Every clip is also
checked for pixels touching the overlay edge, which would indicate clipping.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

LIGHT = (236, 232, 224)
DARK = (28, 28, 34)
FRAME_MS = 1000 / 24
GIF_FRAME_STEP = 2
FILMSTRIP_FRAMES = 8


def composite(frame: Image.Image, color: tuple[int, int, int]) -> Image.Image:
  canvas = Image.new("RGBA", frame.size, color + (255,))
  canvas.alpha_composite(frame)
  return canvas.convert("RGB")


def assemble_clip(directory: Path, output: Path) -> dict:
  paths = sorted(directory.glob("*.png"))
  frames = [Image.open(path).convert("RGBA") for path in paths]
  alphas = np.stack([np.asarray(frame)[..., 3] for frame in frames])
  visible = alphas.max(axis=0) > 0
  ys, xs = np.nonzero(visible)
  edge = alphas[:, 0, :].max(), alphas[:, -1, :].max(), alphas[:, :, 0].max(), alphas[:, :, -1].max()
  stats = {
    "frames": len(frames),
    "size": list(frames[0].size),
    "envelope": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
    "edgeAlphaMax": int(max(edge)),
    "clipped": bool(max(edge) > 0),
  }

  # Review copies at the real 1x Medium overlay size; frames are rendered at 2x.
  light = [
    composite(frame, LIGHT).resize(
      (frame.width // 2, frame.height // 2), Image.Resampling.LANCZOS)
    for frame in frames
  ]
  gif = light[::GIF_FRAME_STEP]
  gif[0].save(
    output / f"{directory.name}.gif", save_all=True, append_images=gif[1:],
    duration=FRAME_MS * GIF_FRAME_STEP, loop=0, optimize=True)

  picks = np.linspace(0, len(frames) - 1, FILMSTRIP_FRAMES).round().astype(int)
  width, height = light[0].size
  strip = Image.new("RGB", (width * len(picks), height + 22), (250, 250, 250))
  draw = ImageDraw.Draw(strip)
  for slot, index in enumerate(picks):
    strip.paste(light[index], (slot * width, 22))
    draw.rectangle(
      [slot * width, 22, (slot + 1) * width - 1, height + 21], outline=(210, 120, 120))
    draw.text((slot * width + 6, 5), f"t={index * FRAME_MS / 1000:.2f}s", fill=(0, 0, 0))
  strip.save(output / f"{directory.name}-filmstrip.png", optimize=True)
  timeline = directory / "timeline.txt"
  if timeline.exists():
    (output / f"{directory.name}-timeline.txt").write_text(timeline.read_text())
  return stats


def assemble_stills(directory: Path, output: Path) -> None:
  names = ["rest", "tilt-left", "tilt-right", "hair-left", "hair-right"]
  images = {name: composite(Image.open(directory / f"{name}.png").convert("RGBA"), LIGHT)
    for name in names}
  width, height = images["rest"].size

  half = [images[name].resize((width // 2, height // 2), Image.Resampling.LANCZOS)
    for name in names]
  sheet = Image.new("RGB", (sum(image.width for image in half), half[0].height + 24), LIGHT)
  draw = ImageDraw.Draw(sheet)
  x = 0
  for name, image in zip(names, half):
    sheet.paste(image, (x, 24))
    draw.text((x + 8, 6), name, fill=(0, 0, 0))
    x += image.width
  sheet.save(output / "warp-extremes.png", optimize=True)

  # Neck/hood blend band and hair-tip band at full resolution: where seams would appear.
  regions = {
    "neck": (int(width * 0.22), int(height * 0.40), int(width * 0.78), int(height * 0.62)),
    "hair-tips": (0, int(height * 0.36), int(width * 0.30), int(height * 0.66)),
  }
  for region, box in regions.items():
    crops = [images[name].crop(box) for name in names]
    sheet = Image.new("RGB", (sum(crop.width for crop in crops), crops[0].height + 24), LIGHT)
    draw = ImageDraw.Draw(sheet)
    x = 0
    for name, crop in zip(names, crops):
      sheet.paste(crop, (x, 24))
      draw.text((x + 8, 6), name, fill=(0, 0, 0))
      x += crop.width
    sheet.save(output / f"warp-{region}.png", optimize=True)


def main() -> None:
  work, output = Path(sys.argv[1]), Path(sys.argv[2])
  output.mkdir(parents=True, exist_ok=True)
  summary = {}
  for clip in sorted((work / "clips").iterdir()):
    summary[clip.name] = assemble_clip(clip, output)
    print(clip.name, summary[clip.name])
  assemble_stills(work / "stills", output)
  (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
  main()
