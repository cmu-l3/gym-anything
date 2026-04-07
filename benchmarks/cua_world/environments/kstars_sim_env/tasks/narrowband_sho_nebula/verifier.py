#!/usr/bin/env python3
"""
Verifier for narrowband_sho_nebula task.

Occupation: Astrophotographer (professional or advanced amateur)
Context: SHO (Sulfur-Hydrogen-Oxygen) narrowband imaging of NGC 7000 (North America Nebula)

Criteria (100 pts total, pass >= 60):
1. Ha frames captured (≥5 in narrowband/Ha/ dir)               - 20 pts
2. OIII frames captured (≥5 in narrowband/OIII/ dir)            - 20 pts
3. SII frames captured (≥5 in narrowband/SII/ dir)             - 15 pts
4. Telescope pointed at NGC 7000 field                          - 20 pts
5. SHO composite PNG produced (false_color.py --palette narrowband) - 25 pts
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# NGC 7000 true coordinates
NGC7000_RA = 20.979   # hours
NGC7000_DEC = 44.334  # degrees
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


def verify_narrowband_sho_nebula(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_per_filter = metadata.get('min_fits_per_filter', 5)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 30)

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

    # ── Count valid FITS per filter directory ─────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_in_dir(dirname):
        """Count valid FITS in a specific sub-directory."""
        count = 0
        for f in valid_fits:
            fdir = f.get('dir', '').upper()
            ffilt = f.get('filter', '').upper()
            if fdir == dirname.upper() or dirname.upper() in ffilt:
                count += 1
        return count

    ha_count = count_in_dir('Ha')
    oiii_count = count_in_dir('OIII')
    sii_count = count_in_dir('SII')

    # ── Criterion 1: Ha frames (20 pts) ───────────────────────────────
    if ha_count >= min_per_filter:
        score += 20
        feedback.append(f"Ha: {ha_count} frames captured")
    elif ha_count >= 2:
        score += 10
        feedback.append(f"Ha: {ha_count}/{min_per_filter} frames")
    elif ha_count >= 1:
        score += 5
        feedback.append(f"Ha: only {ha_count} frame")
    else:
        feedback.append("Ha: no frames in narrowband/Ha/")

    # ── Criterion 2: OIII frames (20 pts) ─────────────────────────────
    if oiii_count >= min_per_filter:
        score += 20
        feedback.append(f"OIII: {oiii_count} frames captured")
    elif oiii_count >= 2:
        score += 10
        feedback.append(f"OIII: {oiii_count}/{min_per_filter} frames")
    elif oiii_count >= 1:
        score += 5
        feedback.append(f"OIII: only {oiii_count} frame")
    else:
        feedback.append("OIII: no frames in narrowband/OIII/")

    # ── Criterion 3: SII frames (15 pts) ──────────────────────────────
    if sii_count >= min_per_filter:
        score += 15
        feedback.append(f"SII: {sii_count} frames captured")
    elif sii_count >= 2:
        score += 8
        feedback.append(f"SII: {sii_count}/{min_per_filter} frames")
    elif sii_count >= 1:
        score += 4
        feedback.append(f"SII: only {sii_count} frame")
    else:
        feedback.append("SII: no frames in narrowband/SII/")

    # ── Criterion 4: Telescope at NGC 7000 (20 pts) ───────────────────
    coord_ok = False
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, NGC7000_RA, NGC7000_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= coord_tol_arcmin:
            score += 20
            coord_ok = True
            feedback.append(f"telescope at NGC 7000 (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= coord_tol_arcmin * 2:
            score += 8
            feedback.append(f"telescope near NGC 7000 area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at NGC 7000 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 5: SHO composite image (25 pts) ─────────────────────
    composite_exists = result.get('composite_exists', False)
    composite_size = result.get('composite_size', 0)
    composite_mtime = result.get('composite_mtime', 0)

    if composite_exists and composite_mtime > task_start:
        if composite_size > 50000:  # > 50KB is a real image
            score += 25
            feedback.append(f"SHO composite produced ({composite_size//1024}KB)")
        elif composite_size > 10000:
            score += 15
            feedback.append(f"SHO composite exists but small ({composite_size}B)")
        else:
            score += 5
            feedback.append("SHO composite file exists but may be empty/corrupt")
    elif composite_exists:
        score += 5
        feedback.append("composite exists but was not created during task")
    else:
        # Check if sky_view exists as partial credit
        if result.get('sky_capture_exists', False):
            score += 10
            feedback.append("sky capture exists but false-color composite not created")
        else:
            feedback.append("SHO composite not found at /home/ga/Images/ngc7000/composite_sho.png")

    # ── Final verdict ─────────────────────────────────────────────────
    # Require Ha + OIII (at minimum) AND correct target
    filters_ok = (ha_count >= min_per_filter and oiii_count >= min_per_filter)
    passed = (score >= 60) and coord_ok and filters_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
