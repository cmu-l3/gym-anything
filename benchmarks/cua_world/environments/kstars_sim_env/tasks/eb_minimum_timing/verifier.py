#!/usr/bin/env python3
"""
Verifier for eb_minimum_timing task.

Occupation: Astronomer / AAVSO Eclipsing Binary Section Observer
Context: Rapid-cadence CCD time series of Algol's primary minimum

Criteria (100 pts total, pass >= 60):
1. FITS images (≥20 in /home/ga/Images/eb_timing/algol/)   - 30 pts
2. Telescope pointed at Algol field                        - 20 pts
3. V-band filter correctly used                            - 10 pts
4. O-C timing report created during task                   - 15 pts
5. Timing report valid (mentions Algol, NOBS>=20, etc.)    - 15 pts
6. Sky verification PNG produced (size > 50KB)             - 10 pts

Anti-gaming: files must be created after task start.
"""

import json
import base64
import os
import math
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_RA = 3.1361   # hours (03h 08m 10.1s)
TARGET_DEC = 40.9556 # degrees (+40° 57' 20")
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


def verify_eb_minimum_timing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 20)
    req_filter_slot = metadata.get('required_filter_slot', 2)

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

    # ── Criterion 1: FITS images (30 pts) ─────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    if valid_count >= min_fits:
        score += 30
        feedback.append(f"captured {valid_count} FITS images in algol directory")
    elif valid_count >= 10:
        score += 15
        feedback.append(f"captured {valid_count}/{min_fits} FITS images")
    elif valid_count >= 1:
        score += 5
        feedback.append(f"only {valid_count} FITS image(s) captured")
    else:
        feedback.append("no valid FITS images found in upload directory")

    # ── Criterion 2: Telescope at Target (20 pts) ──────────────────────
    coord_ok = False
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
            coord_ok = True
            feedback.append(f"telescope pointed at Algol field (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 8
            feedback.append(f"telescope near Algol area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope NOT at Algol (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 3: Filter Valid (10 pts) ────────────────────────────
    try:
        current_slot = int(result.get('current_filter_slot', -1))
    except ValueError:
        current_slot = -1

    filter_ok = False
    if current_slot == req_filter_slot:
        filter_ok = True
    else:
        # Check FITS headers as fallback
        for f in valid_fits:
            if 'V' in str(f.get('filter', '')).upper():
                filter_ok = True
                break

    if filter_ok:
        score += 10
        feedback.append("V-band filter used correctly")
    else:
        feedback.append(f"V-band filter NOT verified (slot={current_slot})")

    # ── Criterion 4: O-C Report Exists (15 pts) ───────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_valid = False

    if report_exists and report_mtime > task_start:
        score += 15
        feedback.append("O-C report created during task")
    elif report_exists:
        score += 5
        feedback.append("report exists but predates task start")
    else:
        feedback.append("O-C report NOT found at ~/Documents/algol_oc_report.txt")

    # ── Criterion 5: O-C Report Content (15 pts) ──────────────────────
    if report_exists:
        report_b64 = result.get('report_b64', '')
        if report_b64:
            try:
                report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
                upper = report_text.upper()

                has_target = 'ALGOL' in upper or 'BETA PER' in upper or 'PERSEI' in upper
                has_jd = '2460703' in upper or '2460700' in upper
                has_v = 'V' in upper or 'JOHNSON' in upper
                has_ccd = 'CCD' in upper

                nobs_match = re.search(r'NOBS\s*[=:]?\s*(\d+)', upper)
                has_nobs = False
                if nobs_match:
                    if int(nobs_match.group(1)) >= 20:
                        has_nobs = True

                criteria_met = sum([has_target, has_jd, has_v, has_ccd, has_nobs])
                
                if criteria_met >= 4:
                    score += 15
                    report_valid = True
                    feedback.append("report format and content valid")
                elif criteria_met >= 2:
                    score += 7
                    feedback.append("report partially valid")
                else:
                    feedback.append("report missing key O-C parameters")
            except Exception as e:
                feedback.append("error reading report content")

    # ── Criterion 6: Sky Verification (10 pts) ────────────────────────
    sky_exists = result.get('sky_capture_exists', False)
    sky_size = result.get('sky_capture_size', 0)

    if sky_exists and sky_size > 50000:
        score += 10
        feedback.append("sky verification image captured correctly (>50KB)")
    elif sky_exists:
        score += 5
        feedback.append("sky verification image captured but size is suspicious")
    else:
        feedback.append("sky verification image NOT found")

    # ── Final Pass Check ──────────────────────────────────────────────
    key_criteria_met = (valid_count >= min_fits) or (coord_ok and report_valid)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }