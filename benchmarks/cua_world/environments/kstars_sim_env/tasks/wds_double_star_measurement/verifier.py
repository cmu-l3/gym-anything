#!/usr/bin/env python3
"""
Verifier for wds_double_star_measurement task.

Occupation: Astronomer / Double Star Observer
Context: Washington Double Star (WDS) catalog measurement request for three systems.

Criteria (100 pts total, pass >= 60):
1. Albireo FITS images (>=3 in doubles/albireo/)               - 12 pts
2. 61 Cygni FITS images (>=3 in doubles/61cyg/)                - 12 pts
3. Eta Cas FITS images (>=3 in doubles/eta_cas/)               - 12 pts
4. Total FITS count >= 9 (sum of valid new files)              - 9 pts
5. Telescope visited Albireo (verified via FITS headers)       - 8 pts
6. Telescope visited 61 Cygni (verified via FITS headers)      - 8 pts
7. Telescope visited Eta Cas (verified via FITS headers)       - 8 pts
8. WDS report file exists and created during task              - 8 pts
9. Report lists all 3 targets (WDS designation or name)        - 10 pts
10. Report has Position Angle (theta) and Separation (rho)      - 8 pts
11. Sky capture image produced                                 - 5 pts

Anti-gaming: files must have mtime > task_start to count. A stale file seeded in
albireo directory must be ignored.
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

# Target coordinates
TARGETS = {
    "albireo": {"ra": 19.512, "dec": 27.960},
    "61cyg": {"ra": 21.115, "dec": 38.749},
    "eta_cas": {"ra": 0.818, "dec": 57.815}
}
COORD_TOL_ARCMIN = 30.0


def parse_sexagesimal_ra(ra_str):
    if not ra_str: return -1
    try: return float(ra_str)
    except ValueError: pass
    nums = re.findall(r"[-+]?\d*\.\d+|\d+", ra_str)
    if len(nums) >= 3:
        return float(nums[0]) + float(nums[1])/60.0 + float(nums[2])/3600.0
    elif len(nums) >= 2:
        return float(nums[0]) + float(nums[1])/60.0
    elif len(nums) >= 1:
        return float(nums[0])
    return -1


def parse_sexagesimal_dec(dec_str):
    if not dec_str: return -999
    try: return float(dec_str)
    except ValueError: pass
    sign = -1 if '-' in dec_str else 1
    nums = re.findall(r"\d*\.\d+|\d+", dec_str)
    if len(nums) >= 3:
        return sign * (float(nums[0]) + float(nums[1])/60.0 + float(nums[2])/3600.0)
    elif len(nums) >= 2:
        return sign * (float(nums[0]) + float(nums[1])/60.0)
    elif len(nums) >= 1:
        return sign * float(nums[0])
    return -999


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_wds_double_star_measurement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits_per_target = metadata.get('min_fits_per_target', 3)

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
    fits_files = result.get('fits_files', [])

    # Filter out stale files (mtime <= task_start) and empty stubs
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_and_check_visitation(target_key):
        count = 0
        visited = False
        target_ra = TARGETS[target_key]["ra"]
        target_dec = TARGETS[target_key]["dec"]

        for f in valid_fits:
            if f.get('dir') == target_key:
                count += 1
                # Check visitation from FITS headers
                ra_str = f.get('ra', '')
                dec_str = f.get('dec', '')
                if ra_str and dec_str:
                    ra_h = parse_sexagesimal_ra(ra_str)
                    dec_d = parse_sexagesimal_dec(dec_str)
                    if ra_h >= 0 and dec_d > -900:
                        sep = angular_separation_deg(ra_h, dec_d, target_ra, target_dec)
                        if sep * 60.0 <= COORD_TOL_ARCMIN:
                            visited = True
        return count, visited

    counts = {}
    visited = {}
    total_valid_fits = len(valid_fits)

    for target in ['albireo', '61cyg', 'eta_cas']:
        counts[target], visited[target] = count_and_check_visitation(target)

    # ── Criteria 1-3: FITS counts per target (3 x 12 pts) ─────────────
    for target, name in [('albireo', 'Albireo'), ('61cyg', '61 Cygni'), ('eta_cas', 'Eta Cas')]:
        c = counts[target]
        if c >= min_fits_per_target:
            score += 12
            feedback.append(f"{name} FITS: {c} frames")
        elif c > 0:
            score += 5
            feedback.append(f"{name} FITS: {c}/{min_fits_per_target} frames")
        else:
            feedback.append(f"{name} FITS: no valid new frames")

    # ── Criterion 4: Total FITS count (9 pts) ─────────────────────────
    if total_valid_fits >= min_fits_per_target * 3:
        score += 9
        feedback.append(f"Total FITS count: {total_valid_fits} (target >= 9)")
    elif total_valid_fits >= min_fits_per_target:
        score += 4
        feedback.append(f"Total FITS count: {total_valid_fits}")

    # ── Criteria 5-7: Target visitation (3 x 8 pts) ───────────────────
    for target, name in [('albireo', 'Albireo'), ('61cyg', '61 Cygni'), ('eta_cas', 'Eta Cas')]:
        if visited[target]:
            score += 8
            feedback.append(f"Visited {name}: Verified via FITS headers")
        else:
            feedback.append(f"Visited {name}: Not verified")

    # ── Criterion 8: WDS report exists (8 pts) ────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_valid = report_exists and report_mtime > task_start

    if report_valid:
        score += 8
        feedback.append("WDS report file created during task")
    else:
        feedback.append("WDS report file missing or stale")

    # ── Criteria 9-10: Report contents ────────────────────────────────
    report_b64 = result.get('report_b64', '')
    if report_valid and report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()

            # Criterion 9: Lists all 3 targets (10 pts)
            targets_found = 0
            if 'albireo' in report_text or '19307+2758' in report_text: targets_found += 1
            if '61 cyg' in report_text or '21069+3845' in report_text: targets_found += 1
            if 'eta cas' in report_text or '00491+5749' in report_text: targets_found += 1

            if targets_found == 3:
                score += 10
                feedback.append("Report lists all 3 WDS targets")
            elif targets_found > 0:
                score += (targets_found * 3)
                feedback.append(f"Report lists {targets_found}/3 WDS targets")
            else:
                feedback.append("Report does not identify the target systems")

            # Criterion 10: Has PA and Separation (8 pts)
            has_theta = 'theta' in report_text or 'pa' in report_text or 'angle' in report_text
            has_rho = 'rho' in report_text or 'sep' in report_text
            # Additionally, look for floating point numbers that look like measurements
            nums = len(re.findall(r'\d+\.\d+', report_text))

            if has_theta and has_rho and nums >= 3:
                score += 8
                feedback.append("Report includes theta (PA) and rho (separation) data")
            elif nums >= 3:
                score += 4
                feedback.append("Report has numeric data but missing theta/rho headers")
            else:
                feedback.append("Report is missing required measurement data")

        except Exception as e:
            feedback.append(f"Error parsing report text: {e}")
    else:
        feedback.append("Cannot evaluate report contents (missing or empty)")

    # ── Criterion 11: Sky capture (5 pts) ─────────────────────────────
    sky_exists = result.get('sky_capture_exists', False)
    if sky_exists:
        score += 5
        feedback.append("Sky capture image produced")
    else:
        feedback.append("No sky capture image found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }