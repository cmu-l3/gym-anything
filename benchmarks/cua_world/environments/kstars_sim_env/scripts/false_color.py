#!/usr/bin/env python3
"""Apply false color / enhancement processing to a sky view capture.

Takes a sky image (from hips2fits API or KStars export) and applies
astrophotography-style processing to make it visually spectacular:
- Enhance contrast and dynamic range with asinh stretch
- Boost color saturation
- Apply a false color palette
- Produce a social-media-ready astronomical image

Usage:
    python3 false_color.py <input.png> <output.png> [--palette PALETTE]

Palettes: enhanced, hubble, narrowband, heat, cool, vibrant
"""
import sys
import os
import argparse
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter


def _to_float(img_array):
    """Convert image array to float64 [0,1]."""
    if img_array.ndim == 2:
        return img_array.astype(np.float64) / 255.0
    # Handle RGBA by dropping alpha
    if img_array.shape[2] == 4:
        img_array = img_array[:, :, :3]
    return img_array.astype(np.float64) / 255.0


def _asinh_stretch(arr, factor=5.0):
    """Apply asinh stretch to reveal faint features."""
    return np.arcsinh(arr * factor) / np.arcsinh(factor)


def _is_colored(img_float):
    """Check if image has meaningful color (not grayscale)."""
    if img_float.ndim == 2:
        return False
    r, g, b = img_float[:,:,0], img_float[:,:,1], img_float[:,:,2]
    # Compare channel variance — colored images have different channels
    diff = np.std(r - g) + np.std(g - b) + np.std(r - b)
    return diff > 0.02


def enhanced_palette(img_array):
    """Enhance natural colors — boost saturation, contrast, stretch faint details."""
    img = _to_float(img_array)

    if _is_colored(img):
        # For colored images: preserve hue, stretch luminance, boost saturation
        r, g, b = img[:,:,0], img[:,:,1], img[:,:,2]

        # Luminance
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        lum_stretched = _asinh_stretch(lum, 3.0)

        # Scale each channel by the stretch ratio (preserves color)
        scale = np.where(lum > 1e-6, lum_stretched / lum, 1.0)
        r_out = np.clip(r * scale, 0, 1)
        g_out = np.clip(g * scale, 0, 1)
        b_out = np.clip(b * scale, 0, 1)

        # Boost saturation
        lum2 = 0.2126 * r_out + 0.7152 * g_out + 0.0722 * b_out
        sat_boost = 1.5
        r_out = np.clip(lum2 + sat_boost * (r_out - lum2), 0, 1)
        g_out = np.clip(lum2 + sat_boost * (g_out - lum2), 0, 1)
        b_out = np.clip(lum2 + sat_boost * (b_out - lum2), 0, 1)

        rgb = np.stack([r_out, g_out, b_out], axis=-1)
    else:
        # Grayscale: apply blue-white star field look
        gray = np.mean(img, axis=2) if img.ndim == 3 else img
        stretched = _asinh_stretch(gray, 5.0)
        r = np.clip(stretched ** 0.9, 0, 1)
        g = np.clip(stretched ** 0.95, 0, 1)
        b = np.clip(stretched ** 0.7, 0, 1)
        rgb = np.stack([r, g, b], axis=-1)

    return (rgb * 255).astype(np.uint8)


def hubble_palette(img_array):
    """Hubble Heritage-style: warm gold highlights, cool blue shadows."""
    img = _to_float(img_array)

    if _is_colored(img):
        r, g, b = img[:,:,0], img[:,:,1], img[:,:,2]
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        lum_s = _asinh_stretch(lum, 4.0)

        # Warm up highlights, cool down shadows
        # Red: boost in bright areas
        r_out = np.clip(lum_s * 1.1 + (r - lum) * 1.3, 0, 1)
        # Green: slightly enhanced mid-tones
        g_out = np.clip(lum_s * 0.85 + (g - lum) * 1.2, 0, 1)
        # Blue: boost in dark areas (cold shadows), reduce in highlights
        blue_boost = np.where(lum_s < 0.3, 1.4, 0.9)
        b_out = np.clip(lum_s * 0.8 * blue_boost + (b - lum) * 1.5, 0, 1)

        rgb = np.stack([r_out, g_out, b_out], axis=-1)
    else:
        gray = np.mean(img, axis=2) if img.ndim == 3 else img
        stretched = _asinh_stretch(gray, 5.0)
        r = np.clip(stretched ** 0.7, 0, 1)
        g = np.clip(stretched ** 1.0 * 0.8, 0, 1)
        b = np.clip(stretched ** 1.5 + 0.1 * stretched, 0, 1)
        rgb = np.stack([r, g, b], axis=-1)

    return (rgb * 255).astype(np.uint8)


def narrowband_palette(img_array):
    """SHO (Hubble) narrowband palette — remaps RGB channels.

    Maps: Red→SII (gold/red), Green→Ha (green), Blue→OIII (blue/teal)
    This creates the iconic Hubble "Pillars of Creation" look.
    """
    img = _to_float(img_array)

    if _is_colored(img):
        r, g, b = img[:,:,0], img[:,:,1], img[:,:,2]

        # Stretch each channel independently
        r_s = _asinh_stretch(r, 5.0)
        g_s = _asinh_stretch(g, 5.0)
        b_s = _asinh_stretch(b, 5.0)

        # SHO mapping: remap channels for narrowband look
        # Output Red: mostly from input red (SII emission)
        r_out = np.clip(r_s * 0.8 + g_s * 0.2, 0, 1)
        # Output Green: mix of green and blue (Ha + OIII blend)
        g_out = np.clip(g_s * 0.5 + b_s * 0.4 + r_s * 0.1, 0, 1)
        # Output Blue: mostly from blue (OIII emission)
        b_out = np.clip(b_s * 0.9 + g_s * 0.15, 0, 1)

        # Boost saturation strongly
        lum = 0.2126 * r_out + 0.7152 * g_out + 0.0722 * b_out
        sat = 2.0
        r_out = np.clip(lum + sat * (r_out - lum), 0, 1)
        g_out = np.clip(lum + sat * (g_out - lum), 0, 1)
        b_out = np.clip(lum + sat * (b_out - lum), 0, 1)

        rgb = np.stack([r_out, g_out, b_out], axis=-1)
    else:
        gray = np.mean(img, axis=2) if img.ndim == 3 else img
        r_s = _asinh_stretch(gray, 5.0)
        g_s = _asinh_stretch(gray, 5.0)
        b_s = _asinh_stretch(gray, 5.0)
        r = np.clip(r_s * 1.2, 0, 1)
        g = np.clip(g_s * 0.6 + b_s * 0.3, 0, 1)
        b = np.clip(b_s * 1.1 + g_s * 0.2, 0, 1)
        rgb = np.stack([r, g, b], axis=-1)

    return (rgb * 255).astype(np.uint8)


def heat_palette(img_array):
    """Thermal/heat palette — black → red → orange → yellow → white."""
    img = _to_float(img_array)
    gray = np.mean(img, axis=2) if img.ndim == 3 else img
    stretched = _asinh_stretch(gray, 8.0)

    r = np.clip(stretched ** 0.5, 0, 1)
    g = np.clip(stretched ** 1.0 * 0.7, 0, 1)
    b = np.clip(stretched ** 2.0 * 0.3, 0, 1)

    rgb = np.stack([r, g, b], axis=-1)
    return (rgb * 255).astype(np.uint8)


def cool_palette(img_array):
    """Cool blue/cyan palette — like X-ray or UV observations."""
    img = _to_float(img_array)
    gray = np.mean(img, axis=2) if img.ndim == 3 else img
    stretched = _asinh_stretch(gray, 6.0)

    r = np.clip(stretched ** 2.0 * 0.5, 0, 1)
    g = np.clip(stretched ** 0.9 * 0.85, 0, 1)
    b = np.clip(stretched ** 0.5, 0, 1)

    rgb = np.stack([r, g, b], axis=-1)
    return (rgb * 255).astype(np.uint8)


def vibrant_palette(img_array):
    """Maximum saturation and color pop — social media optimized."""
    img = _to_float(img_array)

    if _is_colored(img):
        r, g, b = img[:,:,0], img[:,:,1], img[:,:,2]
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        lum_s = _asinh_stretch(lum, 6.0)

        scale = np.where(lum > 1e-6, lum_s / lum, 1.0)
        r_out = np.clip(r * scale, 0, 1)
        g_out = np.clip(g * scale, 0, 1)
        b_out = np.clip(b * scale, 0, 1)

        # Heavy saturation boost
        lum2 = 0.2126 * r_out + 0.7152 * g_out + 0.0722 * b_out
        sat = 2.5
        r_out = np.clip(lum2 + sat * (r_out - lum2), 0, 1)
        g_out = np.clip(lum2 + sat * (g_out - lum2), 0, 1)
        b_out = np.clip(lum2 + sat * (b_out - lum2), 0, 1)

        # Slight warm tint to highlights
        r_out = np.clip(r_out * 1.05, 0, 1)
        b_out = np.clip(b_out * 1.1, 0, 1)

        rgb = np.stack([r_out, g_out, b_out], axis=-1)
    else:
        gray = np.mean(img, axis=2) if img.ndim == 3 else img
        stretched = _asinh_stretch(gray, 10.0)
        r = np.clip(np.where(stretched > 0.5, (stretched - 0.3) * 2, stretched * 0.3), 0, 1)
        g = np.clip(np.where(stretched > 0.3, (stretched - 0.1) * 1.2, 0), 0, 1)
        b = np.clip(np.where(stretched < 0.6, stretched * 1.5, (1 - stretched) * 1.5), 0, 1)
        rgb = np.stack([r, g, b], axis=-1)

    return (rgb * 255).astype(np.uint8)


PALETTES = {
    "enhanced": enhanced_palette,
    "hubble": hubble_palette,
    "narrowband": narrowband_palette,
    "heat": heat_palette,
    "cool": cool_palette,
    "vibrant": vibrant_palette,
}


def process_image(input_path, output_path, palette_name="enhanced"):
    """Load image, apply false color, save result."""
    img = Image.open(input_path).convert("RGB")
    img_array = np.array(img)

    print(f"  Input: {img.size[0]}x{img.size[1]}, mode={img.mode}")

    palette_fn = PALETTES.get(palette_name, enhanced_palette)
    colored = palette_fn(img_array)
    result = Image.fromarray(colored)

    # Enhance contrast slightly
    result = ImageEnhance.Contrast(result).enhance(1.15)

    # Slight sharpening to bring out detail
    result = result.filter(ImageFilter.DETAIL)

    result.save(output_path, quality=95)
    print(f"  Output: {output_path} ({result.size[0]}x{result.size[1]}, palette={palette_name})")


def main():
    parser = argparse.ArgumentParser(description="Apply false color to sky capture")
    parser.add_argument("input", help="Input image (PNG from sky capture)")
    parser.add_argument("output", help="Output false color image")
    parser.add_argument("--palette", default="enhanced",
                        choices=list(PALETTES.keys()),
                        help="Color palette (default: enhanced)")
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"ERROR: Input not found: {args.input}")
        sys.exit(1)

    process_image(args.input, args.output, args.palette)


if __name__ == "__main__":
    main()
