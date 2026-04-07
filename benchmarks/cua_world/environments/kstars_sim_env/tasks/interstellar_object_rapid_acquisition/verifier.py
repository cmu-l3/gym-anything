#!/usr/bin/env python3
"""
Verifier for interstellar_object_rapid_acquisition task.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_RA = 18.6155   # 18h 36m 56s
TARGET_DEC = 38.7836  # +38d 47m 01s
COORD_TOL_ARCMIN = 20.0

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_interstellar_object_rapid_acquisition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

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

    # 1. Telescope Slew (15 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 15
            feedback.append(f"telescope at target field (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 5
            feedback.append(f"telescope near target field (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at target field (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # 2. FITS File Evaluation (mtime check avoids stale frames)
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)
    
    # Check CCD Binning (20 pts) & Short Exposures (15 pts)
    correct_binning_count = sum(1 for f in valid_fits if f.get('xbinning') == 2 and f.get('ybinning') == 2)
    correct_exposure_count = sum(1 for f in valid_fits if abs(f.get('exptime', 0) - 5.0) < 0.1)

    if correct_binning_count > 0:
        score += 20
        feedback.append("CCD configured to 2x2 binning")
    else:
        feedback.append("2x2 binning not detected in new FITS files")

    if correct_exposure_count > 0:
        score += 15
        feedback.append("short exposures (5.0s) used")
    else:
        feedback.append("5.0s exposures not detected in new FITS files")

    # 3. 15+ Frames Captured (20 pts)
    if valid_count >= 15:
        score += 20
        feedback.append(f"captured {valid_count} valid FITS frames")
    elif valid_count >= 5:
        score += 10
        feedback.append(f"captured {valid_count}/15 valid FITS frames")
    elif valid_count > 0:
        score += 5
        feedback.append(f"captured only {valid_count} valid FITS frame(s)")
    else:
        feedback.append("no valid FITS frames captured")

    # 4. Thermal Proxy Image (15 pts)
    if result.get('proxy_exists', False):
        score += 15
        feedback.append("thermal proxy image generated")
    else:
        feedback.append("thermal proxy image missing or has pre-task timestamp")

    # 5. Observation Report (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')

    if report_exists and report_mtime > task_start and report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()
            if 'c/2026' in report_text and '15' in report_text and '2x2' in report_text:
                score += 15
                feedback.append("observation report complete and correct")
            else:
                score += 5
                feedback.append("observation report missing required details")
        except:
            feedback.append("observation report could not be read")
    else:
        feedback.append("observation report missing or not updated")

    # Pass logic: Must have captured some valid frames AND configured binning or exposure
    key_criteria_met = valid_count >= 5 and (correct_binning_count > 0 or correct_exposure_count > 0)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback)
    }