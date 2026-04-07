#!/usr/bin/env python3
"""
Verifier for lsb_galaxy_deep_imaging task.

Occupation: Astronomers and Space Scientists
Context: Low Surface Brightness deep imaging of Malin 1.

Criteria (100 pts total, pass >= 60):
1. CCD Actively Cooled (<= -19C in FITS headers and INDI state)  - 20 pts (CRITICAL)
2. 2x2 Binning Applied (XBINNING=2, YBINNING=2 in FITS)          - 20 pts (CRITICAL)
3. Correct Pointing (Telescope at Malin 1 field)                 - 20 pts
4. Deep Integrations (>=4 valid 300s FITS created during task)   - 20 pts
5. Output Artifacts (malin1_sky.png and malin1_report.txt)       - 20 pts

Anti-gaming protections:
- Requires files to have mtime > task_start to avoid trap 0-byte files.
- Checks hardware property injection directly via astropy FITS header parsing.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Malin 1 coordinates
TARGET_RA = 12.6165   # hours
TARGET_DEC = 13.9983  # degrees
COORD_TOL_ARCMIN = 30.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_lsb_galaxy_deep_imaging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 4)
    req_exp = metadata.get('required_exposure_sec', 300)
    req_bin = metadata.get('required_binning', 2)
    req_temp = metadata.get('required_temp_c', -20.0)

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)

    # Filter out the fake pre-seeded trap files
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # Evaluate FITS frames compliance
    cooled_fits = 0
    binned_fits = 0
    long_exp_fits = 0

    for f in valid_fits:
        if f.get('ccd_temp', 999.0) <= -19.0:
            cooled_fits += 1
        if f.get('xbin', 1) == req_bin and f.get('ybin', 1) == req_bin:
            binned_fits += 1
        if f.get('exptime', 0.0) >= req_exp * 0.95:  # Allow 5% tolerance
            long_exp_fits += 1

    # ── 1. CCD Actively Cooled (20 pts) ────────────────────────────────
    cooler_on = result.get('cooler_on', False)
    current_temp = float(result.get('current_temp', 999.0))
    
    is_cooled = False
    if cooler_on and current_temp <= -19.0 and cooled_fits >= 1:
        score += 20
        is_cooled = True
        feedback.append("CCD actively cooled to -20C")
    elif cooled_fits >= 1:
        score += 10
        feedback.append("Cooling seen in FITS headers but INDI state not verified")
    else:
        feedback.append("CCD active cooling (-20C) not applied or failed")

    # ── 2. 2x2 Binning Applied (20 pts) ────────────────────────────────
    is_binned = False
    if binned_fits >= min_fits:
        score += 20
        is_binned = True
        feedback.append("2x2 hardware binning applied to all frames")
    elif binned_fits >= 1:
        score += 10
        feedback.append(f"2x2 binning applied to only {binned_fits} frame(s)")
    else:
        feedback.append("2x2 hardware binning NOT applied")

    # ── 3. Correct Pointing (20 pts) ───────────────────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 20
            feedback.append(f"Telescope pointing accurate (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 10
            feedback.append(f"Telescope roughly near target (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at Malin 1 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read final telescope coordinates")

    # ── 4. Deep Integrations (20 pts) ──────────────────────────────────
    if long_exp_fits >= min_fits:
        score += 20
        feedback.append(f"{long_exp_fits} deep integration (300s) frames captured")
    elif long_exp_fits > 0:
        score += 10
        feedback.append(f"Only {long_exp_fits}/{min_fits} deep frames captured")
    else:
        feedback.append(f"No 300s exposures captured (trap files ignored)")

    # ── 5. Output Artifacts (20 pts) ───────────────────────────────────
    sky_exists = result.get('sky_capture_exists', False)
    report_exists = result.get('report_exists', False)

    art_score = 0
    if sky_exists:
        art_score += 10
        feedback.append("Sky context image created")
    else:
        feedback.append("Sky context image missing")
        
    if report_exists:
        art_score += 10
        feedback.append("Session report created")
    else:
        feedback.append("Session report missing")
        
    score += art_score

    # Determine passing status
    passed = (score >= 60) and is_cooled and is_binned

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }