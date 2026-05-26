#!/usr/bin/env python3
"""
add-caption-overlays.py

Renders marketing caption overlays (headline + subhead) into the empty top
space of the App Store screenshots captured by capture-app-store-screenshots.sh.

We do NOT add phone mockups, gradients, drop shadows, app icons, or any other
marketing chrome. The captions are plain text drawn directly onto the existing
white space at the top of each screenshot — the cleanest possible editorial
overlay, matching the app's minimalist aesthetic.

Inputs:
    docs/app-store-screenshots/6.9inch/{01-dashboard,02-onboarding}.png  (1320x2868)
    docs/app-store-screenshots/6.5inch/{01-dashboard,02-onboarding}.png  (1242x2688)

Outputs:
    docs/app-store-screenshots/6.9inch/captioned/{01-dashboard,02-onboarding}.png
    docs/app-store-screenshots/6.5inch/captioned/{01-dashboard,02-onboarding}.png

Re-running is idempotent: captions are keyed by filename, output dir is
overwritten cleanly each time.

Requires Pillow:
    python3 -m pip install --user Pillow
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.stderr.write(
        "ERROR: Pillow is required. Install with:\n"
        "    python3 -m pip install --user Pillow\n"
    )
    sys.exit(1)


# ---------------------------------------------------------------------------
# Caption copy, keyed by source filename stem. Edit these to iterate.
# ---------------------------------------------------------------------------

CAPTIONS: dict[str, dict[str, str]] = {
    "01-dashboard": {
        "headline": "How much am I spending?",
        "subhead": "Live Anthropic API costs, on your phone",
    },
    "02-onboarding": {
        "headline": "30-second setup",
        "subhead": "No account. No server. No tracking.",
    },
}


# ---------------------------------------------------------------------------
# Per-device-size typography. Sizes are tuned for the App Store screenshot
# widths so the caption block lives in the top 5%–14% of the image.
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DeviceSpec:
    """Caption rendering parameters for one App Store screenshot size."""
    label: str
    width: int
    height: int
    headline_px: int
    subhead_px: int
    # Pixel height of the iOS status bar in this device's screenshot.
    # Captions are placed strictly below this row.
    status_bar_px: int = 160
    # Maximum y-position (in pixels) the caption block is allowed to end at.
    # Per spec: ~14% from the top.
    max_block_bottom_px: int = 0  # 0 = compute as 0.16 * height
    # Subhead sits this many pixels below the headline's bottom edge.
    line_gap_px: int = 32
    # Padding (px) on each horizontal side reserved for a centered caption
    # to be considered "clean". We need a stripe of white this wide centered
    # on the image.
    clean_band_min_width_frac: float = 0.78


DEVICES: dict[str, DeviceSpec] = {
    "6.9inch": DeviceSpec(
        label="6.9\" (iPhone 17 Pro Max)",
        width=1320,
        height=2868,
        headline_px=86,
        subhead_px=42,
        status_bar_px=160,
        max_block_bottom_px=int(2868 * 0.18),  # ~516px — tighter onboarding
    ),
    "6.5inch": DeviceSpec(
        label="6.5\" (iPhone 11 Pro Max)",
        width=1242,
        height=2688,
        headline_px=80,
        subhead_px=40,
        status_bar_px=150,
        max_block_bottom_px=int(2688 * 0.18),  # ~484px
    ),
}


# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

HEADLINE_COLOR = (10, 10, 10, 255)        # #0A0A0A — softer than pure black
SUBHEAD_COLOR = (0, 122, 255, 255)        # #007AFF — iOS system blue


# ---------------------------------------------------------------------------
# Font resolution
# ---------------------------------------------------------------------------

SF_PRO_VARIABLE = "/System/Library/Fonts/SFNS.ttf"
ARIAL_BOLD_FALLBACK = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
HELVETICA_FALLBACK = "/System/Library/Fonts/Helvetica.ttc"


def load_font(size: int, *, bold: bool) -> ImageFont.FreeTypeFont:
    """
    Resolve an SF Pro font at the requested size + weight, with graceful
    fallback to Arial Bold / Helvetica / Pillow's default if needed.
    """
    if Path(SF_PRO_VARIABLE).exists():
        font = ImageFont.truetype(SF_PRO_VARIABLE, size=size)
        # SFNS.ttf is a variable font — set the Weight axis explicitly.
        try:
            font.set_variation_by_name("Bold" if bold else "Regular")
        except (OSError, AttributeError):
            # Older Pillow or non-variable build — accept default weight.
            pass
        return font

    if bold and Path(ARIAL_BOLD_FALLBACK).exists():
        sys.stderr.write(
            f"WARN: SF Pro ({SF_PRO_VARIABLE}) missing; using Arial Bold.\n"
        )
        return ImageFont.truetype(ARIAL_BOLD_FALLBACK, size=size)

    if Path(HELVETICA_FALLBACK).exists():
        sys.stderr.write(
            f"WARN: SF Pro ({SF_PRO_VARIABLE}) missing; using Helvetica.\n"
        )
        return ImageFont.truetype(HELVETICA_FALLBACK, size=size)

    sys.stderr.write(
        "WARN: No system fonts found; falling back to Pillow default. "
        "Captions will not match SF Pro typography.\n"
    )
    return ImageFont.load_default()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def measure_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    """Return (width, height) of the rendered string."""
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    return right - left, bottom - top


def find_clean_band_top(
    img: Image.Image,
    *,
    min_y: int,
    min_height: int,
    center_band_width: int,
) -> Optional[int]:
    """
    Scan rows from min_y downward and return the y of the first row that
    begins a vertical stripe of at least `min_height` pixels in which the
    horizontal center band (`center_band_width` wide, centered on the image)
    is entirely "white-ish" (RGB > 240).

    Returns None if no such band exists in the searched range.
    """
    rgb = img.convert("RGB")
    w, h = rgb.size
    x0 = (w - center_band_width) // 2
    x1 = x0 + center_band_width

    # Sample every 4 pixels horizontally and every row for speed.
    def row_is_clean(y: int) -> bool:
        for x in range(x0, x1, 4):
            r, g, b = rgb.getpixel((x, y))
            if r <= 240 or g <= 240 or b <= 240:
                return False
        return True

    run_start: Optional[int] = None
    for y in range(min_y, h):
        if row_is_clean(y):
            if run_start is None:
                run_start = y
            elif y - run_start + 1 >= min_height:
                return run_start
        else:
            run_start = None
    return None


def draw_caption(
    img: Image.Image,
    spec: DeviceSpec,
    headline: str,
    subhead: str,
) -> dict:
    """
    Mutates img in place: draws headline + subhead centered.

    Placement strategy:
      1. Measure the caption block height.
      2. Try to place the block in the top zone, just below the status bar,
         ending no later than max_block_bottom_px. If the band is clean,
         use it.
      3. Otherwise, fall back to the first clean-white band of sufficient
         height below the status bar — wherever it naturally lives. This
         handles screens whose first ~14% contains app chrome (nav title,
         icon buttons) by sliding the caption into the next empty zone.

    Returns a small dict describing where the block ended up (for logging).
    """
    draw = ImageDraw.Draw(img)

    headline_font = load_font(spec.headline_px, bold=True)
    subhead_font = load_font(spec.subhead_px, bold=False)

    h_w, h_h = measure_text(draw, headline, headline_font)
    s_w, s_h = measure_text(draw, subhead, subhead_font)

    block_h = h_h + spec.line_gap_px + s_h
    # Center band width: the wider of headline / subhead plus a 40px margin.
    center_band_w = max(h_w, s_w) + 40
    # Clamp to image width minus a tiny side margin.
    center_band_w = min(center_band_w, img.width - 16)

    # Padding (top + bottom) we want around the caption block so it doesn't
    # crowd adjacent UI elements when placed in a detected clean zone.
    breathing_room = 60  # 30px top + 30px bottom (approximate)
    required_band_h = block_h + breathing_room

    # 1. Preferred placement: just below the status bar, in the top spec zone.
    preferred_top = spec.status_bar_px + 8
    preferred_bottom = preferred_top + block_h
    if preferred_bottom <= spec.max_block_bottom_px:
        clean_top_in_pref = find_clean_band_top(
            img,
            min_y=preferred_top,
            min_height=required_band_h,
            center_band_width=center_band_w,
        )
        if clean_top_in_pref is not None and clean_top_in_pref + block_h <= spec.max_block_bottom_px:
            # Center the caption vertically inside the breathing room.
            y_headline = clean_top_in_pref + (breathing_room // 2)
            placement = "preferred (top zone, below status bar)"
        else:
            y_headline = None
            placement = None
    else:
        y_headline = None
        placement = None

    # 2. Fallback: first clean band anywhere below the status bar with
    #    enough breathing room.
    if y_headline is None:
        clean_top = find_clean_band_top(
            img,
            min_y=spec.status_bar_px + 8,
            min_height=required_band_h,
            center_band_width=center_band_w,
        )
        if clean_top is None:
            # Retry without the breathing-room cushion.
            clean_top = find_clean_band_top(
                img,
                min_y=spec.status_bar_px + 8,
                min_height=block_h,
                center_band_width=center_band_w,
            )
            if clean_top is None:
                y_headline = preferred_top
                placement = "forced (no clean band found — may overlap UI)"
            else:
                y_headline = clean_top
                placement = "fallback (tight clean band, no breathing room)"
        else:
            y_headline = clean_top + (breathing_room // 2)
            placement = "fallback (first roomy clean band below status bar)"

    # Draw headline centered.
    x_headline = (img.width - h_w) // 2
    draw.text(
        (x_headline, y_headline),
        headline,
        font=headline_font,
        fill=HEADLINE_COLOR,
    )

    # Draw subhead centered, line_gap_px below the headline.
    y_subhead = y_headline + h_h + spec.line_gap_px
    x_subhead = (img.width - s_w) // 2
    draw.text(
        (x_subhead, y_subhead),
        subhead,
        font=subhead_font,
        fill=SUBHEAD_COLOR,
    )

    return {
        "placement": placement,
        "y_headline": y_headline,
        "y_subhead": y_subhead,
        "block_height": block_h,
        "center_band_width": center_band_w,
    }


def process_one(
    src: Path,
    dst: Path,
    spec: DeviceSpec,
    *,
    dry_run: bool,
) -> Optional[Path]:
    """Render captioned version of src -> dst. Returns dst on success, else None."""
    stem = src.stem  # e.g. "01-dashboard"
    if stem not in CAPTIONS:
        sys.stderr.write(f"WARN: No caption configured for {src}; skipping.\n")
        return None

    captions = CAPTIONS[stem]
    headline = captions["headline"]
    subhead = captions["subhead"]

    if dry_run:
        print(
            f"  [dry-run] {src.name} -> {dst}\n"
            f"            headline: {headline!r}\n"
            f"            subhead:  {subhead!r}"
        )
        return dst

    print(f"  {src.name} -> {dst}")
    print(f"            headline: {headline!r}")
    print(f"            subhead:  {subhead!r}")

    with Image.open(src) as opened:
        img = opened.convert("RGBA")

        # Sanity-check dimensions match the spec. If not, warn but proceed —
        # we trust the spec sizes for typography, but center against actual.
        if (img.width, img.height) != (spec.width, spec.height):
            sys.stderr.write(
                f"WARN: {src} is {img.width}x{img.height}, "
                f"expected {spec.width}x{spec.height}. Proceeding anyway.\n"
            )
            # Use the actual dims for centering so we don't draw off-canvas.
            spec = DeviceSpec(
                label=spec.label,
                width=img.width,
                height=img.height,
                headline_px=spec.headline_px,
                subhead_px=spec.subhead_px,
                status_bar_px=spec.status_bar_px,
                max_block_bottom_px=int(img.height * 0.18),
                line_gap_px=spec.line_gap_px,
                clean_band_min_width_frac=spec.clean_band_min_width_frac,
            )

        info = draw_caption(img, spec, headline, subhead)
        print(
            f"            placement: {info['placement']} "
            f"(y_headline={info['y_headline']}, y_subhead={info['y_subhead']}, "
            f"block_h={info['block_height']})"
        )

        dst.parent.mkdir(parents=True, exist_ok=True)
        img.convert("RGB").save(dst, format="PNG", optimize=True)

    return dst


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned operations without writing files.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Repo root (default: parent of scripts/).",
    )
    args = parser.parse_args()

    base = args.repo_root / "docs" / "app-store-screenshots"
    if not base.exists():
        sys.stderr.write(f"ERROR: {base} does not exist.\n")
        return 1

    written: list[Path] = []
    for device_dir, spec in DEVICES.items():
        src_dir = base / device_dir
        dst_dir = src_dir / "captioned"
        if not src_dir.exists():
            sys.stderr.write(f"WARN: {src_dir} missing; skipping {device_dir}.\n")
            continue

        print(f"== {spec.label} ({device_dir}) ==")
        for stem in CAPTIONS.keys():
            src = src_dir / f"{stem}.png"
            dst = dst_dir / f"{stem}.png"
            if not src.exists():
                sys.stderr.write(f"WARN: {src} missing; skipping.\n")
                continue

            result = process_one(src, dst, spec, dry_run=args.dry_run)
            if result is not None:
                written.append(result)
        print()

    print("Summary")
    print("-------")
    if args.dry_run:
        print(f"  would write {len(written)} file(s):")
    else:
        print(f"  wrote {len(written)} file(s):")
    for path in written:
        print(f"    {path}")

    return 0 if written else 2


if __name__ == "__main__":
    sys.exit(main())
