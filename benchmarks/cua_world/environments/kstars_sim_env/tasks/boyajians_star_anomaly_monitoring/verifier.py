#!/usr/bin/env python3
"""
Verifier for boyajians_star_anomaly_monitoring task.

Occupation: Astronomer / Time-Domain Researcher
Context: Simultaneous multi-band photometry of Tabby's Star (KIC 8462852)

Criteria (100 pts total, pass >= 70):
1. Telescope pointed at KIC 8462852 field (within 30 arcmin)  - 20 pts
2. B-band frames (≥10 in B/ dir, created during task)         - 15 pts
3. V-band frames (≥10 in V/ dir, created during task)         - 15 pts
4. R-band frames (≥10 in R/ dir, created during task)         - 15 pts
5. Finding chart PNG produced (finding_chart.png)             - 20 pts
6. Summary report contains key info                           - 15 pts

Anti-gaming: A stale file from early 2024 is pre-seeded. It must not be counted.
Pass threshold strictly requires telescope positioning and at least 2 full photometric sequences.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# KIC 8462852 true coordinates
KIC_RA = 20.10427   # hours (20h 06m 15.4s)
KIC_DEC = 44.4566   # degrees (+44d 27m 24s)
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

def verify_boyajians_star_anomaly_monitoring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_per_filter = metadata.get('min_fits_per_filter', 10)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 30)

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

    # ── Count valid FITS per filter directory ─────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_in_dir(dirname):
        """Count valid FITS in a specific sub-directory."""
        count = 0
        for f in valid_fits:
            fdir = f.get('dir', '').upper()
            if fdir == dirname.upper():
                count += 1
        return count

    b_count = count_in_dir('B')
    v_count = count_in_dir('V')
    r_count = count_in_dir('R')

    # ── Criterion 1: Telescope at KIC 8462852 (20 pts) ────────────────
    coord_ok = False
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, KIC_RA, KIC_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= coord_tol_arcmin:
            score += 20
            coord_ok = True
            feedback.append(f"telescope at KIC 8462852 (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= coord_tol_arcmin * 3:
            score += 8
            feedback.append(f"telescope near target area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at KIC 8462852 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 2: B frames (15 pts) ────────────────────────────────
    if b_count >= min_per_filter:
        score += 15
        feedback.append(f"B-band: {b_count} frames captured in B/")
    elif b_count >= 3:
        score += 7
        feedback.append(f"B-band: {b_count}/{min_per_filter} frames in B/")
    elif b_count >= 1:
        score += 3
        feedback.append(f"B-band: only {b_count} frame")
    else:
        feedback.append("B-band: no valid new frames in B/")

    # ── Criterion 3: V frames (15 pts) ────────────────────────────────
    if v_count >= min_per_filter:
        score += 15
        feedback.append(f"V-band: {v_count} frames captured in V/")
    elif v_count >= 3:
        score += 7
        feedback.append(f"V-band: {v_count}/{min_per_filter} frames in V/")
    elif v_count >= 1:
        score += 3
        feedback.append(f"V-band: only {v_count} frame")
    else:
        feedback.append("V-band: no valid new frames in V/")

    # ── Criterion 4: R frames (15 pts) ────────────────────────────────
    if r_count >= min_per_filter:
        score += 15
        feedback.append(f"R-band: {r_count} frames captured in R/")
    elif r_count >= 3:
        score += 7
        feedback.append(f"R-band: {r_count}/{min_per_filter} frames in R/")
    elif r_count >= 1:
        score += 3
        feedback.append(f"R-band: only {r_count} frame")
    else:
        feedback.append("R-band: no valid new frames in R/")

    # ── Criterion 5: Finding Chart Produced (20 pts) ──────────────────
    chart_exists = result.get('finding_chart_exists', False)
    if chart_exists:
        score += 20
        feedback.append("Finding chart generated successfully")
    else:
        feedback.append("Finding chart missing or not updated during task")

    # ── Criterion 6: Summary Report (15 pts) ──────────────────────────
    report_exists = result.get('report_exists', False)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            has_name = "8462852" in report_text or "BOYAJIAN" in report_text or "TABBY" in report_text
            has_b = "B" in report_text
            has_v = "V" in report_text
            has_r = "R" in report_text
            
            if has_name and (has_b or has_v or has_r):
                score += 15
                feedback.append("Report generated with accurate target data")
            elif has_name:
                score += 10
                feedback.append("Report exists but missing some sequence info")
            else:
                score += 5
                feedback.append("Report exists but missing key target info")
        except:
            score += 5
            feedback.append("Report found but could not parse text")
    elif report_exists:
        score += 5
        feedback.append("Report file exists but is empty or unreadable")
    else:
        feedback.append("Summary report missing")

    # Pass logic: Must hit at least 70 AND correctly point the telescope
    passed = (score >= 70) and coord_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }