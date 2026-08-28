from __future__ import annotations

from PIL import Image, ImageDraw, ImageFont


def make_icon(state: str = "normal", remaining: float | None = None):
    """Build a high-contrast tray gauge for the lowest remaining quota."""
    colors = {"normal": "#22a447", "warning": "#e09b16", "critical": "#d43732", "degraded": "#70757a"}
    image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    color = colors.get(state, colors["degraded"])
    draw.ellipse((2, 2, 62, 62), fill="#1f2329")
    draw.arc((7, 7, 57, 57), start=-90, end=270, fill="#4b5563", width=7)
    if remaining is not None:
        draw.arc((7, 7, 57, 57), start=-90, end=-90 + max(0, min(100, remaining)) * 3.6, fill=color, width=7)
        label = f"{remaining:.0f}"
    else:
        label = "!" if state == "degraded" else "AI"
    try:
        font = ImageFont.truetype("arial.ttf", 20 if remaining is not None else 18)
    except OSError:
        font = ImageFont.load_default()
    box = draw.textbbox((0, 0), label, font=font)
    draw.text(((64 - (box[2] - box[0])) / 2, (64 - (box[3] - box[1])) / 2 - 2), label, fill="white", font=font)
    return image
