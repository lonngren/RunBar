#!/usr/bin/env python3
"""Turn the user's orange-and-white walking-cat GIF into menu-bar frames.

The source (800x450, 193 frames) has two properties that make a plain
colour-key impossible:

* The cat walks *across* the frame rather than looping in place, so every
  frame is aligned by the silhouette's centre of mass first.
* The cat's white body is almost the same colour as the pale grey backdrop.
  Thresholding on colour alone punches holes straight through the body.

Instead the dark orange markings / outlines are used as a topological seed:
a large closing connects them into one shell, filling the holes recovers the
whole cat, and the shell becomes the alpha mask.  Inside that shell the
orange details are kept and everything else is repainted as clean cream
white, so no grey backdrop survives.  A thin dark-brown outline is added
outside the shell, which is what keeps a white cat legible on a *light*
menu bar.

Usage:
    python3 Tools/CatFrames/make_frames.py <source.gif> <output-dir> \
        [--start 20] [--cycle 32] [--frames 32] [--sheet /tmp/cat_sheet.png]
"""

import argparse
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

# 4x artwork for the cat's 44x22 pt canvas.
CANVAS = (176, 88)
WHITE = np.array([250, 248, 244], dtype=np.float32)
OUTLINE = np.array([112, 86, 66], dtype=np.uint8)
OUTLINE_ALPHA = 205


def background_model(gif):
    """Fit a smooth quadratic surface to pixels that are certainly backdrop."""
    gif.seek(80)
    f = np.asarray(gif.convert("RGB")).astype(np.float32)
    h, w = f.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w]
    sample = ys < 115  # the cat never reaches the top quarter
    xn, yn = xs[sample] / w, ys[sample] / h
    design = np.column_stack([np.ones(xn.size), xn, yn, xn ** 2, yn ** 2, xn * yn])
    xa, ya = xs.ravel() / w, ys.ravel() / h
    full = np.column_stack([np.ones(xa.size), xa, ya, xa ** 2, ya ** 2, xa * ya])
    coef = np.linalg.lstsq(design, f[sample], rcond=None)[0]
    return (full @ coef).reshape(h, w, 3)


def render(gif, index, bg):
    """Render one source frame as an aligned, transparent RGBA image."""
    gif.seek(index)
    f = np.asarray(gif.convert("RGB")).astype(np.float32)
    dist = np.abs(f - bg).mean(2)
    lum = f @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    sat = f.max(2) - f.min(2)

    # Topological seed: only clearly non-backdrop pixels.
    ink = dist > 22
    shell = ndimage.binary_closing(ink, structure=np.ones((19, 19)))
    shell = ndimage.binary_fill_holes(shell)
    shell = ndimage.binary_erosion(shell, iterations=3)
    labels, count = ndimage.label(shell)
    if count:
        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        shell = labels == sizes.argmax()

    # Keep the orange/brown drawing; repaint white fur and grey shadows.
    detail = (dist > 8) & ((sat > 32) | (lum < 130))
    rgb = np.where(detail[..., None], f, WHITE).astype(np.uint8)
    alpha = np.where(shell, 255, 0).astype(np.uint8)
    rgba = np.dstack([rgb, alpha])

    # A soft outline just outside the shell for light menu bars.
    ring = ndimage.binary_dilation(shell, iterations=9) & ~shell
    rgba[ring] = [*OUTLINE, OUTLINE_ALPHA]

    cy, cx = ndimage.center_of_mass(shell)
    rgba = ndimage.shift(
        rgba, (250 - float(cy), 400 - float(cx), 0),
        order=0, mode="constant", cval=0,
    )
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gif")
    ap.add_argument("out_dir")
    ap.add_argument("--start", type=int, default=20)
    ap.add_argument("--cycle", type=int, default=32)
    ap.add_argument("--frames", type=int, default=32)
    ap.add_argument("--sheet", default="/tmp/cat_frames_sheet.png")
    args = ap.parse_args()

    gif = Image.open(args.gif)
    bg = background_model(gif)
    os.makedirs(args.out_dir, exist_ok=True)

    indices = [
        min(gif.n_frames - 1, args.start + round(i * args.cycle / args.frames))
        for i in range(args.frames)
    ]
    frames = [render(gif, i, bg) for i in indices]

    # One common crop for every frame: no size or position jitter in the loop.
    union = np.zeros((450, 800), dtype=bool)
    for fr in frames:
        union |= np.asarray(fr.getchannel("A")) > 20
    ys, xs = np.nonzero(union)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    print("source frames", indices[0], "..", indices[-1], "union box", box)

    for n, fr in enumerate(frames):
        crop = fr.crop(box)
        scale = min(CANVAS[0] / crop.width, CANVAS[1] / crop.height)
        size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
        drawn = crop.resize(size, Image.LANCZOS)
        canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        canvas.alpha_composite(drawn, ((CANVAS[0] - size[0]) // 2,
                                       (CANVAS[1] - size[1]) // 2))
        canvas.save(os.path.join(args.out_dir, f"cat_run_{n:02d}.png"))

    # Preview: a few frames on dark and light menu-bar backgrounds.
    picks = [frames[round(i * (len(frames) - 1) / 7)] for i in range(8)]
    sheet = Image.new("RGB", (8 * 120, 2 * 100), (255, 255, 255))
    for k, fr in enumerate(picks):
        for row, colour in enumerate([(44, 44, 48, 255), (242, 242, 245, 255)]):
            bgimg = Image.new("RGBA", (116, 88), colour)
            bgimg.alpha_composite(fr.crop(box).resize((116, 88), Image.LANCZOS))
            sheet.paste(bgimg.convert("RGB"), (k * 120, row * 100))
    ImageDraw.Draw(sheet).text((6, 184), "dark / light menu bar", fill=(90, 90, 90))
    sheet.save(args.sheet)
    print(f"wrote {len(frames)} frames to {args.out_dir}; sheet: {args.sheet}")


if __name__ == "__main__":
    main()
