#!/usr/bin/env python3
"""
Verifier for ccd_focus_calibration task.

Occupation: Observatory Technician / Observational Astronomer
Context: V-curve focus calibration on Vega prior to science imaging.

Criteria (100 pts total, pass >= 60):
1. FITS images captured (>= 9 valid frames created during task) - 25 pts
2. Telescope pointed at Vega field                              - 20 pts
3. Focuser set to optimal position (28000-42000)                - 20 pts
4. Focus report exists and was created during task              - 15 pts
5. Report content quality (lists positions, optimal focus)      - 20 pts
"""

import json
import base64
import os
import math
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Vega coordinates
TARGET_RA = 18.6156
TARGET_DEC = 38.7836
COORD_TOL_ARCMIN = 15.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_ccd_focus_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_fits = metadata.get('expected_fits_count', 9)
    focus_min = metadata.get('optimal_focus_min', 28000)
    focus_max = metadata.get('optimal_focus_max', 42000)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 15)

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

    # ── Criterion 1: FITS images (25 pts) ─────────────────────────────
    fits_files = result.get('fits_files', [])
    # Anti-gaming: valid files must be created AFTER task_start
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    if valid_count >= expected_fits:
        score += 25
        feedback.append(f"captured {valid_count} FITS images (stale files ignored)")
    elif valid_count >= 5:
        score += 15
        feedback.append(f"captured {valid_count}/{expected_fits} FITS images")
    elif valid_count >= 1:
        score += 5
        feedback.append(f"only {valid_count} new FITS image(s) found")
    else:
        feedback.append("no new valid FITS images captured in focus_run/")

    # ── Criterion 2: Telescope pointed at Vega (20 pts) ───────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= coord_tol_arcmin:
            score += 20
            feedback.append(f"telescope pointed at Vega (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= coord_tol_arcmin * 3:
            score += 10
            feedback.append(f"telescope near Vega (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at Vega (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 3: Focuser at optimal position (20 pts) ─────────────
    try:
        final_focus = int(result.get('final_focus', -1))
    except (ValueError, TypeError):
        final_focus = -1

    if focus_min <= final_focus <= focus_max:
        score += 20
        feedback.append(f"focuser parked at optimal position ({final_focus})")
    elif final_focus > 0 and final_focus != 50000:
        score += 5
        feedback.append(f"focuser moved but not to optimal range (is {final_focus})")
    else:
        feedback.append("focuser not moved to an optimal focus position")

    # ── Criterion 4: Report file exists (15 pts) ──────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_during_task = report_exists and (report_mtime > task_start)

    if report_during_task:
        score += 15
        feedback.append("focus report created during task")
    elif report_exists:
        score += 0
        feedback.append("report file exists but has pre-task timestamp")
    else:
        feedback.append("focus report not found")

    # ── Criterion 5: Report content quality (20 pts) ──────────────────
    report_b64 = result.get('report_content_b64', '')
    if report_b64 and report_during_task:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            content_score = 0
            
            # Mentions target star (5 pts)
            if 'VEGA' in report_text or 'HD 172167' in report_text or 'LYRAE' in report_text:
                content_score += 5
                
            # Identifies optimal focus in the right range (5 pts)
            found_optimal = False
            for val in re.findall(r'\b\d{5}\b', report_text):
                if focus_min <= int(val) <= focus_max:
                    found_optimal = True
                    break
            if found_optimal:
                content_score += 5
                
            # Lists multiple positions evaluated (5 pts)
            numbers = [int(val) for val in re.findall(r'\b\d{5}\b', report_text)]
            if len(set(numbers)) >= 5:
                content_score += 5
                
            # Mentions verification exposure (5 pts)
            if 'VERIF' in report_text or 'CONFIRM' in report_text or 'FINAL' in report_text:
                content_score += 5
                
            score += content_score
            feedback.append(f"report content score: {content_score}/20")
            
        except Exception as e:
            feedback.append(f"failed to parse report: {str(e)}")
    else:
        feedback.append("report content not evaluated (missing or empty)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }