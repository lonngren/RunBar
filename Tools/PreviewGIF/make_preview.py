#!/usr/bin/env python3
"""Build the README showcase GIFs from RunBar's real animation frames.

The frames shipped in the app are transparent PNGs at 4x menu-bar size
(116x88 for the dog, 176x88 for the cat). For a README they are far too
small, so each frame is upscaled and composited onto an opaque dark "menu bar
strip". An opaque background matters here: GitHub renders README images on
both light and dark themes, and both animals have large white areas -- a
transparent GIF would make them disappear on light theme. A small CPU label
reproduces what the real status item looks like.

Usage:
    python3 Tools/PreviewGIF/make_preview.py \
        --run-dir  CatBar/Resources/DogFrames \
        --rest-dir CatBar/Resources/RestDogFrames \
        --cat-dir  CatBar/Resources/CatFrames \
        --out-dir  Docs
"""

import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 360, 200
SCALE = 1.7
TOP = np.array((58.0, 61.0, 69.0))
BOTTOM = np.array((31.0, 32.0, 37.0))
BORDER = (88, 92, 103)
TEXT = (178, 184, 198)
FONT_PATH = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def background():
    """A vertical gradient that stands in for the macOS menu bar."""
    t = np.linspace(0.0, 1.0, H)[:, None, None]
    grad = TOP * (1 - t) + BOTTOM * t
    arr = np.repeat(grad, W, axis=1).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGB")
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W - 1, H - 1), outline=BORDER, width=1)
    d.line((0, 0, W, 0), fill=(104, 108, 120), width=1)
    return img


def compose(frame, bg, label, font):
    """Scale with the frame's own aspect ratio (cat and dog canvases differ)."""
    w, h = frame.size
    dw, dh = round(w * SCALE), round(h * SCALE)
    art = frame.convert("RGBA").resize((dw, dh), Image.LANCZOS)
    out = bg.copy()
    out.paste(art, ((W - dw) // 2, (H - dh) // 2), art)
    if font:
        ImageDraw.Draw(out).text((18, 15), label, font=font, fill=TEXT)
    return out


def pick_indices(total, keep):
    """Resample a loop to `keep` frames without changing its duration."""
    if keep >= total:
        return list(range(total))
    return [min(total - 1, round(i * total / keep)) for i in range(keep)]


def encode(frames, path, duration):
    """One shared palette for every frame: no colour flicker between frames."""
    palette = frames[0].quantize(
        colors=192, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE
    )
    encoded = [
        f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames
    ]
    encoded[0].save(
        path,
        save_all=True,
        append_images=encoded[1:],
        duration=duration,
        loop=0,
        disposal=1,
        optimize=True,
    )
    return encoded


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--rest-dir", required=True)
    ap.add_argument("--cat-dir", default="CatBar/Resources/CatFrames")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--sheet", default="/tmp/runbar_preview_sheet.png")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    bg = background()
    font = ImageFont.truetype(FONT_PATH, 15) if os.path.exists(FONT_PATH) else None

    # GIF stores delays in hundredths of a second, so use exact 10ms steps.
    # Resting uses every frame: 120 x 50ms is the app's real 20 fps / 6s loop.
    run_paths = sorted(glob.glob(os.path.join(args.run_dir, "dog_run_*.png")))
    rest_paths = sorted(glob.glob(os.path.join(args.rest_dir, "rest_dog_*.png")))
    cat_paths = sorted(glob.glob(os.path.join(args.cat_dir, "cat_run_*.png")))
    jobs = [
        ("run", run_paths, len(run_paths), 60, "CPU  92%", "dog-running.gif"),
        ("rest", rest_paths, len(rest_paths), 50, "CPU  4%", "dog-resting.gif"),
        ("cat", cat_paths, len(cat_paths), 60, "CPU  63%", "cat-walking.gif"),
    ]

    samples = []
    for kind, paths, keep, duration, label, filename in jobs:
        if not paths:
            raise SystemExit(f"no frames for {kind}: empty directory")
        idx = pick_indices(len(paths), keep)
        frames = [
            compose(Image.open(paths[i]), bg, label, font) for i in idx
        ]
        out = os.path.join(args.out_dir, filename)
        encode(frames, out, duration)
        size = os.path.getsize(out)
        print(f"{filename}: {len(frames)} frames, {duration}ms/frame, "
              f"{W}x{H}, {size / 1024:.0f} KiB")

        # Read the GIF back. Pillow's optimiser may coalesce identical frames
        # (the source video was 24 fps inside a 30 fps container), folding the
        # dropped frame's delay into its neighbour. So check the *total*
        # duration plus the first frame's pixels rather than assuming indices
        # still line up with the source frames.
        gif = Image.open(out)
        total_delay = 0
        for n in range(gif.n_frames):
            gif.seek(n)
            total_delay += gif.info.get("duration", 0)
            gif.convert("RGB")
        if total_delay != len(frames) * duration:
            raise SystemExit(f"{filename} duration {total_delay}ms "
                             f"!= {len(frames) * duration}ms")
        gif.seek(0)
        got = np.asarray(gif.convert("RGB"), dtype=np.int16)
        want = np.asarray(frames[0], dtype=np.int16)
        if np.abs(got - want).mean() > 12:
            raise SystemExit(f"{filename} first frame differs from source")
        samples.append((label, [frames[i] for i in
                                (0, len(frames) // 3, 2 * len(frames) // 3)]))

    # Contact sheet for a quick visual check of all three loops.
    sheet = Image.new("RGB", (W * 3, H * 3 + 60), (245, 245, 247))
    for row, (label, picks) in enumerate(samples):
        for col, frame in enumerate(picks):
            sheet.paste(frame, (col * W, row * (H + 20)))
        ImageDraw.Draw(sheet).text((8, row * (H + 20) + H + 2),
                                  label, fill=(60, 60, 60))
    sheet.save(args.sheet)
    print("sheet:", args.sheet)


if __name__ == "__main__":
    main()
