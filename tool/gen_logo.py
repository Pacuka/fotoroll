#!/usr/bin/env python3
"""Generates assets/branding/fotoroll.svg (film reel in the Immich palette).
Usage: python3 tool/gen_logo.py assets/branding/fotoroll.svg
       rsvg-convert -w 512 assets/branding/fotoroll.svg -o assets/branding/fotoroll.png"""
import math, sys
out = sys.argv[1]
C = 256
cols = ['#FA2921', '#FFB400', '#18C249', '#1E83F7', '#ED79B5']  # immich palette, clockwise
R1, R2, half = 84, 196, 26  # inner/outer radius, half-angle of each window (deg)
def pt(r, a):
    a = math.radians(a)
    return C + r * math.cos(a), C + r * math.sin(a)
parts = []
holes = []
for i, col in enumerate(cols):
    mid = -90 + i * 72 + 8  # slight twist, like a spinning reel
    a1, a2 = mid - half, mid + half
    o1, o2 = pt(R2, a1), pt(R2, a2)
    i2, i1 = pt(R1, a2), pt(R1, a1)
    d = (f"M{o1[0]:.1f},{o1[1]:.1f} A{R2},{R2} 0 0 1 {o2[0]:.1f},{o2[1]:.1f} "
         f"L{i2[0]:.1f},{i2[1]:.1f} A{R1},{R1} 0 0 0 {i1[0]:.1f},{i1[1]:.1f} Z")
    parts.append(f'<path d="{d}" fill="{col}" stroke="{col}" stroke-width="30" stroke-linejoin="round"/>')
    for k in (-1, 0, 1):  # film perforations along the outer edge
        a = mid + k * 15
        x, y = pt(R2 - 4, a)
        holes.append(f'<rect x="{x-10:.1f}" y="{y-5.5:.1f}" width="20" height="11" rx="3" transform="rotate({a+90:.1f} {x:.1f} {y:.1f})" fill="black"/>')
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs><mask id="m"><rect width="512" height="512" fill="white"/>{''.join(holes)}</mask><mask id="h"><rect width="512" height="512" fill="white"/><circle cx="{C}" cy="{C}" r="16" fill="black"/></mask></defs>
  <g mask="url(#m)">{''.join(parts)}</g>
  <circle cx="{C}" cy="{C}" r="42" fill="#7A6FF0" mask="url(#h)"/>
</svg>
'''
open(out, 'w').write(svg)
