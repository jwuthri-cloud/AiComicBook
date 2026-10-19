"""Safety Atlas app icon: a glowing shield around a small neural network. Usage: python3 app/tools/make_icon.py app/Panels/Assets.xcassets/AppIcon.appiconset/icon-1024.png"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4096          # draw at 4x, downsample for clean edges
K = S / 1024


def p(x, y):
    return (x * K, y * K)


def bezier(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def shield(scale=1.0):
    cx, top, bottom = 512, 178, 862
    w = 262 * scale

    def s(x, y):  # scale around the shield's centre
        return p(cx + (x - cx) * scale, 520 + (y - 520) * scale)

    pts = []
    pts += bezier(s(cx, top), s(cx + 90, 232), s(cx + 190, 252), s(cx + w, 250))      # top right shoulder
    pts += bezier(s(cx + w, 250), s(cx + w + 6, 420), s(cx + w - 10, 560), s(cx + 200, 690))  # right side
    pts += bezier(s(cx + 200, 690), s(cx + 140, 772), s(cx + 70, 826), s(cx, bottom))  # right to tip
    pts += bezier(s(cx, bottom), s(cx - 70, 826), s(cx - 140, 772), s(cx - 200, 690))
    pts += bezier(s(cx - 200, 690), s(cx - w + 10, 560), s(cx - w - 6, 420), s(cx - w, 250))
    pts += bezier(s(cx - w, 250), s(cx - 190, 252), s(cx - 90, 232), s(cx, top))
    return pts


CYAN = (22, 217, 239)
VIOLET = (173, 112, 220)
LIME = (169, 213, 43)
AMBER = (245, 190, 50)
INK = (242, 238, 223)

# Background: deep navy to teal-black, diagonal.
bg = Image.new("RGB", (S, S))
top, bot = (12, 20, 34), (6, 34, 42)
grad = Image.linear_gradient("L").resize((S, S))
bg = Image.composite(Image.new("RGB", (S, S), bot), Image.new("RGB", (S, S), top), grad)

# Faint radial light behind the shield.
halo = Image.new("L", (S, S), 0)
ImageDraw.Draw(halo).ellipse([p(212, 210), p(812, 830)], fill=70)
halo = halo.filter(ImageFilter.GaussianBlur(160 * K / 4))
bg = Image.composite(Image.new("RGB", (S, S), (20, 90, 105)), bg, halo)

# Network: 3 -> 2 -> 1 nodes inside the shield.
layers = [[(400, 405), (512, 385), (624, 405)], [(450, 548), (574, 548)], [(512, 688)]]
colors = [[CYAN, CYAN, CYAN], [VIOLET, VIOLET], [LIME]]

art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(art)

# Shield: soft fill + bright stroke.
# Outline as a filled ring (outer minus inner shield): clean edges, no stroke joints.
d.polygon(shield(), fill=CYAN + (255,))
d.polygon(shield(0.93), fill=(16, 50, 62, 255))
d.polygon(shield(0.82), fill=(10, 32, 42, 255))

for a, b in zip(layers, layers[1:]):
    for x0, y0 in a:
        for x1, y1 in b:
            d.line([p(x0, y0), p(x1, y1)], fill=(150, 230, 240, 150), width=int(12 * K))
for layer, cols in zip(layers, colors):
    for (x, y), c in zip(layer, cols):
        r = 38
        d.ellipse([p(x - r, y - r), p(x + r, y + r)], fill=c + (255,))
        r2 = 14
        d.ellipse([p(x - r2, y - r2), p(x + r2, y + r2)], fill=INK + (255,))

# Glow: blurred copy of the art, added on top of the background.
glow = art.filter(ImageFilter.GaussianBlur(28 * K))
out = bg.convert("RGBA")
out = Image.alpha_composite(out, Image.merge("RGBA", (*glow.split()[:3], glow.split()[3].point(lambda v: int(v * 0.85)))))
out = Image.alpha_composite(out, art)

out.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(sys.argv[1], "PNG", optimize=True)
print("wrote", sys.argv[1])
