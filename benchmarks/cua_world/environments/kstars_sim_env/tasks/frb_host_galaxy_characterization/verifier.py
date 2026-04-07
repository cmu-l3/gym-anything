#!/usr/bin/env python3
"""
Verifier for frb_host_galaxy_characterization task.

Criteria (100 pts total, pass >= 75):
1. Coordinate Extraction: Telescope RA/Dec within 0.05 deg of 5.533h / 33.148° (15 pts)
2. Luminance Imaging: >=3 FITS with EXPTIME~120 and Filter~L/1 (15 pts)
3. R-band Imaging: >=3 FITS with EXPTIME~120 and Filter~R/4 (15 pts)
4. H-alpha Imaging: >=3 FITS with EXPTIME~300 and Filter~Ha/5 (20 pts)
5. Finding Chart Generation: New cool finding chart PNG > 50KB (20 pts)
6. Status Report: Report file exists with correct decimal coordinates (15 pts)

Anti-gaming:
- Target sexagesimal is 05h 31m 58.7s, +33d 08m 52.5s. Agent must calculate dec/ra properly.
- Stale finding chart is pre-seeded; only new mtimes pass.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# True Coordinates for FRB 2024exq (05h 31m 58.7s, +33d 08m 52.5s)
TARGET_RA_H = 5.53297
TARGET_DEC_DEG = 33.1479
TOLERANCE_DEG = 0.05

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_frb_host_galaxy_characterization(traj, env_info, task_info):
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

    # 1. Telescope Coordinate Extraction (15 pts)
    coord_ok = False
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA_H, TARGET_DEC_DEG)
        if sep_deg <= TOLERANCE_DEG:
            score += 15
            coord_ok = True
            feedback.append(f"Telescope on target FRB 2024exq (sep {sep_deg:.3f}°)")
        elif sep_deg <= TOLERANCE_DEG * 10:
            score += 5
            feedback.append(f"Telescope near target area (sep {sep_deg:.3f}°)")
        else:
            feedback.append(f"Telescope off target (sep {sep_deg:.3f}°)")
    else:
        feedback.append("Could not read final telescope coordinates")

    # Filter Valid FITS (created during task)
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # Initialize counters
    l_count = 0
    r_count = 0
    ha_count = 0

    for f in valid_fits:
        filt = f.get('filter', '').strip().upper()
        exp = f.get('exptime', -1)
        
        is_120s = (110 <= exp <= 130)
        is_300s = (290 <= exp <= 310)

        if is_120s and (filt in ('1', 'L', 'LUM', 'LUMINANCE')):
            l_count += 1
        elif is_120s and (filt in ('4', 'R', 'RED')):
            r_count += 1
        elif is_300s and (filt in ('5', 'HA', 'H-ALPHA', 'HALPHA')):
            ha_count += 1

    # 2. Luminance Imaging (15 pts)
    if l_count >= 3:
        score += 15
        feedback.append(f"Luminance frames: {l_count} (>=3 required)")
    elif l_count > 0:
        score += 5
        feedback.append(f"Luminance frames: {l_count}/3")
    else:
        feedback.append("Luminance frames missing or incorrect")

    # 3. R-band Imaging (15 pts)
    if r_count >= 3:
        score += 15
        feedback.append(f"R-band frames: {r_count} (>=3 required)")
    elif r_count > 0:
        score += 5
        feedback.append(f"R-band frames: {r_count}/3")
    else:
        feedback.append("R-band frames missing or incorrect")

    # 4. H-alpha Imaging (20 pts)
    if ha_count >= 3:
        score += 20
        feedback.append(f"H-alpha frames: {ha_count} (>=3 required)")
    elif ha_count > 0:
        score += 8
        feedback.append(f"H-alpha frames: {ha_count}/3")
    else:
        feedback.append("H-alpha frames missing or incorrect")

    # 5. Finding Chart Generation (20 pts)
    chart_exists = result.get('chart_exists', False)
    chart_mtime = result.get('chart_mtime', 0)
    chart_size = result.get('chart_size', 0)

    if chart_exists and chart_mtime > task_start:
        if chart_size > 51200:  # >50KB
            score += 20
            feedback.append("Valid finding chart generated")
        else:
            score += 10
            feedback.append("Finding chart generated but size is small (<50KB)")
    else:
        feedback.append("Finding chart not generated or stale file used")

    # 6. Status Report (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')

    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            
            # Check for coordinates ~5.53 and ~33.14
            has_ra = ('5.53' in report_text or '5.54' in report_text)
            has_dec = ('33.14' in report_text or '33.15' in report_text)

            if has_ra and has_dec:
                score += 15
                feedback.append("Status report contains accurate decimal coordinates")
            elif has_ra or has_dec:
                score += 7
                feedback.append("Status report missing one decimal coordinate")
            else:
                score += 2
                feedback.append("Status report generated but decimal coordinates not found")
        except:
            feedback.append("Status report format invalid")
    else:
        feedback.append("Status report not generated")

    imaging_criteria = (l_count >= 3) + (r_count >= 3) + (ha_count >= 3)
    passed = (score >= 75) and coord_ok and (imaging_criteria >= 2)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }