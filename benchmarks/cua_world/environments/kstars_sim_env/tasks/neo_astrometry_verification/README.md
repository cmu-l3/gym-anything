# Task: neo_astrometry_verification

## Overview

**Difficulty:** very_hard
**Occupation:** Planetary Scientist / Near-Earth Object Observer
**Industry:** Planetary Defense / Asteroid Astrometry
**Environment:** kstars_sim_env (KStars + INDI Simulators)

The Minor Planet Center has requested independent astrometric verification of near-Earth asteroid **2020 QG** — the asteroid that holds the record for the closest known flyby of Earth without impact (2,950 km in August 2020). The agent must read the observing request, slew to the correct field, take a series of CCD images, and produce an MPC-format astrometry report.

## What Makes This Very Hard

1. **No step-by-step instructions** — agent must infer the full workflow from the observing request document
2. **Agent must identify target coordinates** from the document (RA 16h 52m 58s, Dec −21° 55' 00")
3. **Agent must set up the correct CCD configuration** (Luminance filter, 30s exposures, correct upload directory)
4. **Agent must produce an MPC-format astrometry report** — a domain-specific professional format used by the real Minor Planet Center
5. **Telescope starts at wrong target** (M13 Hercules Globular Cluster)
6. **Target is in a different part of the sky** — requires navigating KStars to find the correct coordinates

## Real Data

- **2020 QG** is a real Apollo-type near-Earth asteroid discovered on 2020-08-16 by ZTF. It made the closest flyby in recorded history (2,950 km) on the same date — well within Earth's geosynchronous orbit
- **MPC format** (Minor Planet Circular format) is the real standard submission format used worldwide for asteroid astrometry
- **MPC Observatory Code 945** is Pittsburgh, PA (real code in the MPC database)
- CCD star fields rendered using Hubble GSC data

## Verification Criteria (100 pts, pass ≥ 60)

| Criterion | Points | Details |
|-----------|--------|---------|
| FITS images | 25 | ≥6 valid FITS in `/home/ga/Images/asteroids/2020QG/`, created during task |
| Telescope at target | 25 | Final position within 2° of RA 16.883h, Dec −21.917° |
| MPC report created | 20 | `/home/ga/Documents/mpc_report.txt` created during task |
| Report names 2020 QG | 15 | Report text contains "2020 QG" designation |
| MPC format valid | 15 | Report has COD, OBS, TEL headers and coordinate data |

## Anti-Gaming Protections

- Task start time recorded; FITS and report files must have `mtime > task_start`
- Telescope pointed at M13 at start to prevent reuse of correct position
- 2-degree coordinate tolerance is strict enough to reject guessing random sky positions
