#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generate the default 800x1280 boot splash (raw XRGB8888, little-endian BGRX bytes).

A dark blue vertical gradient with the title drawn in the Terminus 16x32 font from
font16x32.h (scaled up). Uses only the Python standard library.

Usage: gen-splash.py font16x32.h out.bgrx [title] [subtitle]
"""
import re
import sys

W, H = 800, 1280


def load_font(path):
    data = re.findall(r'0x([0-9a-fA-F]{2})', open(path).read().split('{', 1)[1])
    return bytes(int(b, 16) for b in data)


def draw_text(px, font, text, cy, scale, color):
    width = len(text) * 16 * scale
    x0 = (W - width) // 2
    y0 = cy - 16 * scale
    for n, ch in enumerate(text.encode('latin-1')):
        glyph = font[ch * 64:(ch + 1) * 64]
        for row in range(32):
            bits = (glyph[row * 2] << 8) | glyph[row * 2 + 1]
            for col in range(16):
                if bits & (0x8000 >> col):
                    for dy in range(scale):
                        y = y0 + row * scale + dy
                        base = y * W + x0 + (n * 16 + col) * scale
                        for dx in range(scale):
                            px[base + dx] = color


def main():
    font = load_font(sys.argv[1])
    title = sys.argv[3] if len(sys.argv) > 3 else 'Fire HD 8'
    subtitle = sys.argv[4] if len(sys.argv) > 4 else 'Linux'
    px = []
    for y in range(H):
        t = y / (H - 1)
        r, g, b = int(14 + 10 * t), int(24 + 30 * t), int(46 + 60 * t)
        px.extend([(r, g, b)] * W)
    draw_text(px, font, title, H // 2 - 40, 3, (235, 240, 250))
    draw_text(px, font, subtitle, H // 2 + 50, 2, (150, 185, 235))
    with open(sys.argv[2], 'wb') as f:
        f.write(b''.join(bytes((b, g, r, 0)) for r, g, b in px))


if __name__ == '__main__':
    main()
