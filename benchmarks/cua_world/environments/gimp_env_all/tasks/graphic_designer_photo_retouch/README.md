# GIMP Task: `graphic_designer_photo_retouch@1`

## Overview

**Difficulty:** very_hard
**Industry:** Graphic Design / Print Media
**Occupation:** Graphic Designers

A graphic designer performs a multi-correction professional retouch on a portrait photograph destined for a client's annual report. This is a standard workflow for print-ready portrait preparation.

## Professional Context

Graphic designers routinely retouch photography before incorporating it into print layouts. A professional retouch for an annual report portrait involves four standard corrections:

1. **Tonal range correction** — Historical or scanned portraits often have compressed tonal ranges; stretching the histogram recovers full contrast
2. **Color cast removal** — Paper yellowing, scanning, or lighting create color bias that needs correction per channel
3. **Selective sharpening** — Mid-tone detail recovery compensates for softening from scanning or compression
4. **Edge vignette** — A subtle darkened border focuses attention on the subject and is a standard design element for formal portraits

## Task Goal

Open `portrait_photo.jpg` from the Desktop in GIMP and apply all four corrections, then export as `retouched_portrait.png` on the Desktop.

## Verification Criteria

| Criterion | Weight | Description |
|-----------|--------|-------------|
| retouched_portrait.png exists | 20% | Valid PNG file on Desktop |
| Significant pixel changes | 20% | Mean pixel diff >8 or >20% pixels changed |
| Contrast improved | 20% | Histogram p95-p5 spread wider than source |
| Color correction applied | 20% | Channel mean shift >15 or channel std reduced |
| Vignette effect present | 20% | Center brightness > corner brightness by >10 |

**Pass threshold:** 80% (4/5 criteria)

## Why This Is Hard

- Requires using at minimum 4 distinct GIMP tools: Levels/Curves (tonal), individual channel curves (color), Unsharp Mask (sharpening), and a vignette technique
- Vignette in GIMP requires non-obvious multi-step approach (e.g., Script-Fu vignette, or elliptical selection + Gaussian blur + burn)
- Must apply corrections in correct order (levels before sharpening is standard practice)
- No workflow hints given — agent must know which tools to use
- Must export as PNG (not JPEG) to preserve quality

## Source Image

Real historical portrait photograph from Wikimedia Commons (public domain). The image has natural photographic characteristics typical of scanned historical prints.
