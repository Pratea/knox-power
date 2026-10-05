"""Gera a capa da Workshop (workshop/preview.png, 256x256) e o poster do mod
(mod/KnoxPower/42/poster.png) a partir do modelo em art/ (mesmo render do build_art).

Uso:  python tools/make_preview.py
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_art as ba  # noqa: E402

ROOT = ba.ROOT


def font(size, bold=True):
    for name in (("arialbd.ttf", "impact.ttf") if bold else ("arial.ttf",)):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    V, T, N, F = ba.load_obj(os.path.join(ba.ART, "fuse_box.obj"))
    tex = Image.open(os.path.join(ba.ART, "fuse_box.png")).convert("RGBA")
    nV, nN = ba.to_world_north(V, N)
    rv, rn = ba.rotate(nV, "W"), ba.rotate(nN, "W")
    box = ba.render_iso(rv, T, rn, ba.triangles(F, rv, rn), tex, scale=3.0, frame=(400, 900), top=(200, 820))
    box = box.crop(box.getbbox())

    S = 256
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    # fundo: parede escura com brilho amarelo atras da caixa
    for y in range(S):
        c = int(28 + 22 * y / S)
        draw.line([(0, y), (S, y)], fill=(c, c - 4, c - 10, 255))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r in range(110, 0, -4):
        a = int(70 * (1 - r / 110))
        gd.ellipse([S / 2 - r, 112 - r, S / 2 + r, 112 + r], fill=(255, 200, 40, a))
    img.alpha_composite(glow)

    box.thumbnail((150, 150), Image.LANCZOS)
    img.alpha_composite(box, ((S - box.width) // 2, 112 - box.height // 2))

    title = "KNOX POWER"
    f = font(34)
    tw = draw.textlength(title, font=f)
    x, y = (S - tw) / 2, 196
    for ox in range(-2, 3):
        for oy in range(-2, 3):
            draw.text((x + ox, y + oy), title, font=f, fill=(0, 0, 0, 255))
    draw.text((x, y), title, font=f, fill=(255, 210, 50, 255))
    sub = "power panels & breakers"
    f2 = font(13, bold=False)
    sw = draw.textlength(sub, font=f2)
    draw.text(((S - sw) / 2, 236), sub, font=f2, fill=(220, 220, 220, 255))

    img = img.convert("RGB")
    img.save(os.path.join(ROOT, "workshop", "preview.png"))
    img.save(os.path.join(ROOT, "mod", "KnoxPower", "42", "poster.png"))
    print("ok")


if __name__ == "__main__":
    main()
