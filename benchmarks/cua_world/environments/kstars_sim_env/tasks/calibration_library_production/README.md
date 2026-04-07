# Task: calibration_library_production

## Overview

**Difficulty:** very_hard
**Occupation:** Observatory Director / CCD Operations Manager
**Industry:** Observatory Operations / Scientific Instrumentation
**Environment:** kstars_sim_env (KStars + INDI Simulators)

Tonight's science observing run requires a complete CCD calibration library. The agent must read the calibration requirements document, understand all frame types and counts needed, set up the correct INDI device properties for each frame type, manage upload directories, and build the complete library. A **deliberate anti-gaming measure** seeds 3 stale bias files from a previous session — these must NOT count toward the required totals.

## What Makes This Very Hard

1. **No step-by-step instructions** — only goal and requirements document
2. **Agent must manage 6 different INDI configurations** (bias, dark-300s, dark-600s, flat-V, flat-R, flat-B) sequentially
3. **Agent must create the correct directory tree** before populating it with frames
4. **Error injection**: 3 stale bias files pre-seeded (agent must not count these — they predate task start)
5. **Agent must distinguish frame types** via INDI `FRAME_BIAS`, `FRAME_DARK`, `FRAME_FLAT` settings
6. **Agent must switch filters** for each flat series (V=slot2, R=slot4, B=slot3)
7. **Agent must produce a summary report** in the specified format

## Error Injection Details

Three zero-length stub files are pre-created with timestamps from January 2024:
- `/home/ga/Calibration/bias/old_bias_001.fits`
- `/home/ga/Calibration/bias/old_bias_002.fits`
- `/home/ga/Calibration/bias/old_bias_003.fits`

These represent a real-world scenario where an operator must be aware of stale calibration data. The verifier rejects any file with `mtime < task_start` or with a stale filename.

## INDI Commands Reference

```bash
# BIAS frames (no exposure, frame type BIAS)
indi_setprop 'CCD Simulator.CCD_FRAME_TYPE.FRAME_BIAS=On'
indi_setprop 'CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=/home/ga/Calibration/bias'
indi_setprop 'CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=0'

# DARK frames (change exposure time, frame type DARK)
indi_setprop 'CCD Simulator.CCD_FRAME_TYPE.FRAME_DARK=On'
indi_setprop 'CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=/home/ga/Calibration/darks/300s'
indi_setprop 'CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=300'

# FLAT frames (change filter + exposure, frame type FLAT)
indi_setprop 'CCD Simulator.CCD_FRAME_TYPE.FRAME_FLAT=On'
indi_setprop 'Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE=2'  # V
indi_setprop 'CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR=/home/ga/Calibration/flats/V'
indi_setprop 'CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=3'
```

## Verification Criteria (100 pts, pass ≥ 60)

| Criterion | Points | Details |
|-----------|--------|---------|
| Bias frames | 15 | ≥10 NEW frames in `bias/` (stale files excluded) |
| Dark 300s | 15 | ≥10 frames in `darks/300s/` with EXPTIME~300 |
| Dark 600s | 15 | ≥10 frames in `darks/600s/` with EXPTIME~600 |
| V-band flats | 12 | ≥5 frames in `flats/V/` |
| R-band flats | 12 | ≥5 frames in `flats/R/` |
| B-band flats | 12 | ≥5 frames in `flats/B/` |
| Directory structure | 9 | All 6 subdirectories present |
| Summary report | 10 | `calibration_summary.txt` with correct frame counts |

## Do-Nothing Analysis

- Stale files have `mtime` from 2024 → score contribution = 0
- Directory `bias/` exists (created by setup) → +2 pts from dir score
- **Do-nothing score: ~2 pts, passed=False** ✓ (well below 60 pt threshold)
