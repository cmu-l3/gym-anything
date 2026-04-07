#!/usr/bin/env python3
"""
Verifier for asteroid_lightcurve_photometry task.

Criteria (100 pts total, pass >= 60):
1. FITS files captured (25 pts): >=15 valid FITS in correct directory, created during task.
2. Telescope at Nysa (20 pts): RA=18.5375, Dec=-25.145, tol=0.5 deg (30 arcmin).
3. Clear/Luminance filter used (10 pts): Slot 1.
4. Upload directory created (5 pts).
5. ALCDEF report exists & fresh (10 pts).
6. ALCDEF metadata valid (15 pts): Minimum 5 metadata fields present.
7. ALCDEF data block valid (15 pts): STARTDATA/ENDDATA and >=5 DATA lines.
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

# (44) Nysa target coordinates
TARGET_RA = 18.5375    # hours
TARGET_DEC = -25.145   # degrees
COORD_TOL_DEG = 0.5    # 30 arcminutes


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_asteroid_lightcurve_photometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 15)

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

    # 1. Directory created (5 pts)
    if result.get('dir_exists'):
        score += 5
        feedback.append("Upload directory created")
    else:
        feedback.append("Upload directory NOT created")

    # 2. FITS files captured (25 pts)
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]
    fits_count = len(valid_fits)

    if fits_count >= min_fits:
        score += 25
        feedback.append(f"Captured {fits_count} FITS files")
    elif fits_count > 0:
        pts = int((fits_count / min_fits) * 25)
        score += pts
        feedback.append(f"Captured {fits_count}/{min_fits} FITS files")
    else:
        feedback.append("No valid new FITS files captured")

    # 3. Telescope at target (20 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        if sep_deg <= COORD_TOL_DEG:
            score += 20
            feedback.append(f"Telescope pointed at Nysa (sep {sep_deg:.2f}°)")
        elif sep_deg <= COORD_TOL_DEG * 3:
            score += 10
            feedback.append(f"Telescope near Nysa (sep {sep_deg:.2f}°)")
        else:
            feedback.append(f"Telescope NOT at Nysa (sep {sep_deg:.2f}°)")
    else:
        feedback.append("Could not determine telescope position")

    # 4. Filter slot (10 pts)
    filter_slot = result.get('current_filter_slot', -1)
    if filter_slot == 1:
        score += 10
        feedback.append("Luminance/Clear filter (slot 1) selected")
    else:
        feedback.append(f"Incorrect filter selected (slot {filter_slot}, expected 1)")

    # 5. ALCDEF report exists & fresh (10 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("ALCDEF report created during task")
    else:
        feedback.append("ALCDEF report NOT found or stale")

    # Parse report content
    report_b64 = result.get('report_b64', '')
    report_text = ""
    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
        except Exception:
            pass

    # 6. ALCDEF metadata valid (15 pts - 3 pts per field)
    meta_score = 0
    if report_text:
        upper_text = report_text.upper()
        # Object name or number
        if "OBJECTNUMBER=44" in upper_text or bool(re.search(r"OBJECTNAME=.*NYSA", upper_text)):
            meta_score += 3
        # Filter
        if "FILTER=" in upper_text:
            meta_score += 3
        # Standard
        if bool(re.search(r"STANDARD=.*ALCDEF", upper_text)):
            meta_score += 3
        # RA
        if "OBJECTRA=" in upper_text:
            meta_score += 3
        # DEC
        if "OBJECTDEC=" in upper_text:
            meta_score += 3
            
    score += meta_score
    if meta_score == 15:
        feedback.append("ALCDEF metadata fully valid")
    else:
        feedback.append(f"ALCDEF metadata score: {meta_score}/15")

    # 7. ALCDEF data block valid (15 pts)
    data_score = 0
    if report_text:
        has_start = "STARTDATA" in report_text.upper()
        has_end = "ENDDATA" in report_text.upper()
        if has_start and has_end:
            data_score += 5
            # Count data lines (DATA=JD|MAG|MAGERR or similar)
            data_lines = len(re.findall(r"DATA\s*=\s*\d+\.?\d*\|\d+\.?\d*\|\d+\.?\d*", report_text.upper()))
            if data_lines >= 5:
                data_score += 10
            elif data_lines > 0:
                data_score += 5
                
    score += data_score
    if data_score == 15:
        feedback.append("ALCDEF data block valid (>= 5 records)")
    else:
        feedback.append(f"ALCDEF data block score: {data_score}/15")

    # Final result
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }