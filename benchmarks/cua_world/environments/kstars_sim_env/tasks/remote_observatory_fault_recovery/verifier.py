#!/usr/bin/env python3
"""
Verifier for remote_observatory_fault_recovery task.

Context: Observatory operator recovering an automated telescope from cascading faults.

Criteria (100 pts total, pass >= 60):
1. Telescope connected via INDI         - 10 pts
2. CCD connected via INDI               - 10 pts
3. Filter wheel connected via INDI      - 10 pts
4. Telescope unparked                   - 10 pts
5. Focuser at reasonable position (<50000, not 99000) - 10 pts
6. Telescope at Vega (within 1 degree)  - 15 pts
7. Verification FITS captured           - 15 pts
8. Resolution report exists             - 10 pts
9. Resolution report mentions 3+ faults - 10 pts

Anti-gaming:
- Target image must be created after task start and in specific dir
- Focuser begins at 99000; doing nothing means 0 pts for focus
- Disconnected devices cannot be slewed/imaged
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Vega coordinates
VEGA_RA = 18.6156   # hours
VEGA_DEC = 38.7837  # degrees
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


def verify_remote_observatory_fault_recovery(traj, env_info, task_info):
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

    # ── 1-3. Device Connections (30 pts) ──────────────────────────────────
    tel_conn = result.get('tel_connected', 'Off') == 'On'
    ccd_conn = result.get('ccd_connected', 'Off') == 'On'
    fil_conn = result.get('filter_connected', 'Off') == 'On'

    if tel_conn:
        score += 10
        feedback.append("telescope connected")
    else:
        feedback.append("telescope disconnected")

    if ccd_conn:
        score += 10
        feedback.append("CCD connected")
    else:
        feedback.append("CCD disconnected")

    if fil_conn:
        score += 10
        feedback.append("filter wheel connected")
    else:
        feedback.append("filter wheel disconnected")

    # ── 4. Telescope Unparked (10 pts) ────────────────────────────────────
    parked = result.get('tel_parked', 'On') == 'On'
    if not parked:
        score += 10
        feedback.append("telescope unparked")
    else:
        feedback.append("telescope remains parked")

    # ── 5. Focuser Position (10 pts) ──────────────────────────────────────
    try:
        focus_pos = int(result.get('focus_position', 99000))
    except (ValueError, TypeError):
        focus_pos = 99000

    if 0 <= focus_pos <= 50000:
        score += 10
        feedback.append(f"focuser reset to reasonable position ({focus_pos})")
    else:
        feedback.append(f"focuser runaway state unresolved (position {focus_pos})")

    # ── 6. Telescope at Vega (15 pts) ─────────────────────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, VEGA_RA, VEGA_DEC)
        if sep_deg <= COORD_TOL_DEG:
            score += 15
            feedback.append(f"telescope successfully pointing at Vega (sep {sep_deg:.2f}°)")
        else:
            feedback.append(f"telescope not pointing at Vega (sep {sep_deg:.2f}°)")
    else:
        feedback.append("could not verify telescope coordinates")

    # ── 7. Verification FITS (15 pts) ─────────────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    if len(valid_fits) >= 1:
        score += 15
        feedback.append(f"verification FITS image captured ({len(valid_fits)} found)")
    else:
        feedback.append("no valid verification FITS image found in ~/Images/verification/")

    # ── 8. Report Exists (10 pts) ─────────────────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("resolution report created")
    else:
        feedback.append("resolution report missing or not created during task")

    # ── 9. Report Content (10 pts) ────────────────────────────────────────
    report_b64 = result.get('report_b64', '')
    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()
            keywords = ['telescope', 'ccd', 'filter', 'focuser', 'focus', 'upload', 'directory', 'path']
            mentions = sum(1 for kw in keywords if kw in report_text)
            
            if mentions >= 3:
                score += 10
                feedback.append("report documents the faults effectively")
            elif mentions > 0:
                score += 5
                feedback.append("report documents faults partially")
            else:
                feedback.append("report content does not appear to mention the subsystem faults")
        except Exception:
            feedback.append("could not parse report text")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }