#!/usr/bin/env python3
"""Extract the Sleepy Coder presentation sheet into transparent runtime layers.

The supplied artwork is a flattened JPEG board on a slowly varying blue-gray
background. This script uses a soft local-background matte rather than a hard
color-key, preserving the pale hair and antialiased outlines as well as the
source format permits.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/sleepy-coder/parts.jpeg"
OUTPUT = ROOT / "Sources/CHIBIApp/Resources/Characters/sleepy-coder"
MANIFEST = ROOT / "Sources/CHIBIApp/Resources/sleepy-coder.json"
TRANSPARENT_PREVIEW = ROOT / "assets/previews/sleepy-coder-assembly.png"
CONTRAST_PREVIEW = ROOT / "assets/previews/sleepy-coder-assembly-contrast.png"
ANIMATION_PREVIEW = ROOT / "assets/previews/sleepy-coder-animation-extremes.png"


@dataclass(frozen=True)
class Extraction:
  filename: str
  box: tuple[int, int, int, int]
  polygon: tuple[tuple[int, int], ...] | None = None
  cutout_polygon: tuple[tuple[int, int], ...] | None = None
  flood_hole_seed: tuple[int, int] | None = None
  local_background: bool = False
  minimum_component_area: int = 24


EXTRACTIONS = (
  Extraction("head.png", (245, 96, 620, 492)),
  Extraction(
    "hair-front.png",
    (805, 52, 1322, 522),
    cutout_polygon=((115, 390), (145, 360), (180, 340), (220, 330), (258, 325),
                    (300, 330), (340, 340), (375, 360), (402, 390), (417, 470),
                    (100, 470)),
    flood_hole_seed=(258, 330),
  ),
  Extraction("hair-back.png", (1488, 78, 1960, 530)),
  Extraction(
    "torso.png",
    (2145, 148, 2560, 520),
    ((78, 12), (337, 12), (361, 54), (337, 98), (310, 118), (306, 264),
     (337, 295), (325, 345), (90, 345), (78, 310), (103, 270), (105, 118),
     (75, 98), (52, 55)),
  ),
  Extraction("arm-left.png", (721, 672, 947, 1028)),
  Extraction("arm-right.png", (1214, 672, 1438, 1028)),
  Extraction(
    "leg-left.png",
    (306, 1178, 520, 1462),
    ((75, 5), (145, 8), (180, 38), (177, 82), (152, 132), (146, 193),
     (150, 205), (135, 215), (112, 225), (88, 236), (45, 236), (12, 230),
     (2, 222), (12, 211), (66, 194), (72, 151), (58, 108), (59, 55)),
  ),
  Extraction(
    "leg-right.png",
    (929, 1178, 1199, 1462),
    ((80, 7), (153, 5), (190, 39), (194, 85), (182, 126), (195, 193),
     (226, 205), (247, 220), (248, 230), (230, 236), (185, 238), (160, 230),
     (145, 218), (125, 205), (100, 196), (90, 151), (66, 105), (57, 50)),
  ),
  Extraction("eye-left-open.png", (1540, 1050, 1712, 1194)),
  Extraction("eye-right-open.png", (1742, 1050, 1924, 1194)),
  Extraction("eye-left-closed.png", (1540, 1320, 1715, 1445)),
  Extraction("eye-right-closed.png", (1740, 1320, 1928, 1445)),
  Extraction("mouth-neutral.png", (2233, 1240, 2340, 1313), local_background=True),
  Extraction("mouth-happy.png", (2226, 1330, 2342, 1420), local_background=True),
  Extraction("mouth-surprised.png", (2398, 1225, 2497, 1325), local_background=True),
  Extraction("mouth-pout.png", (2390, 1330, 2505, 1428), local_background=True),
)


LAYER_LAYOUTS = (
  ("shadow", None, (0, -327), (0.5, 0.5), -10, 1.0, None),
  ("hairBack", "hair-back.png", (0, 129), (0.5, 0.5), 0, 0.88, (0.5, 0.5)),
  ("leftLeg", "leg-left.png", (-58, -202), (0.5, 0.82), 10, 0.64, (0.5, 0.82)),
  ("rightLeg", "leg-right.png", (58, -202), (0.5, 0.82), 11, 0.64, (0.5, 0.82)),
  ("leftArm", "arm-left.png", (-108, -24), (0.5, 0.84), 15, 0.56, (0.5, 0.84)),
  ("rightArm", "arm-right.png", (108, -24), (0.5, 0.84), 16, 0.56, (0.5, 0.84)),
  ("torso", "torso.png", (0, -85), (0.5, 0.5), 20, 0.72, (0.5, 0.7)),
  ("head", "head.png", (0, 115), (0.5, 0.5), 40, 0.9, (0.5, 0.5)),
  ("face", "face.png", (0, 115), (0.5, 0.5), 50, 1.0, None),
  ("leftEye", "eye-left-open.png", (-75, 138), (0.5, 0.5), 60, 0.92, None),
  ("rightEye", "eye-right-open.png", (75, 138), (0.5, 0.5), 61, 0.74, None),
  ("mouth", "mouth-neutral.png", (0, 56), (0.5, 0.5), 70, 0.58, None),
  ("hairFront", "hair-front.png", (-8, 150), (0.5, 0.5), 80, 0.88, (0.5, 0.5)),
)


def smoothstep(value: np.ndarray) -> np.ndarray:
  value = np.clip(value, 0.0, 1.0)
  return value * value * (3.0 - 2.0 * value)


def fit_background(sheet: Image.Image) -> np.ndarray:
  rgb = np.asarray(sheet.convert("RGB"), dtype=np.float32)
  height, width, _ = rgb.shape
  sample = rgb[::6, ::6]
  yy, xx = np.mgrid[0:height:6, 0:width:6]
  red, green, blue = sample[..., 0], sample[..., 1], sample[..., 2]
  candidate = (
    (red > 145) & (red < 220) & (green > 155) & (green < 228)
    & (blue > 175) & (blue < 240) & (green - red > 2) & (green - red < 22)
    & (blue - green > 5) & (blue - green < 28)
  )
  x = xx[candidate].astype(np.float64) / width
  y = yy[candidate].astype(np.float64) / height
  values = sample[candidate].astype(np.float64)
  basis = np.column_stack((np.ones_like(x), x, y, x * x, y * y, x * y))
  keep = np.ones(len(x), dtype=bool)
  coefficients = None
  for _ in range(4):
    coefficients = np.linalg.lstsq(basis[keep], values[keep], rcond=None)[0]
    residual = np.sqrt(np.sum((basis @ coefficients - values) ** 2, axis=1))
    keep = residual < np.percentile(residual, 72)

  full_y, full_x = np.mgrid[0:height, 0:width]
  full_x = full_x.astype(np.float64) / width
  full_y = full_y.astype(np.float64) / height
  full_basis = np.stack(
    (
      np.ones_like(full_x), full_x, full_y, full_x * full_x, full_y * full_y,
      full_x * full_y,
    ),
    axis=-1,
  )
  return np.clip(full_basis @ coefficients, 0, 255).astype(np.float32)


def fit_local_background(rgb: np.ndarray) -> np.ndarray:
  height, width, _ = rgb.shape
  patch = max(5, min(height, width) // 10)
  corners = np.array(
    [
      np.median(rgb[:patch, :patch], axis=(0, 1)),
      np.median(rgb[:patch, -patch:], axis=(0, 1)),
      np.median(rgb[-patch:, :patch], axis=(0, 1)),
      np.median(rgb[-patch:, -patch:], axis=(0, 1)),
    ],
    dtype=np.float32,
  )
  x = np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :, None]
  y = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None, None]
  top = corners[0] * (1.0 - x) + corners[1] * x
  bottom = corners[2] * (1.0 - x) + corners[3] * x
  return top * (1.0 - y) + bottom * y


def antialiased_polygon(size: tuple[int, int], points: tuple[tuple[int, int], ...]) -> np.ndarray:
  scale = 4
  mask = Image.new("L", (size[0] * scale, size[1] * scale), 0)
  scaled_points = [(x * scale, y * scale) for x, y in points]
  ImageDraw.Draw(mask).polygon(scaled_points, fill=255)
  mask = mask.resize(size, Image.Resampling.LANCZOS)
  return np.asarray(mask, dtype=np.float32) / 255.0


def remove_flooded_guide(
  crop: Image.Image, rgb: np.ndarray, alpha: np.ndarray, seed: tuple[int, int]
) -> None:
  marked = crop.copy()
  ImageDraw.floodfill(marked, seed, value=(255, 0, 255), thresh=32)
  core = np.all(np.asarray(marked) == np.array((255, 0, 255)), axis=2)
  yy, xx = np.nonzero(core)
  basis = np.column_stack((np.ones(len(xx)), xx, yy))
  coefficients = np.linalg.lstsq(basis, rgb[core], rcond=None)[0]
  full_y, full_x = np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]]
  guide = np.stack((np.ones_like(full_x), full_x, full_y), axis=-1) @ coefficients
  difference = np.sqrt(np.sum((rgb - guide) ** 2, axis=2))
  expanded = Image.fromarray((core * 255).astype(np.uint8), mode="L").filter(
    ImageFilter.MaxFilter(11)
  )
  neighborhood = np.asarray(expanded, dtype=np.float32) / 255.0
  keep = smoothstep((difference - 3.0) / 17.0)
  alpha *= 1.0 - neighborhood * (1.0 - keep)


def remove_small_components(alpha: np.ndarray, minimum_area: int) -> None:
  visible = alpha > 0.08
  height, width = visible.shape
  visited = np.zeros_like(visible)
  for start_y, start_x in zip(*np.nonzero(visible & ~visited)):
    if visited[start_y, start_x]:
      continue
    stack = [(start_y, start_x)]
    visited[start_y, start_x] = True
    component = []
    while stack:
      y, x = stack.pop()
      component.append((y, x))
      for neighbor_y in range(max(0, y - 1), min(height, y + 2)):
        for neighbor_x in range(max(0, x - 1), min(width, x + 2)):
          if visible[neighbor_y, neighbor_x] and not visited[neighbor_y, neighbor_x]:
            visited[neighbor_y, neighbor_x] = True
            stack.append((neighbor_y, neighbor_x))
    if len(component) < minimum_area:
      ys, xs = zip(*component)
      alpha[np.array(ys), np.array(xs)] = 0.0


def extract_layer(
  sheet: Image.Image, background_sheet: np.ndarray, extraction: Extraction
) -> Image.Image:
  crop = sheet.crop(extraction.box).convert("RGB")
  rgb = np.asarray(crop, dtype=np.float32)
  left, top, right, bottom = extraction.box
  background = (
    fit_local_background(rgb)
    if extraction.local_background
    else background_sheet[top:bottom, left:right]
  )
  difference = np.sqrt(np.sum((rgb - background) ** 2, axis=2))
  alpha = smoothstep((difference - 5.0) / 10.0)

  if extraction.polygon:
    alpha *= antialiased_polygon(crop.size, extraction.polygon)

  if extraction.cutout_polygon:
    alpha *= 1.0 - antialiased_polygon(crop.size, extraction.cutout_polygon)

  if extraction.flood_hole_seed:
    remove_flooded_guide(crop, rgb, alpha, extraction.flood_hole_seed)

  alpha[alpha < 0.08] = 0.0
  remove_small_components(alpha, extraction.minimum_component_area)
  rgba = np.dstack((rgb.astype(np.uint8), np.rint(alpha * 255).astype(np.uint8)))
  image = Image.fromarray(rgba, mode="RGBA")
  bounds = image.getchannel("A").getbbox()
  if bounds is None:
    raise RuntimeError(f"Extraction produced no visible pixels: {extraction.filename}")
  left, top, right, bottom = bounds
  padding = 3
  bounds = (
    max(0, left - padding),
    max(0, top - padding),
    min(image.width, right + padding),
    min(image.height, bottom + padding),
  )
  return image.crop(bounds)


def write_manifest() -> None:
  prefix = "Characters/sleepy-coder/"
  assets = {
    "fullBody": prefix + "full-body.png",
    "hairBack": prefix + "hair-back.png",
    "leftLeg": prefix + "leg-left.png",
    "rightLeg": prefix + "leg-right.png",
    "torso": prefix + "torso.png",
    "leftArm": prefix + "arm-left.png",
    "rightArm": prefix + "arm-right.png",
    "head": prefix + "head.png",
    "face": prefix + "face.png",
    "leftEye": prefix + "eye-left-open.png",
    "rightEye": prefix + "eye-right-open.png",
    "leftEyeClosed": prefix + "eye-left-closed.png",
    "rightEyeClosed": prefix + "eye-right-closed.png",
    "mouth": prefix + "mouth-neutral.png",
    "mouthHappy": prefix + "mouth-happy.png",
    "mouthSleep": prefix + "mouth-surprised.png",
    "hairFront": prefix + "hair-front.png",
  }
  layers = []
  for layer, asset, position, anchor, order, scale, animation_anchor in LAYER_LAYOUTS:
    entry = {
      "layer": layer,
      "position": {"x": position[0], "y": position[1]},
      "anchorPoint": {"x": anchor[0], "y": anchor[1]},
      "drawOrder": order,
      "scale": scale,
    }
    if animation_anchor:
      entry["animationAnchorPoint"] = {
        "x": animation_anchor[0],
        "y": animation_anchor[1],
      }
    layers.append(entry)
  manifest = {
    "identifier": "dev.chibi.sleepy-coder",
    "displayName": "Sleepy Coder",
    "renderDimensions": {"width": 640, "height": 760},
    "renderingMode": "fullBody",
    "assets": assets,
    "fullBodyLayout": {
      "position": {"x": 0, "y": -8},
      "anchorPoint": {"x": 0.5, "y": 0.5},
      "scale": 0.41,
    },
    "layers": layers,
    "animations": {
      "idleBobHeight": 7.0,
      "idleCycleDuration": 2.6,
      "blinkMinimumDelay": 2.1,
      "blinkDelayVariation": 2.8,
      "happyHopHeight": 38.0,
      "walkStepDuration": 0.3,
      "danceBeatDuration": 0.44,
      "sleepSwayDuration": 3.0,
    },
  }
  MANIFEST.parent.mkdir(parents=True, exist_ok=True)
  MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def compose_assembly(
  asset_overrides: dict[str, str] | None = None,
  position_offsets: dict[str, tuple[int, int]] | None = None,
) -> Image.Image:
  width, height = 640, 760
  assembly = Image.new("RGBA", (width, height), (0, 0, 0, 0))
  asset_overrides = asset_overrides or {}
  position_offsets = position_offsets or {}

  for layer_name, asset, position, anchor, _, scale, animation_anchor in sorted(
    LAYER_LAYOUTS, key=lambda item: item[4]
  ):
    if asset is None or asset == "face.png":
      continue
    asset = asset_overrides.get(layer_name, asset)
    offset = position_offsets.get(layer_name, (0, 0))
    layer = Image.open(OUTPUT / asset).convert("RGBA")
    layer = layer.resize(
      (max(1, round(layer.width * scale)), max(1, round(layer.height * scale))),
      Image.Resampling.LANCZOS,
    )
    pivot = animation_anchor or anchor
    center_x = width / 2 + position[0] + offset[0]
    center_y = height / 2 - position[1] - offset[1]
    left = round(center_x - pivot[0] * layer.width)
    top = round(center_y - (1.0 - pivot[1]) * layer.height)
    assembly.alpha_composite(layer, (left, top))
  return assembly


def render_preview() -> None:
  assembly = compose_assembly()

  TRANSPARENT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
  assembly.save(TRANSPARENT_PREVIEW, optimize=True)
  contrast = Image.new("RGBA", assembly.size, (74, 38, 91, 255))
  contrast.alpha_composite(assembly)
  contrast.convert("RGB").save(CONTRAST_PREVIEW, quality=95)


def render_animation_preview() -> None:
  states = (
    ("Idle", {}, {}),
    ("Happy", {"mouth": "mouth-happy.png"},
     {"leftArm": (-5, 8), "rightArm": (5, 8)}),
    ("Sleep", {"leftEye": "eye-left-closed.png", "rightEye": "eye-right-closed.png",
               "mouth": "mouth-surprised.png"}, {"head": (0, -2)}),
    ("Walk", {}, {"leftLeg": (0, 5), "leftArm": (-3, 0), "rightArm": (3, 0),
                  "torso": (0, 2)}),
    ("Dance", {}, {"leftArm": (-5, 12), "rightArm": (5, 12),
                   "hairFront": (0, 3)}),
  )
  cell_width, cell_height = 320, 410
  sheet = Image.new("RGB", (cell_width * len(states), cell_height), (74, 38, 91))
  draw = ImageDraw.Draw(sheet)
  for index, (label, overrides, offsets) in enumerate(states):
    pose = compose_assembly(overrides, offsets).resize((320, 380), Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", pose.size, (74, 38, 91, 255))
    cell.alpha_composite(pose)
    sheet.paste(cell.convert("RGB"), (index * cell_width, 0))
    draw.text((index * cell_width + 12, 386), label, fill=(255, 255, 255))
  sheet.save(ANIMATION_PREVIEW, quality=95)


def main() -> None:
  if not SOURCE.exists():
    raise SystemExit(f"Missing source sheet: {SOURCE}")
  OUTPUT.mkdir(parents=True, exist_ok=True)
  sheet = Image.open(SOURCE).convert("RGB")
  background = fit_background(sheet)
  for extraction in EXTRACTIONS:
    extract_layer(sheet, background, extraction).save(OUTPUT / extraction.filename, optimize=True)
  Image.new("RGBA", (1, 1), (0, 0, 0, 0)).save(OUTPUT / "face.png")
  write_manifest()
  render_preview()
  render_animation_preview()
  print(f"Generated {len(EXTRACTIONS) + 1} transparent layers in {OUTPUT}")
  print(f"Wrote manifest: {MANIFEST}")
  print(f"Wrote transparent assembly preview: {TRANSPARENT_PREVIEW}")
  print(f"Wrote contrast assembly preview: {CONTRAST_PREVIEW}")
  print(f"Wrote animation-extremes preview: {ANIMATION_PREVIEW}")


if __name__ == "__main__":
  main()
