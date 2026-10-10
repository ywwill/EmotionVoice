#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EmotionVoice icon — direction exploration (4 variants)."""
import math, os

W, MARGIN = 1024, 100
BOX = W - 2 * MARGIN
CX = CY = W / 2.0
A = BOX / 2.0
N_EXP = 5.0
OUT = os.path.dirname(os.path.abspath(__file__))

BG_TOP, BG_MID, BG_BOT = "#1A1D24", "#111318", "#0A0B0E"
G_DEEP, G_MID, G_HI = "#B98343", "#E0A360", "#FBDCAF"
AMBER, AMBER_DK = "#E8A968", "#D49B5B"


def sup(cx, cy, rx, ry, n=N_EXP, steps=720):
    pts = []
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        pts.append("%.2f,%.2f" % (cx + rx * math.copysign(abs(ct) ** (2.0 / n), ct),
                                  cy + ry * math.copysign(abs(st) ** (2.0 / n), st)))
    return "M" + "L".join(pts) + "Z"


SQUIRCLE = sup(CX, CY, A, A)
INNER = sup(CX, CY, A - 3.5, A - 3.5)

HEAD = f'''<defs>
<clipPath id="body"><path d="{SQUIRCLE}"/></clipPath>
<linearGradient id="bg" x1="0" y1="{MARGIN}" x2="0" y2="{W-MARGIN}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{BG_TOP}"/><stop offset="0.52" stop-color="{BG_MID}"/><stop offset="1" stop-color="{BG_BOT}"/>
</linearGradient>
<radialGradient id="vignette" cx="{CX}" cy="{CY-40}" r="640" gradientUnits="userSpaceOnUse">
  <stop offset="0.42" stop-color="#000000" stop-opacity="0"/><stop offset="1" stop-color="#000000" stop-opacity="0.45"/>
</radialGradient>
<radialGradient id="halo" cx="{CX}" cy="{CY-6}" r="452" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{AMBER}" stop-opacity="0.30"/><stop offset="0.42" stop-color="{AMBER_DK}" stop-opacity="0.12"/><stop offset="1" stop-color="{AMBER_DK}" stop-opacity="0"/>
</radialGradient>
<radialGradient id="core" cx="{CX}" cy="{CY}" r="200" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{G_HI}" stop-opacity="0.20"/><stop offset="0.55" stop-color="{AMBER}" stop-opacity="0.09"/><stop offset="1" stop-color="{AMBER}" stop-opacity="0"/>
</radialGradient>
<linearGradient id="rim" x1="{CX}" y1="{MARGIN}" x2="{CX}" y2="{W-MARGIN}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.30"/><stop offset="0.28" stop-color="#FFFFFF" stop-opacity="0.08"/>
  <stop offset="0.62" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.06"/>
</linearGradient>
<linearGradient id="sheen" x1="0" y1="260" x2="0" y2="770" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
  <stop offset="1" stop-color="#000000" stop-opacity="0.20"/>
</linearGradient>
{{gold}}
</defs>
<g clip-path="url(#body)">
  <rect width="{W}" height="{W}" fill="url(#bg)"/>
  <rect width="{W}" height="{W}" fill="url(#vignette)"/>
  <rect width="{W}" height="{W}" fill="url(#halo)"/>
  <rect width="{W}" height="{W}" fill="url(#core)"/>
  {{art}}
  <path d="{INNER}" fill="none" stroke="url(#rim)" stroke-width="7"/>
</g>
<path d="{SQUIRCLE}" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="2"/>'''

ICON_OPEN = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" viewBox="0 0 {W} {W}">'
ICON_CLOSE = "</svg>"


def gold_grad(id_, x0, x1, y0=None, y1=None, horizontal=True):
    if horizontal:
        c = f'x1="{x0}" y1="0" x2="{x1}" y2="0"'
    else:
        c = f'x1="0" y1="{y0}" x2="0" y2="{y1}"'
    return f'''<linearGradient id="{id_}" {c} gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{G_DEEP}"/><stop offset="0.22" stop-color="{G_MID}"/>
  <stop offset="0.5" stop-color="{G_HI}"/><stop offset="0.78" stop-color="{G_MID}"/>
  <stop offset="1" stop-color="{G_DEEP}"/></linearGradient>'''


# ---------------- Variant A: refined symmetric spectrum ----------------
def variant_a():
    bw, sp = 72, 120
    hs = [148, 288, 468, 288, 148]
    xs = [CX + k * sp for k in range(-2, 3)]
    x0, x1 = xs[0] - bw / 2, xs[-1] + bw / 2
    gold = gold_grad("ga", x0 - 40, x1 + 40)
    bars = "\n  ".join(
        f'<rect x="{x-bw/2:.1f}" y="{CY-h/2:.1f}" width="{bw}" height="{h}" rx="{bw/2}" ry="{bw/2}" fill="url(#ga)"/>'
        for x, h in zip(xs, hs))
    art = f'''<g>
  {bars}
  <rect x="{x0-60:.0f}" y="180" width="{x1-x0+120:.0f}" height="664" fill="url(#sheen)" clip-path="url(#barsClip)"/>
</g>'''
    # sheen needs a clip of the bars themselves -> use a mask instead
    mask = f'<mask id="barsClip"><g>{bars}</g></mask>'
    art = f'''<g>
  {bars}
  <g mask="url(#barsClip)"><rect x="{x0-60:.0f}" y="150" width="{x1-x0+120:.0f}" height="720" fill="url(#sheen)"/></g>
</g>'''
    return ICON_OPEN + HEAD.format(gold=gold + mask, art=art) + ICON_CLOSE


# ---------------- Variant B: speech intonation envelope ----------------
def variant_b():
    bw, sp = 74, 118
    hs = [156, 300, 452, 316, 208]
    xs = [CX + k * sp for k in range(-2, 3)]
    x0, x1 = xs[0] - bw / 2, xs[-1] + bw / 2
    gold = gold_grad("gb", x0 - 40, x1 + 40)
    bars = "\n  ".join(
        f'<rect x="{x-bw/2:.1f}" y="{CY-h/2:.1f}" width="{bw}" height="{h}" rx="{bw/2}" ry="{bw/2}" fill="url(#gb)"/>'
        for x, h in zip(xs, hs))
    mask = f'<mask id="barsClip"><g>{bars}</g></mask>'
    art = f'''<g>
  {bars}
  <g mask="url(#barsClip)"><rect x="{x0-60:.0f}" y="150" width="{x1-x0+120:.0f}" height="720" fill="url(#sheen)"/></g>
</g>'''
    return ICON_OPEN + HEAD.format(gold=gold + mask, art=art) + ICON_CLOSE


# ---------------- Variant C: continuous waveform ribbon ----------------
def variant_c():
    x0, x1 = 268, 756
    n, k_wave = 260, 2.0
    top, bot = [], []
    amp_max, thick = 210, 46
    pts_mid = []
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        env = math.sin(math.pi * t) ** 1.35          # bell envelope, 0 at both ends
        y = CY + env * amp_max * math.sin(2 * math.pi * k_wave * t - math.pi / 2)
        pts_mid.append((x, y, env))
    # build ribbon outline: offset perpendicular-ish (vertical) by thickness modulated
    up, dn = [], []
    for x, y, env in pts_mid:
        th = thick * (0.35 + 0.65 * env)
        up.append((x, y - th / 2))
        dn.append((x, y + th / 2))
    d = "M" + "L".join("%.1f,%.1f" % p for p in up) + "L" + "L".join("%.1f,%.1f" % p for p in reversed(dn)) + "Z"
    gold = gold_grad("gc", x0 - 30, x1 + 30)
    art = f'<path d="{d}" fill="url(#gc)" stroke="none"/>'
    return ICON_OPEN + HEAD.format(gold=gold, art=art) + ICON_CLOSE


# ---------------- Variant D: resonance ripples ----------------
def variant_d():
    gold = gold_grad("gd", CX - 380, CX + 380)
    rings = [(72, None), (178, 24), (286, 21), (392, 18)]
    art = []
    for r, sw in rings:
        if sw is None:
            art.append(f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="url(#gd)"/>')
        else:
            alpha = {24: 0.85, 21: 0.5, 18: 0.26}[sw]
            art.append(f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="none" stroke="url(#gd)" stroke-width="{sw}" stroke-opacity="{alpha}"/>')
    return ICON_OPEN + HEAD.format(gold=gold, art="\n  ".join(art)) + ICON_CLOSE


VARIANTS = {"A": variant_a, "B": variant_b, "C": variant_c, "D": variant_d}

if __name__ == "__main__":
    for k, fn in VARIANTS.items():
        with open(os.path.join(OUT, f"variant_{k}.svg"), "w") as f:
            f.write(fn())
    print("wrote variants A-D")
