"""Arrange untouched native screenshot crops for design review."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

folder = Path(__file__).resolve().parent
names = [("A / SUNNY", "Sunny"), ("B / PLAYFUL", "Playful"), ("C / SPORT", "Sport")]
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", 34)

def compare(filename, bounds):
    width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
    margin, header, gap = 24, 72, 24
    sheet = Image.new("RGB", (margin * 2 + width * 3 + gap * 2, height + header + margin), "#FAF6EE")
    draw = ImageDraw.Draw(sheet)
    for index, (label, name) in enumerate(names):
        source = Image.open(folder / f"{name}-Native.png").convert("RGB")
        assert source.size == (3840, 2160), source.size
        x = margin + index * (width + gap)
        draw.text((x + 10, 20), label, fill="#253C43", font=font)
        sheet.paste(source.crop(bounds), (x, header))
    sheet.save(folder / filename)

compare("Robot-Options.png", (2120, 840, 2975, 2020))
compare("Menu-Options.png", (1065, 540, 1730, 1350))
