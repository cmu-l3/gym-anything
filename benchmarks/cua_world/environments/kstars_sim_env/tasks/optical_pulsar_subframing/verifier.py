#!/usr/bin/env python3
"""
Verifier for optical_pulsar_subframing task.

Occupation: Astronomer / Astrophysicist
Context: Configuring tight subframing (ROI) and hardware binning to achieve
         high-speed cadence for time-domain observations (Crab Pulsar).

Criteria (100 pts total, pass >= 60 AND critical parameters met):
1. Target Acquisition (20 pts) - RA/Dec within 1.0 degree of Crab Pulsar (05h 34m 32s, +22° 00' 52")
2. High-Cadence Execution (30 pts) - >= 30 fresh FITS files in the required upload directory
3. Subframe / ROI Applied (15 pts) - NAXIS1 <= 256 (Image Width)
4. Binning Applied (10 pts) - XBINNING == 2, YBINNING == 2
5. Exposure & Filter (10 pts) - EXPTIME == 0.5s, FILTER corresponds to Luminance (Slot 1)
6. Context Image Generated (15 pts) - crab_context.png successfully created
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Crab Pulsar Coordinates (05h 34m 32s, +22d 00m 52s)
TARGET_RA = 5.5755    # hours
TARGET_DEC = 22.0144  # degrees
COORD_TOL_DEG = 1.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_optical_pulsar_subframing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 30)
    max_naxis1 = metadata.get('max_naxis1', 256)
    req_bin = metadata.get('required_binning', 2)
    req_exp = metadata.get('required_exposure_sec', 0.5)

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

    # Filter out seeded stale files
    all_fits = result.get('fits_files', [])
    valid_fits = [f for f in all_fits
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]
    valid_count = len(valid_fits)

    # 1. Target Acquisition (20 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        if sep_deg <= COORD_TOL_DEG:
            score += 20
            feedback.append(f"Telescope pointed correctly (separation {sep_deg:.2f}°)")
        else:
            feedback.append(f"Telescope NOT at Crab Pulsar (separation {sep_deg:.2f}°)")
    else:
        feedback.append("Telescope coordinates unreadable")

    # 2. High-Cadence Execution (30 pts)
    if valid_count >= min_fits:
        score += 30
        feedback.append(f"Successfully captured {valid_count} frames")
    elif valid_count >= 15:
        score += 15
        feedback.append(f"Partial capture: {valid_count}/{min_fits} frames")
    elif valid_count > 0:
        score += 5
        feedback.append(f"Insufficient capture: {valid_count}/{min_fits} frames")
    else:
        feedback.append("No valid new FITS frames captured")

    # Analyze headers from the first valid FITS file
    is_subframed = False
    if valid_count > 0:
        sample_fits = valid_fits[0]
        naxis1 = sample_fits.get('naxis1', -1)
        xbin = sample_fits.get('xbin', -1)
        ybin = sample_fits.get('ybin', -1)
        exptime = sample_fits.get('exptime', -1.0)
        filt = sample_fits.get('filter', '').upper()

        # 3. Subframe / ROI Applied (15 pts)
        # Note: If binning is applied, the physical dimensions might be 128x128. 
        # We ensure it is <= 256 to prove subframing from 4096.
        if 0 < naxis1 <= max_naxis1:
            score += 15
            is_subframed = True
            feedback.append(f"Subframe correctly applied (Width: {naxis1}px)")
        else:
            feedback.append(f"Subframe NOT applied or invalid (Width: {naxis1}px)")

        # 4. Binning Applied (10 pts)
        if xbin == req_bin and ybin == req_bin:
            score += 10
            feedback.append("2x2 Binning correctly applied")
        else:
            feedback.append(f"Binning incorrect (X:{xbin}, Y:{ybin})")

        # 5. Exposure & Filter (10 pts)
        if abs(exptime - req_exp) < 0.1:
            score += 5
            feedback.append("Exposure time correct (0.5s)")
        else:
            feedback.append(f"Exposure time incorrect ({exptime}s)")

        if filt in ['LUMINANCE', 'L', 'CLEAR', '1']:
            score += 5
            feedback.append("Luminance filter correct")
        else:
            feedback.append(f"Filter incorrect ({filt})")
    else:
        feedback.append("Cannot verify instrument parameters (No valid FITS found)")

    # 6. Context Image Generated (15 pts)
    if result.get('context_exists', False):
        score += 15
        feedback.append("Context image successfully generated")
    else:
        feedback.append("Context image missing or stale")

    # Final Pass Evaluation
    # Agent MUST successfully execute subframing and capture fresh data to truly "pass"
    passed = score >= 60 and is_subframed and valid_count > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }