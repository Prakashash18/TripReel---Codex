#!/usr/bin/env python3
"""Build side-by-side TripReel reference/native QA images."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent.parent
QA = ROOT / "qa"
SCREENS = ("welcome", "access", "trips", "pace", "export", "done", "cleanup")
COMPACT_SCREENS = ("access", "limited", "trips", "cut", "pace", "export", "paywall", "done", "cleanup")
VIEWPORT = (402, 874)
PAIR_SIZE = (844, 930)
BACKGROUND = "#120b07"
CREAM = "#fdfaf5"
MUTED = "#9d938b"


def font(size: int) -> ImageFont.ImageFont:
    candidates = (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSRounded.ttf",
    )
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def pair_for(screen: str) -> Image.Image:
    reference = Image.open(QA / f"reference-{screen}.png").convert("RGB")
    native = Image.open(QA / f"{screen}-final-402.png").convert("RGB")
    reference = reference.resize(VIEWPORT, Image.Resampling.LANCZOS)
    native = native.resize(VIEWPORT, Image.Resampling.LANCZOS)

    pair = Image.new("RGB", PAIR_SIZE, BACKGROUND)
    draw = ImageDraw.Draw(pair)
    draw.text((10, 8), screen.upper(), fill=CREAM, font=font(17))
    draw.text((10, 32), "SOURCE", fill=MUTED, font=font(11))
    draw.text((432, 32), "NATIVE SWIFTUI", fill=MUTED, font=font(11))
    pair.paste(reference, (10, 51))
    pair.paste(native, (432, 51))
    return pair


def main() -> None:
    pairs = []
    for screen in SCREENS:
        pair = pair_for(screen)
        pair.save(QA / f"compare-{screen}-final.png", quality=95)
        pairs.append(pair)

    columns = 3
    rows = (len(pairs) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (PAIR_SIZE[0] * columns, PAIR_SIZE[1] * rows),
        BACKGROUND,
    )
    for index, pair in enumerate(pairs):
        x = (index % columns) * PAIR_SIZE[0]
        y = (index // columns) * PAIR_SIZE[1]
        sheet.paste(pair, (x, y))
    sheet.save(QA / "compare-states-final.png", quality=94)

    compact_width = 250
    compact_height = 445
    label_height = 28
    compact_sheet = Image.new(
        "RGB",
        (compact_width * 3, (compact_height + label_height) * 3),
        BACKGROUND,
    )
    compact_draw = ImageDraw.Draw(compact_sheet)
    for index, screen in enumerate(COMPACT_SCREENS):
        source = Image.open(QA / f"{screen}-375x667.png").convert("RGB")
        source.thumbnail((compact_width, compact_height), Image.Resampling.LANCZOS)
        x = (index % 3) * compact_width
        y = (index // 3) * (compact_height + label_height)
        compact_draw.text((x + 8, y + 5), screen.upper(), fill=CREAM, font=font(13))
        compact_sheet.paste(source, (x, y + label_height))
    compact_sheet.save(QA / "responsive-375x667-final.png", quality=94)


if __name__ == "__main__":
    main()
