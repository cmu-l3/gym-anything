#!/usr/bin/env python3
"""
Verifier for equatorial_mount_pec_calibration task.

Occupation: Observatory Engineer / Technician
Context: Executing a Periodic Error Correction (PEC) data gathering run on Mintaka.

Criteria (100 pts total, pass >= 60):
1. Telescope Pointing: Pointed at Mintaka (RA ~5.533h, Dec ~-0.3°) (20 pts)
2. Focuser Offset: Focuser set to exactly 31500 (20 pts)
3. Filter Selection: Filter slot 2 (V-band) selected (15 pts)
4. Image Acquisition: >= 40 valid FITS files in pec_run dir (25 pts)
5. Summary Report: pec_summary.txt exists and contains target/focus info (20 pts)

Anti-gaming:
- Key criteria (pointing + acquisition) must both be met.
- FITS and report files must have modification times > task_start.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    """Calculate angular separation between two equatorial coordinates."""
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_equatorial_mount_pec_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    target_ra = metadata.get('target_ra_hours', 5.5333)
    target_dec = metadata.get('target_dec_degrees', -0.299)
    coord_tol_deg = metadata.get('coordinate_tolerance_deg', 0.5)
    expected_focuser = metadata.get('expected_focuser_pos', 31500)
    expected_filter = metadata.get('expected_filter_slot', 2)
    min_fits = metadata.get('min_fits_count', 40)

    # Copy and parse task_result.json
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

    # 1. Telescope Pointing (20 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    pointing_ok = False
    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, target_ra, target_dec)
        if sep_deg <= coord_tol_deg:
            score += 20
            pointing_ok = True
            feedback.append(f"Telescope pointing correct (sep {sep_deg:.2f}°)")
        else:
            feedback.append(f"Telescope pointing incorrect (sep {sep_deg:.2f}° from Mintaka)")
    else:
        feedback.append("Could not read telescope coordinates")

    # 2. Focuser Offset (20 pts)
    try:
        focuser_pos = int(result.get('focuser_pos', -1))
    except (ValueError, TypeError):
        focuser_pos = -1

    if focuser_pos == expected_focuser:
        score += 20
        feedback.append(f"Focuser set correctly to {expected_focuser}")
    else:
        feedback.append(f"Focuser is at {focuser_pos} (expected {expected_focuser})")

    # 3. Filter Selection (15 pts)
    try:
        filter_slot = int(result.get('filter_slot', -1))
    except (ValueError, TypeError):
        filter_slot = -1

    if filter_slot == expected_filter:
        score += 15
        feedback.append("Filter slot 2 (V-band) selected")
    else:
        feedback.append(f"Filter slot is {filter_slot} (expected {expected_filter})")

    # 4. Image Acquisition (25 pts)
    fits_files = result.get('fits_files', [])
    # Anti-gaming: ensure files were captured during the task with valid data
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]
    valid_count = len(valid_fits)

    acq_ok = False
    if valid_count >= min_fits:
        score += 25
        acq_ok = True
        feedback.append(f"Captured {valid_count} FITS images")
    elif valid_count >= 10:
        score += 10
        feedback.append(f"Captured {valid_count}/{min_fits} FITS images")
    elif valid_count >= 1:
        score += 5
        feedback.append(f"Captured only {valid_count} FITS image(s)")
    else:
        feedback.append("No valid FITS images captured in pec_run directory")

    # 5. Summary Report (20 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    report_during_task = report_exists and (report_mtime > task_start)
    
    if report_during_task:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()
            if 'mintaka' in report_text and str(expected_focuser) in report_text:
                score += 20
                feedback.append("Summary report contains target and focuser position")
            else:
                score += 10
                feedback.append("Summary report created but missing 'Mintaka' or '31500'")
        except Exception:
            feedback.append("Could not decode summary report")
    elif report_exists:
        feedback.append("Summary report exists but has pre-task timestamp (gaming attempt rejected)")
    else:
        feedback.append("Summary report not found at ~/Documents/pec_summary.txt")

    # Final logic: score must be passing AND key core operations complete
    passed = (score >= 60) and pointing_ok and acq_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }