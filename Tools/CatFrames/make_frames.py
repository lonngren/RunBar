#!/usr/bin/env python3
"""Cut the user's green-screen cat video into menu-bar frames.

The source is 1280x720 at 30 fps. Its backdrop is a *green gradient with a
vignette* rather than pure #00FF00, but it is still cleanly separable: the
backdrop has a green excess ``G - (R+B)/2`` of about 27...31, while the
orange-and-white cat sits at -15...0. A soft chroma key therefore yields a
per-pixel alpha with real semi-transparent edges. Unlike the earlier pale-grey
source, there is no need to guess a silhouette, repaint the white fur, or draw
an artificial outline -- all of which produced the chunky brown residue around
the legs.

The cat walks across the frame rather than looping in place, so every frame is
aligned on the centre of mass of its upper body before one common crop is
taken. The first 32 frames with a well-closed walking cycle are exported, plus
a still standing pose for the idle bucket.

Extract the video frames first (the shared AVFoundation helper lives in
Tools/RestDogFrames)::

    swift Tools/RestDogFrames/ExtractFrames.swift cat-green.mp4 /tmp/cat_green_raw 30
    python3 Tools/CatFrames/make_frames.py /tmp/cat_green_raw CatBar/Resources/CatFrames
"""

import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

# 4x artwork for the cat's 44x22 pt canvas.
CANVAS = (176, 88)


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32)


def cutout(rgb):
    """Soft chroma key + green-spill suppression + largest connected blob."""
    exg = rgb[..., 1] - (rgb[..., 0] + rgb[..., 2]) / 2
    alpha = np.clip((20.0 - exg) / 12.0, 0.0, 1.0)
    alpha = ndimage.median_filter(alpha, size=3)

    # Keep only the cat: compression noise, motion lines and the faint ground
    # shadow form small separate islands.
    solid = alpha > 0.5
    labels, count = ndimage.label(solid)
    if count:
        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        keep = ndimage.binary_dilation(labels == sizes.argmax(), iterations=2)
        alpha *= keep

    # Despill: edge pixels still carry a little of the green backdrop. The cat
    # has no green of its own, so clamping G to the red/blue average is safe.
    g = np.minimum(rgb[..., 1], (rgb[..., 0] + rgb[..., 2]) / 2 + 2.0)
    out = np.dstack([rgb[..., 0], g, rgb[..., 2], alpha * 255.0])
    return np.clip(out, 0, 255).astype(np.uint8), alpha


def aligned(rgba, alpha):
    """Translate the cat so its upper body is centred at (640, 360)."""
    head = (alpha > 0.5).copy()
    head[420:, :] = False                 # ignore leg poses and the shadow
    ys, xs = np.nonzero(head)
    cx = float(xs.mean()) if len(xs) else 640.0
    cy = float(ys.mean()) if len(ys) else 360.0
    shifted = ndimage.shift(
        rgba.astype(np.float32), (360.0 - cy, 640.0 - cx, 0),
        order=0, mode="constant", cval=0,
    )
    return np.clip(shifted, 0, 255).astype(np.uint8)


def fit(image, box):
    """Scale a cut-out to the 4x canvas, preserving its aspect ratio."""
    crop = image.crop(box)
    scale = min(CANVAS[0] / crop.width, CANVAS[1] / crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    drawn = crop.resize(size, Image.LANCZOS)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    canvas.alpha_composite(drawn, ((CANVAS[0] - size[0]) // 2,
                                   (CANVAS[1] - size[1]) // 2))
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames_dir", help="directory of raw_NNN.png frames")
    ap.add_argument("out_dir", help="directory to write cat_run_NN.png into")
    ap.add_argument("--start", type=int, default=41,
                    help="first frame of the walking cycle (30 fps source)")
    ap.add_argument("--frames", type=int, default=32)
    ap.add_argument("--rest", type=int, default=239,
                    help="frame holding the standing pose for the idle bucket")
    ap.add_argument("--rest-out", default=None,
                    help="directory for rest_cat.png (defaults to out_dir parent)")
    ap.add_argument("--sheet", default="/tmp/cat_green_sheet.png")
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(args.frames_dir, "raw_*.png")))
    if not paths:
        raise SystemExit(f"no raw_*.png frames in {args.frames_dir}")
    print("source frames", len(paths), "size", Image.open(paths[0]).size)

    # Sanity check that this really is a green-screen source.
    probe = load(paths[0])
    exg = probe[..., 1] - (probe[..., 0] + probe[..., 2]) / 2
    if np.percentile(exg, 50) < 12:
        raise SystemExit("backdrop does not look green -- check the source video")

    indices = list(range(args.start, args.start + args.frames))
    if args.rest >= len(paths) or indices[-1] >= len(paths):
        raise SystemExit("not enough source frames for the requested range")

    rendered = {}
    for i in sorted(set(indices + [args.rest])):
        rgba, alpha = cutout(load(paths[i]))
        rendered[i] = aligned(rgba, alpha)

    # One common crop for the whole loop: no size or position jitter.
    union = np.zeros((720, 1280), dtype=bool)
    for i in indices:
        union |= rendered[i][..., 3] > 20
    ys, xs = np.nonzero(union)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    print("walking frames", indices[0], "..", indices[-1], "union box", box)

    os.makedirs(args.out_dir, exist_ok=True)
    for n, i in enumerate(indices):
        fit(Image.fromarray(rendered[i], "RGBA"), box).save(
            os.path.join(args.out_dir, f"cat_run_{n:02d}.png"))

    rest_dir = args.rest_out or os.path.dirname(os.path.abspath(args.out_dir))
    os.makedirs(rest_dir, exist_ok=True)
    fit(Image.fromarray(rendered[args.rest], "RGBA"), box).save(
        os.path.join(rest_dir, "rest_cat.png"))
    print(f"wrote {len(indices)} walking frames + rest_cat.png (from frame {args.rest})")

    # Preview: eight loop frames plus the still, on dark and light menu bars.
    picks = [rendered[indices[round(k * (len(indices) - 1) / 7)]] for k in range(8)]
    picks.append(rendered[args.rest])
    sheet = Image.new("RGB", (9 * 120, 2 * 100), (255, 255, 255))
    for k, frame in enumerate(picks):
        for row, colour in enumerate([(44, 44, 48, 255), (242, 242, 245, 255)]):
            bg = Image.new("RGBA", (116, 88), colour)
            bg.alpha_composite(fit(Image.fromarray(frame, "RGBA"), box)
                               .resize((116, 88), Image.LANCZOS))
            sheet.paste(bg.convert("RGB"), (k * 120, row * 100))
    ImageDraw.Draw(sheet).text((6, 184), "dark / light menu bar", fill=(90, 90, 90))
    sheet.save(args.sheet)
    print("sheet:", args.sheet)


if __name__ == "__main__":
    main()
