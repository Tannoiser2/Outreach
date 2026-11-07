#!/usr/bin/env python3
"""Genera le immagini della vista 3D (e degli strati della 2D) a partire da assets/mappa.json:
- assets/board/linee.png: griglia di esagoni, numeri, lati di polvere e nomi delle stelle faro, su
  fondo trasparente (si sovrappone a qualsiasi mappa);
- assets/board/nuvola_sotto.png, nuvola_sopra.png: la galassia come nuvola, con i colori della
  mappa originale (asse dorato, frangia grigia, Nucleo rosso), trasparente.
Tutte con la stessa geometria: lato dell'esagono S pixel, margine MX/MY esagoni.
Uso: python3 tools/genera_texture.py
"""
import json, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
m = json.load(open(os.path.join(R, "assets/mappa.json")))
esa = {int(k): v for k, v in m["esagoni"].items()}
fari = {int(k): v for k, v in m["fari"].items()}
pol = [tuple(map(int, e.split("-"))) for e in m["polvere"]]
S, MX, MY = 52.0, 1.4, 1.4
W = int((75 + 2 * MX) * S)
H = int((28 * math.sqrt(3) + math.sqrt(3) / 2 + 2 * MY) * S)


def centro(h, k=1.0):
    c, r = h // 100, h % 100
    y = (r - 1) * math.sqrt(3) + (0 if c % 2 == 1 else math.sqrt(3) / 2)
    return ((c - 1) * 1.5 + MX) * S * k, (y + MY) * S * k


def esagono(h, k=1.0, sc=1.0):
    cx, cy = centro(h, sc)
    return [(cx + S * sc * k * math.cos(math.radians(a)), cy + S * sc * k * math.sin(math.radians(a))) for a in range(0, 360, 60)]


# ---------------- linee, numeri, polvere, nomi
im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
fn = ImageFont.truetype(os.path.join(R, "assets/fonts/ShareTechMono-Regular.ttf"), 13)
fs = ImageFont.truetype(os.path.join(R, "assets/fonts/OldStandard-Bold.ttf"), 17)
for h in esa:
    d.polygon(esagono(h), outline=(90, 175, 205, 230))
for h in esa:
    cx, cy = centro(h)
    d.text((cx, cy - S * 0.62), "%04d" % h, font=fn, fill=(110, 190, 220, 210), anchor="mm")
for a, b in pol:
    pa, pb = centro(a), centro(b)
    mx, my = (pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2
    dx, dy = pb[0] - pa[0], pb[1] - pa[1]
    L = math.hypot(dx, dy)
    px, py = -dy / L, dx / L
    hl = S / 2
    d.line([(mx + px * hl, my + py * hl), (mx - px * hl, my - py * hl)], fill=(240, 70, 40, 255), width=7)
for h, nome in fari.items():
    cx, cy = centro(h)
    d.ellipse([cx - 5, cy + 8, cx + 5, cy + 18], fill=(235, 55, 45, 255))
    d.text((cx, cy - 8), nome, font=fs, fill=(240, 70, 55, 255), anchor="mm", stroke_width=2, stroke_fill=(0, 0, 0, 160))
im.save(os.path.join(R, "assets/board/linee.png"), optimize=True)

# ---------------- nuvole colorate come la mappa originale
K = 0.5
w2, h2 = int(W * K), int(H * K)
COL = {"A": (205, 150, 45), "F": (175, 172, 168), "I": (40, 48, 75), "N": (190, 62, 38), "W": (245, 160, 70)}
ALFA = {"A": 0.62, "F": 0.5, "I": 0.1, "N": 0.6, "W": 0.8}


def rumore(seme, scala, ottave=4):
    g = np.random.default_rng(seme)
    out = np.zeros((h2, w2), np.float32)
    amp, tot = 1.0, 0.0
    for _ in range(ottave):
        sh = (max(2, int(h2 / scala)), max(2, int(w2 / scala)))
        n = (g.random(sh) * 255).astype(np.uint8)
        n = np.asarray(Image.fromarray(n).resize((w2, h2), Image.BICUBIC)).astype(np.float32) / 255
        out += n * amp
        tot += amp
        amp *= 0.5
        scala /= 2
    return out / tot


col = Image.new("RGB", (w2, h2), (0, 0, 0))
alf = Image.new("L", (w2, h2), 0)
dc, da = ImageDraw.Draw(col), ImageDraw.Draw(alf)
for h, t in esa.items():
    p = esagono(h, 1.08, K)
    dc.polygon(p, fill=COL[t])
    da.polygon(p, fill=int(255 * ALFA[t]))
col = np.asarray(col.filter(ImageFilter.GaussianBlur(10))).astype(np.float32) / 255
alf = np.asarray(alf.filter(ImageFilter.GaussianBlur(12))).astype(np.float32) / 255
cx, cy = centro(3915, K)
yy, xx = np.mgrid[0:h2, 0:w2]
nucleo = np.exp(-(((xx - cx) ** 2 + ((yy - cy) / 0.85) ** 2) / (150.0 ** 2)))
for nome, seme, forza, luce in [("nuvola_sotto", 3000, 1.0, 1.0), ("nuvola_sopra", 76, 0.55, 1.15)]:
    n1 = rumore(seme, 110)
    n2 = rumore(seme + 1, 30)
    a = alf * (0.45 + 0.85 * n1) * (0.75 + 0.45 * n2) * forza + nucleo * 0.35 * forza
    a = np.clip(a, 0, 0.85)
    c = np.clip(col * (0.8 + 0.4 * n2[..., None]) * luce + nucleo[..., None] * np.array([0.35, 0.22, 0.08]), 0, 1)
    stelle = np.random.default_rng(seme + 7).random((h2, w2)) > 0.9982
    c[stelle] = 1.0
    a[stelle] = np.maximum(a[stelle], 0.8)
    Image.fromarray(np.dstack([c * 255, a[..., None] * 255]).astype(np.uint8), "RGBA").save(os.path.join(R, "assets/board/%s.png" % nome), optimize=True)
json.dump({"S": S, "MX": MX, "MY": MY, "W": W, "H": H}, open(os.path.join(R, "assets/board/geometria3d.json"), "w"))
print("fatto", W, H)
