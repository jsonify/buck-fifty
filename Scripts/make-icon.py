#!/usr/bin/env python3
"""Draws the Buck Fifty logo: an SK-1 chassis with the olive LCD reading 1.50 and the orange check key.

Writes SVGs (light, dark, tinted) to the folder given; Scripts/render-icon.js turns them into the 1024 px PNGs in
App/Assets.xcassets/AppIcon.appiconset. Colours are SK1Kit's tokens (SK1Tokens/SK1.swift).

    python3 Scripts/make-icon.py build/icon && node Scripts/render-icon.js build/icon build/icon
    cp build/icon/icon-light.png App/Assets.xcassets/AppIcon.appiconset/AppIcon.png   # and -Dark, -Tinted
"""
import os
import sys

# SK1Kit tokens.
LIGHT = dict(chassisTop="#f6f4ef", chassis="#ebe8e1", bezelTop="#d2cec4", bezelBottom="#e2ded6",
             lip="#ffffff", lipOpacity=0.9, shadow=0.16, lcd=1.0)
DARK = dict(chassisTop="#33312d", chassis="#2b2a27", bezelTop="#1d1c1a", bezelBottom="#26251f",
            lip="#ffffff", lipOpacity=0.07, shadow=0.5, lcd=0.86)
GLASS = ("#d3d9be", "#c3caad", "#b9c0a2")
LCD_INK = "#1e2318"
ORANGE_TOP, ORANGE_BOTTOM, ORANGE_SKIRT = "#ff8045", "#f2520f", "#b93a07"

# Seven segments: a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle.
DIGITS = {"0": "abcdef", "1": "bc", "5": "afgcd", "8": "abcdefg"}


def segments(x, y, w, h, t, lit):
    """Polygons for one seven-segment digit with its top left at (x, y), slanted like a calculator's."""
    slant = 0.08 * h  # how far the top leans right
    def sk(px, py):  # shear: higher points move right
        return (px + slant * (1 - (py - y) / h), py)
    m = y + h / 2
    g = t * 0.18  # gap between segments
    half = t / 2
    def hseg(cy):
        x0, x1 = x + g + half, x + w - g - half
        return [(x0 - half, cy), (x0, cy - half), (x1, cy - half), (x1 + half, cy), (x1, cy + half), (x0, cy + half)]
    def vseg(cx, y0, y1):
        y0, y1 = y0 + g + half, y1 - g - half
        return [(cx, y0 - half), (cx + half, y0), (cx + half, y1), (cx, y1 + half), (cx - half, y1), (cx - half, y0)]
    shapes = {
        "a": hseg(y + half), "g": hseg(m), "d": hseg(y + h - half),
        "f": vseg(x + half, y + half, m), "b": vseg(x + w - half, y + half, m),
        "e": vseg(x + half, m, y + h - half), "c": vseg(x + w - half, m, y + h - half),
    }
    out = []
    for name, pts in shapes.items():
        pts = [sk(*p) for p in pts]
        d = " ".join(f"{px:.1f},{py:.1f}" for px, py in pts)
        out.append((name in lit, d))
    return out


def svg(theme, tinted=False):
    p = theme
    s = []
    s.append('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">')
    s.append(f"""<defs>
  <linearGradient id="chassis" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{p['chassisTop']}"/><stop offset="1" stop-color="{p['chassis']}"/></linearGradient>
  <linearGradient id="bezel" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{p['bezelTop']}"/><stop offset="1" stop-color="{p['bezelBottom']}"/></linearGradient>
  <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{GLASS[0]}"/><stop offset="0.5" stop-color="{GLASS[1]}"/>
    <stop offset="1" stop-color="{GLASS[2]}"/></linearGradient>
  <linearGradient id="key" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{ORANGE_TOP}"/><stop offset="1" stop-color="{ORANGE_BOTTOM}"/></linearGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.35"/><stop offset="0.55" stop-color="#ffffff" stop-opacity="0"/></linearGradient>
  <filter id="inner" x="-10%" y="-10%" width="120%" height="120%">
    <feOffset dy="10"/><feGaussianBlur stdDeviation="9" result="b"/>
    <feComposite in="SourceGraphic" in2="b" operator="arithmetic" k2="-1" k3="1" result="i"/>
    <feFlood flood-color="#000" flood-opacity="{0.28 + p['shadow'] * 0.4}"/>
    <feComposite in2="i" operator="in"/><feComposite in2="SourceGraphic" operator="in"/></filter>
  <filter id="drop" x="-20%" y="-20%" width="140%" height="160%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="18"/>
    <feComponentTransfer><feFuncA type="linear" slope="{0.35 + p['shadow']}"/></feComponentTransfer>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>""")
    # Chassis, full bleed (iOS rounds the corners).
    s.append('<rect width="1024" height="1024" fill="url(#chassis)"/>')

    # The sunken bezel and the LCD glass.
    bx, by, bw, bh, br = 96, 150, 832, 392, 64
    s.append(f'<rect x="{bx}" y="{by + 4}" width="{bw}" height="{bh}" rx="{br}" fill="{p["lip"]}" '
             f'fill-opacity="{p["lipOpacity"]}"/>')
    s.append(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="{br}" fill="url(#bezel)"/>')
    s.append(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="{br}" fill="#000" filter="url(#inner)" opacity="0.9"/>')
    gx, gy, gw, gh, gr = bx + 30, by + 30, bw - 60, bh - 60, 38
    s.append(f'<g opacity="{p["lcd"]}">')
    s.append(f'<rect x="{gx}" y="{gy}" width="{gw}" height="{gh}" rx="{gr}" fill="url(#glass)"/>')
    s.append(f'<rect x="{gx}" y="{gy}" width="{gw}" height="{gh}" rx="{gr}" fill="#000" filter="url(#inner)" opacity="0.6"/>')

    # 1.50 on the glass, with the unlit segments faintly showing, as on a real LCD.
    dh, dw, t = 236, 132, 30
    gap = 40
    dot = 46
    total = 3 * dw + 2 * gap + dot
    x0 = gx + (gw - total) / 2 - 10
    y0 = gy + (gh - dh) / 2
    xs = [x0, x0 + dw + gap + dot, x0 + 2 * (dw + gap) + dot]
    for ch, x in zip("150", xs):
        for lit, d in segments(x, y0, dw, dh, t, DIGITS[ch]):
            op = 0.92 if lit else 0.045
            s.append(f'<polygon points="{d}" fill="{LCD_INK}" fill-opacity="{op}"/>')
    # Decimal point.
    s.append(f'<rect x="{x0 + dw + gap / 2 + 2:.1f}" y="{y0 + dh - t:.1f}" width="{t}" height="{t}" rx="4" '
             f'fill="{LCD_INK}" fill-opacity="0.92"/>')
    s.append('</g>')

    # The orange key, raised on its skirt, with a check.
    kx, ky, kw, kh, kr = 232, 640, 560, 236, 56
    skirt = 22
    s.append('<g filter="url(#drop)">')
    s.append(f'<rect x="{kx}" y="{ky + skirt}" width="{kw}" height="{kh}" rx="{kr}" fill="{ORANGE_SKIRT}"/>')
    s.append(f'<rect x="{kx}" y="{ky}" width="{kw}" height="{kh}" rx="{kr}" fill="url(#key)"/>')
    s.append('</g>')
    s.append(f'<rect x="{kx + 6}" y="{ky + 6}" width="{kw - 12}" height="{kh - 12}" rx="{kr - 6}" fill="url(#sheen)"/>')
    cx, cy = kx + kw / 2, ky + kh / 2 + 4
    s.append(f'<path d="M {cx - 82} {cy + 2} L {cx - 22} {cy + 58} L {cx + 92} {cy - 62}" fill="none" '
             f'stroke="#ffffff" stroke-width="40" stroke-linecap="round" stroke-linejoin="round"/>')
    s.append('</svg>')
    out = "\n".join(s)
    if tinted:
        # iOS tints a greyscale icon on black: drop the colour and the chassis.
        out = out.replace('<rect width="1024" height="1024" fill="url(#chassis)"/>',
                          '<rect width="1024" height="1024" fill="#000"/>')
        out = out.replace("<svg ", '<svg style="filter: grayscale(1)" ', 1)
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, text in (("light", svg(LIGHT)), ("dark", svg(DARK)), ("tinted", svg(DARK, tinted=True))):
        with open(os.path.join(out, f"icon-{name}.svg"), "w") as f:
            f.write(text + "\n")


if __name__ == "__main__":
    main()
