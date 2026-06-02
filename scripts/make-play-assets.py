#!/usr/bin/env python3
"""
make-play-assets.py

Generate Google Play graphic assets for TokenCounter.

- Icon: from iOS icon-1024.png, resized to 512x512.
- Feature graphic: 1024x500, app icon + wordmark on brand navy.
- Screenshots: REAL Android captures (emulator, demo mode) with marketing
  caption overlays drawn into the top whitespace. Same caption copy as iOS.

Raw Android captures live in docs/play-store-assets/android-raw/:
    shot-dashboard.png    (1080x2400) dashboard in demo mode
    01-after-launch.png   (1080x2400) onboarding "One-time setup"

Outputs under docs/play-store-assets/:
    icon-512.png
    feature-graphic.png
    screenshots/01-dashboard.png
    screenshots/02-onboarding.png
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
IOS_ICON = REPO / "ios/TokenTracker/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
OUT = REPO / "docs/play-store-assets"
RAW = OUT / "android-raw"
SHOTS_OUT = OUT / "screenshots"

NAVY = (24, 28, 36)
WHITE = (255, 255, 255)
INK = (20, 22, 28)
BLUE = (10, 110, 235)
SUBGRAY = (150, 158, 170)

FEATURE_W, FEATURE_H = 1024, 500

# Caption copy mirrors iOS app-store-listing.md
# src -> (headline, subhead, out_name, crop_bottom_px)
# crop_bottom_px trims the device capture's bottom band before framing
# (used to drop the dashboard footer link that carries a spell-check underline).
CAPTIONS = {
    "shot-dashboard.png": ("How much am I spending?", "Live Anthropic API costs, on your phone", "01-dashboard.png", 300),
    "shot-onboarding.png": ("30-second setup", "No account. No server. No tracking.", "02-onboarding.png", 0),
}


def font(size, bold=False):
    cands = []
    if bold:
        cands += [
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
    else:
        cands += [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
    cands += ["/Library/Fonts/Arial.ttf"]
    for c in cands:
        if Path(c).exists():
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()


def make_icon():
    OUT.mkdir(parents=True, exist_ok=True)
    icon = Image.open(IOS_ICON).convert("RGB").resize((512, 512), Image.LANCZOS)
    p = OUT / "icon-512.png"
    icon.save(p)
    print("icon ->", p)


def text_centered(d, cx, y, txt, fnt, fill):
    bbox = d.textbbox((0, 0), txt, font=fnt)
    w = bbox[2] - bbox[0]
    d.text((cx - w / 2, y), txt, font=fnt, fill=fill)
    return bbox[3] - bbox[1]


def make_feature_graphic():
    img = Image.new("RGB", (FEATURE_W, FEATURE_H), NAVY)
    d = ImageDraw.Draw(img)
    icon = Image.open(IOS_ICON).convert("RGBA").resize((300, 300), Image.LANCZOS)
    img.paste(icon, (90, (FEATURE_H - 300) // 2), icon)
    tx = 470
    d.text((tx, 170), "TokenCounter", font=font(76, bold=True), fill=WHITE)
    d.text((tx, 280), "Anthropic API spend,", font=font(36), fill=(205, 212, 224))
    d.text((tx, 328), "live on your phone.", font=font(36), fill=(205, 212, 224))
    p = OUT / "feature-graphic.png"
    img.save(p)
    print("feature graphic ->", p)


def caption_screenshot(src_name, headline, subhead, out_name, crop_bottom=0):
    """Real Android capture placed on a clean white marketing frame with a
    caption band on TOP (headline + subhead) and the device shot below, framed
    with a subtle rounded border. Final 1080x1920 (9:16) Play phone screenshot.
    No fake mockup chrome — the actual app screen, just framed + captioned."""
    shot = Image.open(RAW / src_name).convert("RGB")
    if crop_bottom > 0:
        shot = shot.crop((0, 0, shot.width, shot.height - crop_bottom))

    CANVAS_W, CANVAS_H = 1080, 1920
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), WHITE)
    d = ImageDraw.Draw(canvas)
    cx = CANVAS_W // 2

    # Caption band at top
    y = 90
    h1 = text_centered(d, cx, y, headline, font(62, bold=True), INK)
    y += h1 + 34
    text_centered(d, cx, y, subhead, font(40), BLUE)

    # Device shot below caption, scaled to fit remaining height
    top_band = 340
    avail_h = CANVAS_H - top_band - 40
    avail_w = CANVAS_W - 120
    scale = min(avail_w / shot.width, avail_h / shot.height)
    new_w, new_h = int(shot.width * scale), int(shot.height * scale)
    shot_r = shot.resize((new_w, new_h), Image.LANCZOS)
    x = (CANVAS_W - new_w) // 2
    y2 = top_band + (avail_h - new_h) // 2
    # subtle border frame
    d.rectangle([x - 3, y2 - 3, x + new_w + 2, y2 + new_h + 2], outline=(225, 228, 233), width=3)
    canvas.paste(shot_r, (x, y2))

    SHOTS_OUT.mkdir(parents=True, exist_ok=True)
    p = SHOTS_OUT / out_name
    canvas.save(p)
    print("screenshot ->", p, canvas.size)


def make_screenshots():
    for src, (h, s, out, crop) in CAPTIONS.items():
        caption_screenshot(src, h, s, out, crop)


if __name__ == "__main__":
    make_icon()
    make_feature_graphic()
    make_screenshots()
    print("\nDone ->", OUT)
