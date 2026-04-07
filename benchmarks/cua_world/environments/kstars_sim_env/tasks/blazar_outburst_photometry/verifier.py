#!/usr/bin/env python3
"""
Verifier for blazar_outburst_photometry task.

Occupation: Astrophysicist / High-Energy Astronomer
Context: Multi-band ToO photometry of Markarian 421 based on an ATel alert

Criteria (100 pts total, pass >= 70):
1. Telescope pointed at Markarian 421 field (within 30 arcmin)  - 20 pts
2. B-band frames captured (≥5 valid FITS, exptime/filter match) - 15 pts
3. V-band frames captured (≥5 valid FITS, exptime/filter match) - 15 pts
4. R-band frames captured (≥5 valid FITS, exptime/filter match) - 15 pts
5. False-color Sky View generated with heat palette             - 20 pts
6. Optical counterpart report written naming target             - 15 pts
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Mrk 421 predicted coordinates
TARGET_RA = 11.074   # hours (11h 04m 27s)
TARGET_DEC = 38.208  # degrees (+38° 12' 31")
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


def verify_blazar_outburst_photometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_per_filter', 5)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 30.0)

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

    # ── Criterion 1: Telescope at target field (20 pts) ────────────────
    coord_ok = False
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
            coord_ok = True
            feedback.append(f"telescope at Markarian 421 field (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= coord_tol_arcmin * 3:
            score += 10
            feedback.append(f"telescope near target area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at Markarian 421 field (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Filter Classification ──────────────────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    b_count, v_count, r_count = 0, 0, 0
    for f in valid_fits:
        filt = f.get('filter', '').upper()
        exp = f.get('exptime', -1)
        # Classify by exact filter match OR matching expected exposure times
        if 'B' in filt or (exp > 100 and exp <= 140):
            b_count += 1
        elif 'V' in filt or (exp > 50 and exp <= 75 and 'R' not in filt):
            v_count += 1
        elif 'R' in filt or (exp > 50 and exp <= 75 and 'V' not in filt):
            r_count += 1

    # ── Criterion 2: B-band Frames (15 pts) ───────────────────────────
    if b_count >= min_fits:
        score += 15
        feedback.append(f"B-band: {b_count} valid frames captured")
    elif b_count >= 2:
        score += 8
        feedback.append(f"B-band: {b_count}/{min_fits} frames")
    elif b_count >= 1:
        score += 4
        feedback.append(f"B-band: only {b_count} frame")
    else:
        feedback.append("B-band: no valid frames found")

    # ── Criterion 3: V-band Frames (15 pts) ───────────────────────────
    if v_count >= min_fits:
        score += 15
        feedback.append(f"V-band: {v_count} valid frames captured")
    elif v_count >= 2:
        score += 8
        feedback.append(f"V-band: {v_count}/{min_fits} frames")
    elif v_count >= 1:
        score += 4
        feedback.append(f"V-band: only {v_count} frame")
    else:
        feedback.append("V-band: no valid frames found")

    # ── Criterion 4: R-band Frames (15 pts) ───────────────────────────
    if r_count >= min_fits:
        score += 15
        feedback.append(f"R-band: {r_count} valid frames captured")
    elif r_count >= 2:
        score += 8
        feedback.append(f"R-band: {r_count}/{min_fits} frames")
    elif r_count >= 1:
        score += 4
        feedback.append(f"R-band: only {r_count} frame")
    else:
        feedback.append("R-band: no valid frames found")

    # ── Criterion 5: X-Ray Analog Image (20 pts) ──────────────────────
    sky_exists = result.get('sky_capture_exists', False)
    if sky_exists:
        score += 20
        feedback.append("heat palette sky view image created during task")
    else:
        feedback.append("mrk421_xray_analog.png missing or pre-dates task")

    # ── Criterion 6: Optical Counterpart Report (15 pts) ──────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            if 'MARKARIAN 421' in report_text or 'MRK 421' in report_text or 'MARKARIAN' in report_text:
                score += 15
                feedback.append("report created and names Markarian 421")
            else:
                score += 5
                feedback.append("report created but target name 'Markarian 421' missing")
        except:
            feedback.append("report file exists but could not be parsed")
    else:
        feedback.append("optical counterpart report missing or not updated")

    # Pass threshold
    bands_completed = sum(1 for c in [b_count, v_count, r_count] if c >= min_fits)
    passed = (score >= 70) and coord_ok and (bands_completed >= 2)

    if passed:
        feedback.insert(0, "SUCCESS: Key criteria met.")
    else:
        feedback.insert(0, "FAIL: Score < 70, target not reached, or missing photometry bands.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }