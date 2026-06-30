#!/usr/bin/env python3
"""Generate a traffic light icon for Cloud Code Light."""
import subprocess, os, struct

def create_icon():
    """Create a simple traffic light .icns using only macOS built-in tools."""

    # First create a simple PNG using sips and a base image approach
    # We'll create a 512x512 PNG using Python's built-in modules

    size = 512
    # Create raw RGBA pixel data
    pixels = bytearray(size * size * 4)

    def set_pixel(x, y, r, g, b, a=255):
        if 0 <= x < size and 0 <= y < size:
            idx = (y * size + x) * 4
            pixels[idx] = r
            pixels[idx+1] = g
            pixels[idx+2] = b
            pixels[idx+3] = a

    def dist(x1, y1, x2, y2):
        return ((x1-x2)**2 + (y1-y2)**2) ** 0.5

    # Draw rounded rectangle body (dark background)
    body_left, body_top = 130, 40
    body_right, body_bottom = 382, 480
    corner_r = 40
    body_color = (52, 56, 61)

    for y in range(size):
        for x in range(size):
            # Check if inside rounded rect
            inside = False
            if body_left + corner_r <= x <= body_right - corner_r and body_top <= y <= body_bottom:
                inside = True
            elif body_left <= x <= body_right and body_top + corner_r <= y <= body_bottom - corner_r:
                inside = True
            else:
                # Check corners
                for cx, cy in [(body_left+corner_r, body_top+corner_r),
                               (body_right-corner_r, body_top+corner_r),
                               (body_left+corner_r, body_bottom-corner_r),
                               (body_right-corner_r, body_bottom-corner_r)]:
                    if dist(x, y, cx, cy) <= corner_r:
                        if body_left <= x <= body_right and body_top <= y <= body_bottom:
                            inside = True
                            break

            if inside:
                set_pixel(x, y, *body_color)

    # Draw three circles (lights)
    cx = 256  # center x
    lights = [
        (110, (243, 66, 59)),    # red
        (256, (255, 212, 65)),   # yellow
        (402, (85, 211, 77)),    # green
    ]

    for ly, (lr, lg, lb) in lights:
        for y in range(max(0, ly-65), min(size, ly+65)):
            for x in range(max(0, cx-65), min(size, cx+65)):
                d = dist(x, y, cx, ly)
                if d <= 48:
                    # Main circle
                    set_pixel(x, y, lr, lg, lb)
                elif d <= 55:
                    # Rim
                    alpha = int(255 * (1 - (d - 48) / 7))
                    set_pixel(x, y, lr, lg, lb, alpha)
                # Specular highlight
                if d <= 20 and y < ly - 10 and abs(x - cx) < 15:
                    set_pixel(x, y, 255, 255, 255, 180)

    # Write as PNG manually
    def write_png(filename, width, height, pixels):
        import zlib
        def chunk(chunk_type, data):
            c = chunk_type + data
            return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

        raw = b''
        for y in range(height):
            raw += b'\x00'  # filter byte
            row_start = y * width * 4
            raw += bytes(pixels[row_start:row_start + width * 4])

        compressed = zlib.compress(raw)

        with open(filename, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n')
            f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)))
            f.write(chunk(b'IDAT', compressed))
            f.write(chunk(b'IEND', b''))

    png_path = os.path.join(os.path.dirname(__file__), 'icon_512.png')
    write_png(png_path, size, size, pixels)
    print(f"Created {png_path}")

    # Convert to .icns using iconutil
    iconset_dir = os.path.join(os.path.dirname(__file__), 'AppIcon.iconset')
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [16, 32, 64, 128, 256, 512]
    for s in sizes:
        out = os.path.join(iconset_dir, f'icon_{s}x{s}.png')
        subprocess.run(['sips', '-z', str(s), str(s), png_path, '--out', out], check=True, capture_output=True)
        if s * 2 <= 1024:
            out2 = os.path.join(iconset_dir, f'icon_{s}x{s}@2x.png')
            subprocess.run(['sips', '-z', str(s*2), str(s*2), png_path, '--out', out2], check=True, capture_output=True)

    icns_path = os.path.join(os.path.dirname(__file__), 'AppIcon.icns')
    subprocess.run(['iconutil', '-c', 'icns', iconset_dir, '-o', icns_path], check=True, capture_output=True)
    print(f"Created {icns_path}")

    # Cleanup
    import shutil
    shutil.rmtree(iconset_dir)
    os.remove(png_path)

    return icns_path

if __name__ == '__main__':
    create_icon()
