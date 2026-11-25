"""Generate the example PNGs with Python 3's standard library."""

from pathlib import Path
import struct
import zlib


def chunk(kind, payload):
    return (
        struct.pack('>I', len(payload))
        + kind + payload
        + struct.pack('>I', zlib.crc32(kind + payload))
    )


def render(path, width, height, palette):
    sky, sun, far, near = (bytes(color) for color in palette)
    # Work in normalized integer coordinates so regeneration needs no RNG,
    # fonts, or platform-specific drawing libraries.
    xs = [x * 1000 // width for x in range(width)]
    peaks = [510 + abs(x - 310) * 3 // 5 for x in xs]
    ridges = [635 + abs(x - 735) // 2 for x in xs]
    rows = bytearray()
    for row in range(height):
        y = row * 1000 // height
        rows.append(0)  # PNG scanline filter: none.
        for x, peak, ridge in zip(xs, peaks, ridges):
            in_sun = (x - 650) ** 2 * width**2 + (y - 405) ** 2 * height**2
            if y >= min(ridge, 785 - x // 8):
                rows.extend(near)
            elif y >= peak:
                rows.extend(far)
            elif in_sun <= (min(width, height) * 105) ** 2:
                rows.extend(sun)
            else:
                rows.extend(sky)
    header = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header)
        + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')
    )


if __name__ == '__main__':
    assets = Path(__file__).resolve().parents[1] / 'assets'
    assets.mkdir(exist_ok=True)
    render(assets / 'landscape.png', 2400, 1600, (
        (178, 225, 220), (255, 187, 82), (57, 139, 134), (21, 78, 82),
    ))
    render(assets / 'portrait.png', 1600, 2400, (
        (230, 214, 243), (236, 130, 180), (126, 100, 172), (62, 44, 112),
    ))
