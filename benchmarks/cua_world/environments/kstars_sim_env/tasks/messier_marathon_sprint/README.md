# Messier Marathon Sprint (`messier_marathon_sprint@1`)

## Overview

**Difficulty:** very_hard
**Occupation:** Amateur Astronomer / Observational Astronomer
**Industry:** Observational Astronomy / Amateur Astronomy Community
**Environment:** kstars_sim_env (KStars + INDI Simulators)

The annual Messier Marathon is one of the most beloved traditions in amateur astronomy — attempting to observe all 110 Messier objects in a single night near the spring equinox. This task simulates a **sprint variant**: the agent receives a target sheet listing 6 diverse Messier objects spanning the sky, each requiring specific filter configurations, exposure counts, and organized file storage. The agent must efficiently slew between targets, configure the CCD and filter wheel for each, capture the required frames, and produce a structured observation log. This tests the fundamental observatory workflow of **multi-target queue execution** — the bread-and-butter of every observing night.

## What Makes This Very Hard

1. **No step-by-step instructions** — only the marathon target sheet document
2. **Agent must manage 6 distinct telescope pointings** with correct RA/Dec for each Messier object
3. **Agent must switch between 3 different filters** (V=slot 2, R=slot 4, Ha=slot 5) depending on target type
4. **Agent must create and manage 6 separate upload directories** — one per target
5. **Agent must match exposure times to the target sheet** (varying from 30s to 90s)
6. **Anti-gaming**: 2 stale FITS files pre-seeded in the M13 directory from a "previous session"
7. **Telescope starts pointed at Polaris** (RA ~2.53h, Dec +89.26°) — far from all targets
8. **Agent must produce a structured observation log** summarizing all targets observed

## Real Data

All targets are real Messier objects from Charles Messier's 1781 catalog:

| # | Target | Type | RA (J2000) | Dec (J2000) | Constellation | Filter | Exp | Frames |
|---|--------|------|------------|-------------|---------------|--------|-----|--------|
| 1 | M1 (Crab Nebula) | Supernova Remnant | 05h 34m 31.9s | +22° 00' 52" | Taurus | Ha (slot 5) | 60s | ≥2 |
| 2 | M13 (Great Globular Cluster) | Globular Cluster | 16h 41m 41.6s | +36° 27' 41" | Hercules | V (slot 2) | 30s | ≥3 |
| 3 | M27 (Dumbbell Nebula) | Planetary Nebula | 19h 59m 36.3s | +22° 43' 16" | Vulpecula | Ha (slot 5) | 45s | ≥2 |
| 4 | M51 (Whirlpool Galaxy) | Spiral Galaxy | 13h 29m 52.7s | +47° 11' 43" | Canes Venatici | R (slot 4) | 60s | ≥2 |
| 5 | M57 (Ring Nebula) | Planetary Nebula | 18h 53m 35.1s | +33° 01' 45" | Lyra | Ha (slot 5) | 45s | ≥2 |
| 6 | M101 (Pinwheel Galaxy) | Spiral Galaxy | 14h 03m 12.6s | +54° 20' 57" | Ursa Major | V (slot 2) | 90s | ≥2 |

CCD star fields are rendered from real Hubble Guide Star Catalog (GSC) data.

## Task Workflow (What the Agent Must Do)

1. Read `~/Documents/marathon_targets.txt` to learn all target coordinates, filters, and exposure requirements
2. For each of the 6 targets in order:
   a. Slew telescope to the target coordinates
   b. Set the correct filter wheel slot
   c. Set the CCD upload directory to `/home/ga/Images/marathon/<target_name>/`
   d. Take the required number of LIGHT exposures at the specified duration
3. After completing all targets, capture a sky view of the final target (M101): `bash ~/capture_sky_view.sh ~/Images/marathon/sky_view_m101.png`
4. Write an observation log to `/home/ga/Documents/marathon_log.txt` containing each target name.

## Error Injection Details

Two stale FITS files are pre-seeded in the M13 directory to simulate leftover data from a previous observing run:
- `/home/ga/Images/marathon/M13/old_m13_001.fits` (0 bytes, mtime 2024-01-15)
- `/home/ga/Images/marathon/M13/old_m13_002.fits` (0 bytes, mtime 2024-01-15)

These must NOT count toward the required ≥3 frames for M13. The verifier only counts files with `mtime > task_start` and `size > 0`.

## Verification Criteria (100 pts, pass ≥ 60)

| Criterion | Points | Details |
|-----------|--------|---------|
| M1 images | 12 | ≥2 valid FITS in `marathon/M1/`, created during task, size >0 |
| M13 images | 12 | ≥3 NEW valid FITS in `marathon/M13/` (stale files excluded) |
| M27 images | 12 | ≥2 valid FITS in `marathon/M27/`, created during task |
| M51 images | 12 | ≥2 valid FITS in `marathon/M51/`, created during task |
| M57 images | 12 | ≥2 valid FITS in `marathon/M57/`, created during task |
| M101 images | 12 | ≥2 valid FITS in `marathon/M101/`, created during task |
| Log exists | 10 | `/home/ga/Documents/marathon_log.txt` exists |
| Log content | 8 | Log mentions all 6 target names |
| Sky view | 10 | `sky_view_m101.png` exists, >50KB, mtime > task_start |