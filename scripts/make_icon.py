"""Draws the Wafflez Wordz app icon (golden waffle on midnight) and writes AppIcon.icns + a PNG preview."""
import io, struct, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def icon():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Midnight squircle background with a vertical gradient.
    bg = Image.new("RGBA", (S, S))
    top, bottom = (16, 22, 52, 255), (8, 11, 28, 255)
    d = ImageDraw.Draw(bg)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([60, 60, S - 60, S - 60], radius=200, fill=255)
    img.paste(bg, (0, 0), mask)
    # Moon glow
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([560, 110, 900, 450], fill=(124, 140, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    img = Image.alpha_composite(img, Image.composite(glow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))
    # Stars
    d = ImageDraw.Draw(img)
    for (x, y, r) in [(250, 230, 7), (330, 170, 4), (800, 620, 5), (190, 520, 4), (720, 200, 6)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(230, 233, 245, 220))
    # Waffle shadow
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([262, 312, 782, 832], radius=110, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    img = Image.alpha_composite(img, shadow)
    # Waffle body
    waffle = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    wd = ImageDraw.Draw(waffle)
    x0, y0, x1, y1 = 252, 282, 772, 802
    wd.rounded_rectangle([x0, y0, x1, y1], radius=110, fill=(245, 185, 66, 255))
    # Gradient sheen
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    for i in range(y1 - y0):
        t = i / (y1 - y0)
        sd.line([(x0, y0 + i), (x1, y0 + i)], fill=lerp((255, 214, 120, 255), (232, 138, 60, 255), t))
    wm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(wm).rounded_rectangle([x0, y0, x1, y1], radius=110, fill=255)
    waffle = Image.composite(sheen, waffle, wm)
    wd = ImageDraw.Draw(waffle)
    # Pockets (4x4 grid)
    n, pad, gap = 4, 46, 22
    cell = ((x1 - x0) - pad * 2 - gap * (n - 1)) / n
    for r in range(n):
        for c in range(n):
            cx = x0 + pad + c * (cell + gap)
            cy = y0 + pad + r * (cell + gap)
            wd.rounded_rectangle([cx, cy, cx + cell, cy + cell], radius=22, fill=(176, 98, 28, 255))
            wd.rounded_rectangle([cx + 6, cy + 6, cx + cell, cy + cell], radius=20, fill=(150, 80, 20, 255))
    img = Image.alpha_composite(img, waffle)
    # Syrup drip across the top
    syrup = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    yd = ImageDraw.Draw(syrup)
    color = (122, 62, 12, 235)
    yd.rounded_rectangle([300, 270, 740, 340], radius=36, fill=color)
    for (x, h) in [(340, 120), (430, 70), (520, 150), (640, 95), (700, 60)]:
        yd.rounded_rectangle([x - 18, 300, x + 18, 300 + h], radius=18, fill=color)
        yd.ellipse([x - 22, 300 + h - 26, x + 22, 300 + h + 14], fill=color)
    yd.ellipse([360, 282, 420, 300], fill=(255, 225, 160, 140))
    img = Image.alpha_composite(img, syrup)
    # Sparkle (AI)
    d = ImageDraw.Draw(img)
    cx, cy, R = 790, 300, 70
    d.polygon([(cx, cy - R), (cx + 16, cy - 16), (cx + R, cy), (cx + 16, cy + 16), (cx, cy + R), (cx - 16, cy + 16), (cx - R, cy), (cx - 16, cy - 16)], fill=(230, 233, 245, 255))
    return img

def icns(img):
    entries = [(b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128), (b"ic08", 256), (b"ic09", 512),
               (b"ic10", 1024), (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512)]
    chunks = b""
    for tag, size in entries:
        buf = io.BytesIO()
        img.resize((size, size), Image.LANCZOS).save(buf, format="PNG")
        data = buf.getvalue()
        chunks += tag + struct.pack(">I", len(data) + 8) + data
    return b"icns" + struct.pack(">I", len(chunks) + 8) + chunks

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "Resources"
    im = icon()
    im.save(f"{out}/AppIcon.png")
    with open(f"{out}/AppIcon.icns", "wb") as f:
        f.write(icns(im))
    print("wrote", out)
