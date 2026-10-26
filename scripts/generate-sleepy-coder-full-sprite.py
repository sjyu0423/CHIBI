#!/usr/bin/env python3
"""Clean the approved front-facing Sleepy Coder into one transparent sprite.

This intentionally does not reconstruct or redraw the character. The source is
base_character_transparent.png, a single-figure RGBA export. Its silhouette is
kept exactly; cleanup is limited to the matte:

- Only the connected character silhouette is retained, so stray residue below
  the shoes or along the canvas edge (ground line, shadow, specks) is cleared.
- The faint low-alpha halo outside the ink outline is dropped and the nearly
  opaque (alpha 253/254) interior becomes fully opaque.
- Partially transparent contour pixels take their color from the adjacent
  opaque artwork so no pale matte fringe shows on dark desktops. Fully opaque
  pixels remain byte-for-byte source RGB.
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/sleepy-coder/base_character_transparent.png"
OUTPUT = ROOT / "Sources/CHIBIApp/Resources/Characters/sleepy-coder/full-body.png"
TRANSPARENT_PREVIEW = ROOT / "assets/previews/sleepy-coder-full-body.png"
DARK_PREVIEW = ROOT / "assets/previews/sleepy-coder-full-body-dark.png"
COMPARISON_PREVIEW = ROOT / "assets/previews/sleepy-coder-full-body-comparison.png"

# Source alpha at or below HALO_ALPHA is matte residue; at or above SOLID_ALPHA
# it is artwork interior. Values between are remapped linearly as contour AA.
HALO_ALPHA = 16
SOLID_ALPHA = 240
# Pixels at or above this source alpha seed the single character silhouette.
SILHOUETTE_ALPHA = 24
PADDING = 4
DARK_BACKGROUND = (24, 24, 28)


def largest_component(mask: np.ndarray) -> np.ndarray:
  height, width = mask.shape
  labels = np.zeros(mask.shape, dtype=np.int32)
  best_label, best_size, label = 0, 0, 0
  for start_y, start_x in zip(*np.nonzero(mask)):
    if labels[start_y, start_x]:
      continue
    label += 1
    labels[start_y, start_x] = label
    queue, size = deque([(start_y, start_x)]), 0
    while queue:
      y, x = queue.popleft()
      size += 1
      for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
        if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
          labels[ny, nx] = label
          queue.append((ny, nx))
    if size > best_size:
      best_label, best_size = label, size
  return labels == best_label


def dilate(mask: np.ndarray, size: int) -> np.ndarray:
  image = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
  return np.asarray(image.filter(ImageFilter.MaxFilter(size))) > 0


def bleed_opaque_color(rgb: np.ndarray, known: np.ndarray, targets: np.ndarray) -> np.ndarray:
  """Fill target pixels with the average color of the nearest known pixels."""
  result = rgb.copy()
  known = known.copy()
  remaining = targets & ~known
  while remaining.any():
    weights = known.astype(np.float32)
    padded_rgb = np.pad(result * weights[..., None], ((1, 1), (1, 1), (0, 0)))
    padded_weights = np.pad(weights, 1)
    total = np.zeros_like(result)
    count = np.zeros(weights.shape, dtype=np.float32)
    for dy in (0, 1, 2):
      for dx in (0, 1, 2):
        total += padded_rgb[dy:dy + rgb.shape[0], dx:dx + rgb.shape[1]]
        count += padded_weights[dy:dy + rgb.shape[0], dx:dx + rgb.shape[1]]
    frontier = remaining & (count > 0)
    if not frontier.any():
      break
    result[frontier] = total[frontier] / count[frontier, None]
    known |= frontier
    remaining &= ~frontier
  return result


def clean_sprite(source: Image.Image) -> Image.Image:
  rgba = np.asarray(source, dtype=np.float32)
  rgb, source_alpha = rgba[..., :3], rgba[..., 3]

  silhouette = largest_component(source_alpha >= SILHOUETTE_ALPHA)
  silhouette = dilate(silhouette, 5)

  alpha = np.clip((source_alpha - HALO_ALPHA) / (SOLID_ALPHA - HALO_ALPHA), 0.0, 1.0)
  alpha[~silhouette] = 0.0

  opaque = alpha >= 1.0
  contour = (alpha > 0.0) & ~opaque
  recovered = bleed_opaque_color(rgb, opaque, contour)
  recovered[alpha == 0.0] = 0.0

  cleaned = np.dstack(
    (np.rint(recovered).astype(np.uint8), np.rint(alpha * 255).astype(np.uint8))
  )
  sprite = Image.fromarray(cleaned, mode="RGBA")
  bounds = sprite.getchannel("A").getbbox()
  if bounds is None:
    raise RuntimeError("Full-body cleanup produced no visible pixels")
  left, top, right, bottom = bounds
  padded = Image.new(
    "RGBA", (right - left + PADDING * 2, bottom - top + PADDING * 2), (0, 0, 0, 0)
  )
  padded.paste(sprite.crop(bounds), (PADDING, PADDING))
  return padded


def on_background(image: Image.Image, color: tuple[int, int, int]) -> Image.Image:
  canvas = Image.new("RGBA", image.size, color + (255,))
  canvas.alpha_composite(image)
  return canvas.convert("RGB")


def render_previews(sprite: Image.Image, source: Image.Image) -> None:
  TRANSPARENT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
  sprite.save(TRANSPARENT_PREVIEW, optimize=True)

  margin = 36
  dark = Image.new(
    "RGBA", (sprite.width + margin * 2, sprite.height + margin * 2), DARK_BACKGROUND + (255,)
  )
  dark.alpha_composite(sprite, (margin, margin))
  dark.convert("RGB").save(DARK_PREVIEW, optimize=True)

  target_height = 900
  views = [on_background(image, DARK_BACKGROUND) for image in (source, sprite)]
  views = [
    view.resize(
      (round(view.width * target_height / view.height), target_height),
      Image.Resampling.LANCZOS,
    )
    for view in views
  ]
  gap = 36
  comparison = Image.new(
    "RGB",
    (sum(view.width for view in views) + gap * 3, target_height + gap * 2),
    (68, 35, 88),
  )
  comparison.paste(views[0], (gap, gap))
  comparison.paste(views[1], (views[0].width + gap * 2, gap))
  comparison.save(COMPARISON_PREVIEW, optimize=True)


def main() -> None:
  if not SOURCE.exists():
    raise SystemExit(f"Missing approved source image: {SOURCE}")
  source = Image.open(SOURCE)
  if source.mode != "RGBA":
    raise SystemExit(f"Expected an RGBA source, found {source.mode}: {SOURCE}")
  sprite = clean_sprite(source)
  OUTPUT.parent.mkdir(parents=True, exist_ok=True)
  sprite.save(OUTPUT, optimize=True)
  render_previews(sprite, source)
  print(f"Wrote full-body sprite: {OUTPUT} ({sprite.width}x{sprite.height})")
  print(f"Wrote transparent preview: {TRANSPARENT_PREVIEW}")
  print(f"Wrote dark preview: {DARK_PREVIEW}")
  print(f"Wrote source comparison: {COMPARISON_PREVIEW}")


if __name__ == "__main__":
  main()
