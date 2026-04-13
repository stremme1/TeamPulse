#!/usr/bin/env python3
"""
Generate TeamPulse app icons using raw Python pixel buffers and manual PNG encoding.
No external image libraries needed beyond stdlib + zlib.

Icon design:
- Dark rounded-square background (#1C1C1E)
- Three concentric activity rings (Move=red, Exercise=green, Stand=blue)
- Centered pulsing ECG/pulse line in white
- Clean, bold, Apple Fitness-inspired aesthetic
"""

import struct, zlib, math, os

# ── Color Palette ──────────────────────────────────────────────────────────

BG_COLOR      = (28, 28, 30, 255)
RING_MOVE     = (255, 59, 48, 255)
RING_EXERCISE = (50, 215, 75, 255)
RING_STAND    = (10, 132, 255, 255)
WHITE         = (255, 255, 255, 255)
SHADOW        = (0, 0, 0, 80)

# ── Output dirs ─────────────────────────────────────────────────────────────

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Script lives in ios/ — ROOT_DIR is the ios folder itself
ROOT_DIR   = SCRIPT_DIR
IPHONE_DIR = os.path.join(ROOT_DIR, "WorkoutSync", "Assets.xcassets", "AppIcon.appiconset")
WATCH_DIR  = os.path.join(ROOT_DIR, "WatchWorkout", "Assets.xcassets", "AppIcon.appiconset")


# ── Pixel Buffer ───────────────────────────────────────────────────────────

class PixelBuffer:
    """Row-major RGBA pixel buffer with premultiplied alpha blending."""

    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.pixels = [[0, 0, 0, 0] for _ in range(w * h)]

    def _idx(self, x, y):
        return y * self.w + x

    def getpixel(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.pixels[self._idx(x, y)]
        return None

    def setpixel(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.pixels[self._idx(x, y)] = list(color)

    def blendpixel(self, x, y, color):
        """Blend a color onto a pixel with premultiplied alpha."""
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        dst = self.pixels[self._idx(x, y)]
        r, g, b, a = color
        da = dst[3] / 255.0
        ca = a / 255.0
        na = ca + da * (1 - ca)
        if na > 0 and na < 1.0:
            na = max(0.001, min(0.999, na))
        elif na == 0:
            return
        inv = 1.0 / na
        self.pixels[self._idx(x, y)] = [
            int((r * ca + dst[0] * da * (1 - ca)) * inv),
            int((g * ca + dst[1] * da * (1 - ca)) * inv),
            int((b * ca + dst[2] * da * (1 - ca)) * inv),
            int(na * 255 + 0.5),
        ]


# ── PNG Encoder ─────────────────────────────────────────────────────────────

def save_png(buf, filepath):
    """Save PixelBuffer as a PNG file."""
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    w, h = buf.w, buf.h
    ihdr_data = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)

    raw = b"".join(
        b"\x00" + bytes(sum(buf.pixels[y * w:(y + 1) * w], []))
        for y in range(h)
    )
    compressed = zlib.compress(raw, level=6)

    with open(filepath, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr_data))
        f.write(chunk(b"IDAT", compressed))
        f.write(chunk(b"IEND", b""))


# ── Drawing Primitives ─────────────────────────────────────────────────────

def fill_rounded_rect(buf, x0, y0, w, h, r, color):
    """Fill a rounded rectangle."""
    # Center rect
    for y in range(y0 + r, y0 + h - r):
        for x in range(x0, x0 + w):
            buf.blendpixel(x, y, color)
    # Top/bottom bands with semicircle ends
    for y in range(y0, y0 + r):
        dy = r - 1 - (y - y0)
        span = int(math.sqrt(max(0, r*r - dy*dy))) if dy >= 0 else r
        for x in range(x0 + r - span, x0 + w - r + span):
            buf.blendpixel(x, y, color)
    for y in range(y0 + h - r, y0 + h):
        dy = (y - (y0 + h - r))
        span = int(math.sqrt(max(0, r*r - dy*dy))) if dy >= 0 else r
        for x in range(x0 + r - span, x0 + w - r + span):
            buf.blendpixel(x, y, color)


def fill_ring_arc(buf, cx, cy, r, width, start_deg, end_deg, color):
    """Fill a thick arc (ring segment) in the pixel buffer."""
    outer_r = r + width / 2
    inner_r = max(0, r - width / 2)

    y0 = max(0, int(cy - outer_r) - 1)
    y1 = min(buf.h, int(cy + outer_r) + 2)
    x0 = max(0, int(cx - outer_r) - 1)
    x1 = min(buf.w, int(cx + outer_r) + 2)

    for y in range(y0, y1):
        for x in range(x0, x1):
            dx = x - cx
            dy = y - cy
            dist_sq = dx * dx + dy * dy
            outer_sq = (outer_r + 0.5) * (outer_r + 0.5)
            inner_sq = max(0, (inner_r - 0.5) * (inner_r - 0.5))

            if dist_sq > outer_sq or dist_sq < inner_sq:
                continue

            angle = math.degrees(math.atan2(dy, dx)) % 360
            span = (end_deg - start_deg) % 360
            s_norm = start_deg % 360
            if (angle - s_norm) % 360 >= span:
                continue

            dist = math.sqrt(dist_sq)
            alpha = 255
            if dist > r + width / 2 - 1:
                alpha = max(0, int(255 * (r + width / 2 - dist)))
            elif dist < r - width / 2 + 1:
                alpha = max(0, int(255 * (dist - (r - width / 2))))

            if alpha > 0:
                r_c, g_c, b_c, _ = color
                buf.blendpixel(x, y, (r_c, g_c, b_c, alpha))


def draw_line(buf, x1, y1, x2, y2, color, width=1):
    """Bresenham line with blend."""
    dx, dy = abs(x2 - x1), abs(y2 - y1)
    sx = 1 if x1 < x2 else -1
    sy = 1 if y1 < y2 else -1
    err = dx - dy
    x, y = x1, y1
    while True:
        buf.blendpixel(x, y, color)
        if width > 1:
            for dx2 in range(-width // 2 + 1, width // 2 + 1):
                for dy2 in range(-width // 2 + 1, width // 2 + 1):
                    if dx2 or dy2:
                        buf.blendpixel(x + dx2, y + dy2, (color[0], color[1], color[2], color[3] // 2))
        if x == x2 and y == y2:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


# ── Pulse/ECG Line Points ────────────────────────────────────────────────────

def pulse_points(cx, cy, size):
    """ECG/pulse line centered at (cx, cy)."""
    pw = size * 0.55
    ph = size * 0.18
    py = cy + size * 0.02

    raw = [
        (0.00, 0.50), (0.12, 0.50), (0.20, 0.28),
        (0.28, 0.04), (0.35, 0.28), (0.42, 0.50),
        (0.52, 0.50), (0.60, 0.35), (0.66, 0.10),
        (0.72, 0.38), (0.80, 0.50), (1.00, 0.50),
    ]
    return [
        (cx - pw / 2 + pw * p[0],
         py - ph * (p[1] - 0.5))
        for p in raw
    ]


# ── Heart Shape ─────────────────────────────────────────────────────────────

def heart_points(cx, cy, size):
    """Heart polygon points centered at (cx, cy)."""
    pts = []
    for t in range(361):
        t_rad = t / 360 * 2 * math.pi
        x = 16 * math.sin(t_rad) ** 3
        y = -(13 * math.cos(t_rad) - 5 * math.cos(2*t_rad)
              - 2 * math.cos(3*t_rad) - math.cos(4*t_rad))
        pts.append((x, y))
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    w = size * 0.42
    h = size * 0.38
    return [
        (cx + w * (p[0] - min(xs)) / (max(xs) - min(xs)) - w / 2,
         cy + h * (p[1] - min(ys)) / (max(ys) - min(ys)) - h / 2)
        for p in pts
    ]


def scanline_fill(buf, polygon, color):
    """Scanline fill using even-odd rule."""
    if not polygon:
        return
    ys = [p[1] for p in polygon]
    y_min = max(0, int(min(ys)) - 1)
    y_max = min(buf.h, int(max(ys)) + 2)

    for y in range(y_min, y_max):
        intersections = []
        n = len(polygon)
        for i in range(n):
            p1, p2 = polygon[i], polygon[(i + 1) % n]
            if abs(p1[1] - p2[1]) < 1e-9:
                continue
            if (y >= min(p1[1], p2[1])) and (y < max(p1[1], p2[1])):
                x = p1[0] + (y - p1[1]) * (p2[0] - p1[0]) / (p2[1] - p1[1])
                intersections.append(x)
        intersections.sort()
        for i in range(0, len(intersections) - 1, 2):
            x1, x2 = max(0, int(intersections[i])), min(buf.w - 1, int(intersections[i + 1]))
            for x in range(x1, x2 + 1):
                buf.blendpixel(x, y, color)


# ── Main Builder ─────────────────────────────────────────────────────────────

def create_icon(size, filepath):
    """Generate a single TeamPulse app icon."""
    buf = PixelBuffer(size, size)

    pad     = size // 8
    content = size - pad * 2
    cx      = size // 2
    cy      = size // 2
    icon_sz = content * 0.85

    # ── 1. Rounded square background ────────────────────────────────────────
    rr = size // 5
    fill_rounded_rect(buf, pad, pad, content, content, rr, BG_COLOR)

    # ── 2. Three activity rings (concentric, starting from ~3 o'clock, sweeping most of circle) ──
    stroke = max(2, size // 20)
    arc_start = 135  # Start at ~7:30 position (top-left)

    # Outer ring - Move (red)
    outer_r = icon_sz * 0.50
    fill_ring_arc(buf, cx, cy, outer_r, stroke, arc_start, arc_start + 280, RING_MOVE)

    # Middle ring - Exercise (green)
    middle_r = outer_r - stroke - max(2, size // 32)
    fill_ring_arc(buf, cx, cy, middle_r, stroke, arc_start + 20, arc_start + 20 + 240, RING_EXERCISE)

    # Inner ring - Stand (blue)
    inner_r = middle_r - stroke - max(2, size // 32)
    fill_ring_arc(buf, cx, cy, inner_r, stroke, arc_start + 40, arc_start + 40 + 200, RING_STAND)

    # ── 3. Heart shape in center ─────────────────────────────────────────────
    heart = heart_points(cx, cy + size * 0.02, icon_sz * 0.55)
    scanline_fill(buf, heart, RING_MOVE)

    # ── 4. Pulse/ECG line ────────────────────────────────────────────────────
    line = pulse_points(cx, cy + size * 0.02, icon_sz * 0.55)
    sw = max(1, size // 28)

    # Shadow pass
    shadow = [(x + 1, y + 1) for x, y in line]
    for i in range(len(shadow) - 1):
        draw_line(buf, int(shadow[i][0]), int(shadow[i][1]),
                  int(shadow[i+1][0]), int(shadow[i+1][1]), SHADOW, sw)

    # White line
    for i in range(len(line) - 1):
        draw_line(buf, int(line[i][0]), int(line[i][1]),
                  int(line[i+1][0]), int(line[i+1][1]), WHITE, sw)

    # ── 5. Save ──────────────────────────────────────────────────────────────
    save_png(buf, filepath)
    print(f"  ✓ {os.path.basename(filepath)} ({size}×{size})")


def main():
    os.makedirs(IPHONE_DIR, exist_ok=True)
    os.makedirs(WATCH_DIR, exist_ok=True)

    # iPhone icon sizes (all required iOS sizes)
    iphone = {
        "Icon-20.png":   20,   "Icon-40.png":   40,   "Icon-58.png":   58,
        "Icon-60.png":   60,   "Icon-76.png":   76,   "Icon-80.png":   80,
        "Icon-87.png":   87,   "Icon-120.png": 120,   "Icon-152.png": 152,
        "Icon-167.png": 167,   "Icon-180.png": 180,   "Icon-1024.png":1024,
    }
    print("Generating iPhone icons...")
    for name, sz in iphone.items():
        create_icon(sz, os.path.join(IPHONE_DIR, name))

    # Watch icon sizes (all required watchOS sizes)
    watch = {
        "Icon-20.png":   20,   "Icon-24.png":   24,   "Icon-27.5.png": 28,
        "Icon-29.png":   29,   "Icon-32.png":   32,   "Icon-33.png":   33,
        "Icon-36.png":   36,   "Icon-40.png":   40,   "Icon-44.png":   44,
        "Icon-46.png":   46,   "Icon-48.png":   48,   "Icon-50.png":   50,
        "Icon-51.png":   51,   "Icon-54.png":   54,   "Icon-57.png":   57,
        "Icon-60.png":   60,   "Icon-64.png":   64,   "Icon-66.png":   66,
        "Icon-76.png":   76,   "Icon-80.png":   80,   "Icon-86.png":   86,
        "Icon-87.png":   87,   "Icon-88.png":   88,   "Icon-92.png":   92,
        "Icon-98.png":   98,   "Icon-100.png": 100,   "Icon-102.png": 102,
        "Icon-108.png": 108,   "Icon-117.png": 117,   "Icon-129.png": 129,
        "Icon-132.png": 132,   "Icon-142.png": 142,   "Icon-146.png": 146,
        "Icon-152.png": 152,   "Icon-164.png": 164,   "Icon-172.png": 172,
        "Icon-176.png": 176,   "Icon-180.png": 180,   "Icon-196.png": 196,
        "Icon-216.png": 216,   "Icon-234.png": 234,   "Icon-258.png": 258,
        "Icon-1024.png":1024,
    }
    print("Generating Watch icons...")
    for name, sz in watch.items():
        create_icon(sz, os.path.join(WATCH_DIR, name))

    print("\nAll TeamPulse icons generated successfully!")


if __name__ == "__main__":
    main()
