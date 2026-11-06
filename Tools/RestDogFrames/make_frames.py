#!/usr/bin/env python3
"""Turns the extracted resting-dog frames into menu-bar artwork.

The source video has a grey/white checkerboard baked in where an editor would
show transparency. A plain colour key cannot work here: the dog's body is the
same white as the light squares, so keying the backdrop also erases the dog.

Instead the black ink outline is used as a *topological* boundary: everything
enclosed by the outline is the dog, everything connected to the image border
is backdrop. Coloured details (pink ears and paws) are added to the ink so
they help close the boundary, and a small dilation seals the hairline gaps in
the hand-drawn outline before the holes are filled.

Run with:
  python3 Tools/RestDogFrames/make_frames.py <raw-dir> <resources-dir> [fps]

Requires numpy, scipy and Pillow.
"""

import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

# The artwork is 4x the logical 29x22 point canvas the dog occupies in the
# menu bar. The resting pose is square, so it is centred with transparent
# padding on the left and right.
CANVAS_W, CANVAS_H = 116, 88
DOG_BOX = 86
FPS = 20
LOOP_SECONDS = 6.0


def mask_for(rgb):
    """Returns (alpha mask, rgb) with the checkerboard removed."""
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    saturation = rgb.max(axis=2) - rgb.min(axis=2)

    # Dark ink and coloured details. The darkest checkerboard square is about
    # 201 in luminance, so a 165 cut-off picks up only the drawing.
    ink = (lum < 165) | (saturation > 28)
    ink = ndimage.binary_dilation(ink, iterations=2)
    filled = ndimage.binary_fill_holes(ink)

    # Keep the dog-sized component. Anything else is a stray speck from the
    # video compression.
    labels, count = ndimage.label(filled)
    sizes = np.bincount(labels.ravel())
    keep = [i for i in range(1, count + 1) if sizes[i] > 5000]
    if not keep:
        return filled, rgb
    silhouette = np.isin(labels, keep)
    return silhouette, rgb


def main():
    raw_dir = sys.argv[1]
    out_dir = sys.argv[2]
    fps = int(sys.argv[3]) if len(sys.argv) > 3 else FPS

    paths = sorted(glob.glob(os.path.join(raw_dir, "raw_*.png")))
    if not paths:
        raise SystemExit("没有找到 raw_*.png，请先运行 ExtractFrames.swift")

    # Keep at most one full loop, and thin the frames if a lower rate was asked
    # for. The video is 6 seconds long at 20 fps.
    wanted = int(round(LOOP_SECONDS * fps))
    step = max(1, len(paths) // wanted)
    paths = paths[::step][:wanted]

    frames = []
    boxes = []
    for path in paths:
        rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
        silhouette, _ = mask_for(rgb)
        alpha = np.clip(
            ndimage.gaussian_filter(silhouette.astype(np.float32) * 255, 0.8),
            0, 255,
        ).astype(np.uint8)
        rgba = np.dstack([rgb.astype(np.uint8), alpha])
        frames.append(Image.fromarray(rgba, "RGBA"))
        ys, xs = np.where(silhouette)
        boxes.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    # One shared crop for every frame: the tail swings from side to side, and
    # a per-frame bounding box would make the whole dog appear to bounce.
    left = min(b[0] for b in boxes)
    top = min(b[1] for b in boxes)
    right = max(b[2] for b in boxes)
    bottom = max(b[3] for b in boxes)
    margin = 6
    left, top = max(0, left - margin), max(0, top - margin)
    right = min(frames[0].width, right + margin)
    bottom = min(frames[0].height, bottom + margin)

    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob(os.path.join(out_dir, "rest_dog_*.png")):
        os.remove(old)

    scale = min(DOG_BOX / (right - left), DOG_BOX / (bottom - top))
    size = (max(1, int((right - left) * scale)), max(1, int((bottom - top) * scale)))
    x = (CANVAS_W - size[0]) // 2
    y = (CANVAS_H - size[1]) // 2

    for index, frame in enumerate(frames):
        dog = frame.crop((left, top, right, bottom)).resize(size, Image.LANCZOS)
        canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
        canvas.alpha_composite(dog, (x, y))
        canvas.save(os.path.join(out_dir, "rest_dog_%03d.png" % index))

    print("共用裁剪框 (%d, %d, %d, %d)，缩放后 %dx%d，画布 %dx%d" %
          (left, top, right, bottom, size[0], size[1], CANVAS_W, CANVAS_H))
    print("已生成 %d 帧（%d fps，循环 %.1f 秒）到 %s" %
          (len(frames), fps, len(frames) / fps, out_dir))

    # A contact sheet makes it easy to eyeball the result on both menu bars.
    picks = np.linspace(0, len(frames) - 1, 9).astype(int)
    sheet = Image.new("RGB", (CANVAS_W * 3 * 2, CANVAS_H * 3 * 2), (40, 40, 40))
    for i, pick in enumerate(picks):
        tile = Image.new("RGBA", (CANVAS_W, CANVAS_H), (40, 40, 40, 255))
        tile.alpha_composite(frames[pick].crop((left, top, right, bottom))
                             .resize(size, Image.LANCZOS), (x, y))
        sheet.paste(tile.convert("RGB").resize((CANVAS_W * 2, CANVAS_H * 2)),
                    ((i % 3) * CANVAS_W * 2, (i // 3) * CANVAS_H * 2))
    sheet.save("/tmp/rest_sheet.png")


if __name__ == "__main__":
    main()
