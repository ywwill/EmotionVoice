#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EmotionVoice — final asset set: Emotion Knob."""
import math, os
import variants as V

W, CX, CY = V.W, V.CX, V.CY

R_BODY = 244
POINTER_DEG = 34.0
N_TICKS = 13
TICK_SPAN = 300.0
TICK_R = 324

KNOB_RADIAL = f'''<radialGradient id="kbody" cx="{CX-96}" cy="{CY-108}" r="392" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#FBDCAF"/><stop offset="0.18" stop-color="#EDB273"/>
  <stop offset="0.48" stop-color="#C98A45"/><stop offset="0.78" stop-color="#96682C"/>
  <stop offset="1" stop-color="#6B481C"/></radialGradient>'''
POINTER_GRAD = f'''<linearGradient id="kmark" x1="0" y1="{CY-180}" x2="0" y2="{CY}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#2B1B09"/><stop offset="1" stop-color="#452C12"/></linearGradient>'''

BODY_R = 244
PTR_W, PTR_LEN, HUB = 46, 152, 40


def _ticks(only_major=False, r=TICK_R, rad=12, minor_rad=7, major_op=0.92, minor_op=0.30):
    out = []
    for i in range(N_TICKS):
        major = (i % 3 == 0)
        if only_major and not major:
            continue
        a = math.radians(-TICK_SPAN / 2 + TICK_SPAN * i / (N_TICKS - 1))
        tx, ty = CX + r * math.cos(a), CY + r * math.sin(a)
        out.append(f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="{rad if major else minor_rad}" '
                   f'fill="{"#E8A968" if major else "#FFFFFF"}" '
                   f'fill-opacity="{major_op if major else minor_op}"/>')
    return "\n  ".join(out)


def _body(r=BODY_R, ptr_w=PTR_W, ptr_len=PTR_LEN, hub=HUB, grooves=True, bevel=True):
    art = [f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="url(#kbody)"/>']
    if grooves:
        for rr in (r - 52, r - 86, r - 120):
            art.append(f'<circle cx="{CX}" cy="{CY}" r="{rr}" fill="none" stroke="#000000" '
                       f'stroke-opacity="0.07" stroke-width="3"/>')
            art.append(f'<circle cx="{CX}" cy="{CY}" r="{rr+3}" fill="none" stroke="#FFFFFF" '
                       f'stroke-opacity="0.05" stroke-width="2"/>')
    if bevel:
        art.append(f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="none" stroke="#000000" '
                   f'stroke-opacity="0.40" stroke-width="6"/>')
        art.append(f'<circle cx="{CX}" cy="{CY}" r="{r-7}" fill="none" stroke="#FFFFFF" '
                   f'stroke-opacity="0.14" stroke-width="3"/>')
        art.append(f'<path d="M{CX-166} {CY-124} A204 204 0 0 1 {CX+70} {CY-220}" fill="none" '
                   f'stroke="#FFFFFF" stroke-opacity="0.58" stroke-width="13" stroke-linecap="round"/>')
        art.append(f'<path d="M{CX+132} {CY+158} A204 204 0 0 1 {CX-124} {CY+186}" fill="none" '
                   f'stroke="#000000" stroke-opacity="0.26" stroke-width="15" stroke-linecap="round"/>')
    art.append(f'<g transform="rotate({POINTER_DEG} {CX:.0f} {CY:.0f})">'
               f'<rect x="{CX-ptr_w/2:.0f}" y="{CY-ptr_len:.0f}" width="{ptr_w}" height="{ptr_len}" '
               f'rx="{ptr_w/2:.0f}" fill="url(#kmark)"/></g>')
    art.append(f'<circle cx="{CX}" cy="{CY}" r="{hub}" fill="url(#kmark)"/>')
    art.append(f'<circle cx="{CX}" cy="{CY}" r="{hub}" fill="none" stroke="#FFFFFF" '
               f'stroke-opacity="0.20" stroke-width="3"/>')
    return "\n  ".join(art)


# ----------------------------------------------------------- app icon ------
def build_icon():
    defs = KNOB_RADIAL + POINTER_GRAD + f'''<radialGradient id="kglow" cx="{CX}" cy="{CY}" r="430" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{V.AMBER}" stop-opacity="0.20"/>
  <stop offset="0.55" stop-color="{V.AMBER}" stop-opacity="0.06"/>
  <stop offset="1" stop-color="{V.AMBER}" stop-opacity="0"/></radialGradient>'''
    art = f'<circle cx="{CX}" cy="{CY}" r="430" fill="url(#kglow)"/>\n  ' + _ticks() + "\n  " + _body()
    return V.ICON_OPEN + V.HEAD.format(gold=defs, art=art) + V.ICON_CLOSE


def build_small_icon():
    """16/32/64px: drop the ticks, enlarge + thicken so the silhouette survives."""
    defs = KNOB_RADIAL + POINTER_GRAD + f'''<radialGradient id="kglow" cx="{CX}" cy="{CY}" r="440" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="{V.AMBER}" stop-opacity="0.22"/>
  <stop offset="0.6" stop-color="{V.AMBER}" stop-opacity="0.05"/>
  <stop offset="1" stop-color="{V.AMBER}" stop-opacity="0"/></radialGradient>'''
    art = (f'<circle cx="{CX}" cy="{CY}" r="440" fill="url(#kglow)"/>\n  '
           + _ticks(only_major=True, r=330, rad=20)
           + "\n  " + _body(r=254, ptr_w=58, ptr_len=168, hub=48, grooves=False))
    return V.ICON_OPEN + V.HEAD.format(gold=defs, art=art) + V.ICON_CLOSE


# ---------------------------------------------------------- word mark ------
def build_mark():
    """transparent background; gold ticks read on both light and dark hosts"""
    pad = 22
    half = TICK_R + 12 + pad
    size = half * 2
    defs = KNOB_RADIAL + POINTER_GRAD
    art = _ticks(major_op=1.0, minor_op=0.45) + "\n  " + _body()
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="{CX-half:.0f} {CY-half:.0f} {size} {size}">\n<defs>{defs}</defs>\n{art}\n</svg>\n')


def build_mono(color="#F5F5F7"):
    pad = 22
    half = TICK_R + 12 + pad
    size = half * 2
    art = []
    for i in range(N_TICKS):
        a = math.radians(-TICK_SPAN / 2 + TICK_SPAN * i / (N_TICKS - 1))
        tx, ty = CX + TICK_R * math.cos(a), CY + TICK_R * math.sin(a)
        major = (i % 3 == 0)
        art.append(f'<circle cx="{tx:.1f}" cy="{ty:.1f}" r="{12 if major else 7}" '
                   f'fill="{color}" fill-opacity="{0.95 if major else 0.38}"/>')
    art.append(f'<circle cx="{CX}" cy="{CY}" r="{R_BODY}" fill="none" stroke="{color}" stroke-width="26"/>')
    art.append(f'<circle cx="{CX}" cy="{CY}" r="{R_BODY-40}" fill="none" stroke="{color}" '
               f'stroke-opacity="0.30" stroke-width="4"/>')
    art.append(f'<g transform="rotate({POINTER_DEG} {CX:.0f} {CY:.0f})">'
               f'<rect x="{CX-PTR_W/2:.0f}" y="{CY-PTR_LEN:.0f}" width="{PTR_W}" height="{PTR_LEN}" '
               f'rx="{PTR_W/2:.0f}" fill="{color}"/></g>')
    art.append(f'<circle cx="{CX}" cy="{CY}" r="{HUB}" fill="{color}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="{CX-half:.0f} {CY-half:.0f} {size} {size}">\n' + "\n  ".join(art) + "\n</svg>\n")


if __name__ == "__main__":
    open(os.path.join(V.OUT, "f_icon.svg"), "w").write(build_icon())
    open(os.path.join(V.OUT, "f_small.svg"), "w").write(build_small_icon())
    open(os.path.join(V.OUT, "f_mark.svg"), "w").write(build_mark())
    open(os.path.join(V.OUT, "f_mono.svg"), "w").write(build_mono())
    print("final set written")
