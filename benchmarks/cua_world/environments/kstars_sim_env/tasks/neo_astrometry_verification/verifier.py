#!/usr/bin/env python3
"""
Verifier for neo_astrometry_verification task.

Occupation: Planetary Scientist / Near-Earth Object Observer
Context: Independent astrometry verification of asteroid 2020 QG for the Minor Planet Center

Criteria (100 pts total, pass >= 60):
1. FITS images captured (≥6, in correct directory)             - 25 pts
2. Telescope pointed at 2020 QG field (within 2 degrees)      - 25 pts
3. MPC report file created during task                        - 20 pts
4. Report mentions 2020 QG by designation                     - 15 pts
5. Report has MPC format elements (COD, OBS, TEL, etc.)       - 15 pts
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 2020 QG predicted coordinates (as given in request)
TARGET_RA = 16.883   # hours
TARGET_DEC = -21.917 # degrees
COORD_TOL_DEG = 2.0  # 2-degree tolerance (generous for NEO observer)


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_neo_astrometry_verification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 6)
    coord_tol_deg = metadata.get('coordinate_tolerance_deg', 2.0)

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
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    if valid_count >= min_fits:
        score += 25
        feedback.append(f"captured {valid_count} FITS images in asteroid directory")
    elif valid_count >= 3:
        score += 12
        feedback.append(f"captured {valid_count}/{min_fits} FITS images")
    elif valid_count >= 1:
        score += 5
        feedback.append(f"only {valid_count} FITS image(s) found")
    else:
        feedback.append("no FITS images in /home/ga/Images/asteroids/2020QG/")

    # ── Criterion 2: Telescope at target field (25 pts) ────────────────
    coord_ok = False
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        if sep_deg <= coord_tol_deg:
            score += 25
            coord_ok = True
            feedback.append(f"telescope at 2020 QG field (sep {sep_deg:.2f}°)")
        elif sep_deg <= coord_tol_deg * 2:
            score += 12
            feedback.append(f"telescope near target area (sep {sep_deg:.2f}°)")
        else:
            feedback.append(f"telescope not at 2020 QG field (sep {sep_deg:.2f}°)")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 3: MPC report exists (20 pts) ────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_during_task = report_exists and (report_mtime > task_start)

    if report_during_task:
        score += 20
        feedback.append("MPC report created during task")
    elif report_exists:
        score += 5
        feedback.append("report file exists but has pre-task timestamp")
    else:
        feedback.append("MPC report not found at ~/Documents/mpc_report.txt")

    # ── Criterion 4: Report mentions 2020 QG (15 pts) ─────────────────
    report_b64 = result.get('report_b64', '')
    report_text = ''
    has_designation = False
    has_mpc_format = False

    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            report_text = report_text.replace('\\n', '\n').replace('\\t', '\t')
            upper = report_text.upper()

            has_designation = '2020 QG' in upper or '2020QG' in upper
        except Exception as e:
            feedback.append(f"report decode error: {e}")

    if has_designation:
        score += 15
        feedback.append("report correctly names 2020 QG")
    elif report_exists:
        feedback.append("report does not mention 2020 QG by designation")
    else:
        feedback.append("report missing (cannot check designation)")

    # ── Criterion 5: MPC format elements (15 pts) ─────────────────────
    if report_text:
        upper = report_text.upper()
        has_cod = 'COD' in upper or 'OBS CODE' in upper
        has_obs = 'OBS ' in upper
        has_tel = 'TEL' in upper
        has_number = any(c.isdigit() for c in report_text)
        has_coords = ('RA' in upper or ':' in report_text or
                      any(s in report_text for s in ['16 52', '16 53', '16h', '-21']))

        mpc_elements = sum([has_cod, has_obs, has_tel])
        if mpc_elements >= 3 and has_coords:
            score += 15
            has_mpc_format = True
            feedback.append("report has valid MPC format elements")
        elif mpc_elements >= 2:
            score += 10
            feedback.append(f"report has {mpc_elements}/3 MPC format elements")
        elif mpc_elements >= 1 or (has_number and has_coords):
            score += 5
            feedback.append("report has minimal astrometry content")
        else:
            feedback.append("report lacks MPC format structure")
    elif report_exists:
        feedback.append("report file content unreadable")

    # ── Final verdict ─────────────────────────────────────────────────
    passed = (score >= 60) and coord_ok and (valid_count >= min_fits) and report_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
