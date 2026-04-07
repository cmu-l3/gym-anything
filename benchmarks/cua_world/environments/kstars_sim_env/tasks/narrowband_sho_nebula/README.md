# Task: narrowband_sho_nebula

## Overview

**Difficulty:** very_hard
**Occupation:** Astrophotographer (advanced amateur / professional)
**Industry:** Astrophotography / Scientific Imaging
**Environment:** kstars_sim_env (KStars + INDI Simulators)

A narrowband emission nebula imaging session has been scheduled for **NGC 7000 (North America Nebula)** in Cygnus. The agent must read the imaging plan, discover the target coordinates and filter assignments, execute the full SHO (Sulfur-Hydrogen-Oxygen) narrowband filter sequence with separate upload directories per filter, and produce a final false-color composite image using the Hubble palette.

## What Makes This Very Hard

1. **No step-by-step instructions** — only the imaging plan document
2. **Agent must identify NGC 7000 coordinates** (RA 20h 58m 47s, Dec +44° 20' 02")
3. **Agent must manage 3 different filter slots** (Ha=5, OIII=6, SII=4) with different upload dirs per filter
4. **Agent must switch upload directories** between filter sets to maintain separate storage
5. **Agent must produce a false-color composite** using `false_color.py --palette narrowband`
6. **Telescope starts at wrong target** (M57 Ring Nebula)

## Real Data

- **NGC 7000** is a real H-alpha emission nebula in Cygnus, one of the most popular targets for narrowband astrophotography due to its distinctive North America continental shape
- **SHO palette** (Hubble palette) is the real narrowband mapping used in professional astronomical imaging, most famously in the Hubble Space Telescope "Pillars of Creation" image
- **H-alpha (656nm), OIII (500nm), SII (672nm)** are real nebular emission lines from ionized hydrogen, doubly-ionized oxygen, and singly-ionized sulfur respectively
- CCD star fields rendered from real Hubble GSC catalog data

## Verification Criteria (100 pts, pass ≥ 60)

| Criterion | Points | Details |
|-----------|--------|---------|
| Ha frames | 20 | ≥5 valid FITS in `narrowband/Ha/`, created during task |
| OIII frames | 20 | ≥5 valid FITS in `narrowband/OIII/`, created during task |
| SII frames | 15 | ≥5 valid FITS in `narrowband/SII/`, created during task |
| Telescope at NGC 7000 | 20 | Final position within 30 arcmin of RA 20.979h, Dec +44.334° |
| SHO composite | 25 | `/home/ga/Images/ngc7000/composite_sho.png` created via `false_color.py --palette narrowband` |

## Anti-Gaming Protections

- Task start time recorded; all FITS files and composite must have `mtime > task_start`
- Telescope slewed to M57 at start (Ring Nebula — similar size but entirely different location)
- Composite size checked (>50KB required for a real image)
- Filter assignments not obvious — agent must read the imaging plan to learn Ha=slot5, OIII=slot6, SII=slot4
