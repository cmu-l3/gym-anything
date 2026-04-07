# Task: photometric_standard_calibration

## Overview

**Difficulty:** very_hard
**Occupation:** Observatory Technician / Research Astronomer
**Industry:** Observatory Operations / Photometric Calibration
**Environment:** kstars_sim_env (KStars + INDI Simulators)

The observatory's CCD photometric calibration is overdue before a science observing run. The agent must read a specification document left by the PI, identify the **Landolt standard star field SA 98**, configure the filter wheel to observe in B, V, and R bands sequentially, capture the required images, and produce a calibration catalog file for the downstream reduction pipeline.

## What Makes This Very Hard

1. **No step-by-step instructions** — only the goal and spec document location
2. **Agent must identify SA 98 field coordinates** from the spec (RA 06h 51m 36s, Dec −00° 17')
3. **Agent must manage three different filter configurations** (B=slot3, V=slot2, R=slot4) sequentially
4. **Agent must switch upload directory** to the correct path before imaging each filter
5. **Agent must produce a structured calibration catalog** in the specified format
6. **Telescope starts at wrong target** (M42/Orion area)

## Real Data

- **SA 98** is a real Landolt standard star field widely used for CCD photometric calibration in professional astronomy (Landolt 1992, AJ 104, 340)
- **HD 49798** is a real hot subdwarf O star (sdO6) in the field
- The BVR photometric system (Bessell/Johnson) is the real standard for optical astronomy
- CCD star fields rendered from real Hubble Guide Star Catalog (GSC) data

## Verification Criteria (100 pts, pass ≥ 60)

| Criterion | Points | Details |
|-----------|--------|---------|
| B-band images | 20 | ≥5 valid FITS with FILTER=B, created during task |
| V-band images | 20 | ≥5 valid FITS with FILTER=V, created during task |
| R-band images | 20 | ≥5 valid FITS with FILTER=R, created during task |
| Telescope at SA 98 | 20 | Final position within 30 arcmin of RA 6.86h, Dec −0.283° |
| Calibration catalog | 20 | `/home/ga/Images/photcal/sa98/calibration_catalog.txt` with all 3 filters listed |

## Anti-Gaming Protections

- Task start time recorded; all FITS files must have `mtime > task_start`
- Telescope slewed to M42 at task start to prevent reuse of pre-slewed position
- Calibration catalog mtime checked against task start
