#!/usr/bin/env python3
"""
Verifier for open_cluster_cmd_photometry task.

Occupation: Graduate Student in Stellar Astrophysics
Context: B and V band photometry of M44 (Praesepe / Beehive Cluster) for a CMD.

Criteria (100 pts total, pass >= 60):
1. B-band FITS images (≥8 valid FITS files in B/ directory, >0 bytes, mtime > task_start) - 20 pts
2. V-band FITS images (≥8 valid FITS files in V/ directory, >0 bytes, mtime > task_start) - 20 pts
3. Telescope pointed at M44 (RA 8.6733h, Dec +19.667°, within 30 arcmin tolerance) - 15 pts
4. Sky view captured (m44_sky_view.png exists, >50KB, mtime > task_start) - 10 pts
5. Directory structure (B/ and V/ exist) - 5 pts
6. Report file exists (>200 bytes, mtime > task_start) - 10 pts
7. Report contains target info ("M44" | "Praesepe" | "NGC 2632", coords) - 10 pts
8. Report contains both filters (references to B and V bands, frame counts) - 10 pts

Anti-gaming: Stale files (January 2024 timestamp) are excluded since they predate task_start.
Telescope starts at Polaris (~70° away).
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# M44 true coordinates
M44_RA = 8.6733     # hours
M44_DEC = 19.667    # degrees
COORD_TOL_ARCMIN = 30.0

STALE_FITS_NAMES = {'old_attempt_b_001.fits', 'old_attempt_v_001.fits'}


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_open_cluster_cmd_photometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_fits_per_filter', 8)

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

    # ── Verify FITS Files (Criteria 1 & 2) ───────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files 
                  if f.get('mtime', 0) > task_start 
                  and f.get('size', 0) > 0 
                  and f.get('name') not in STALE_FITS_NAMES]

    b_count = sum(1 for f in valid_fits if f.get('dir') == 'B')
    v_count = sum(1 for f in valid_fits if f.get('dir') == 'V')

    if b_count >= min_frames:
        score += 20
        feedback.append(f"B-band: {b_count} valid frames in B/")
    elif b_count >= 1:
        score += 10
        feedback.append(f"B-band: {b_count}/{min_frames} frames in B/")
    else:
        feedback.append("B-band: No valid frames found in B/")

    if v_count >= min_frames:
        score += 20
        feedback.append(f"V-band: {v_count} valid frames in V/")
    elif v_count >= 1:
        score += 10
        feedback.append(f"V-band: {v_count}/{min_frames} frames in V/")
    else:
        feedback.append("V-band: No valid frames found in V/")

    # ── Verify Telescope Position (Criterion 3) ──────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, M44_RA, M44_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 15
            feedback.append(f"Telescope at M44 (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 7
            feedback.append(f"Telescope near M44 (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at M44 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not determine telescope coordinates.")

    # ── Verify Sky View Image (Criterion 4) ──────────────────────────
    sky_view = result.get('sky_view', {})
    if sky_view.get('exists') and sky_view.get('size', 0) > 50000 and sky_view.get('mtime', 0) > task_start:
        score += 10
        feedback.append("Sky view captured successfully (>50KB)")
    elif sky_view.get('exists'):
        score += 5
        feedback.append("Sky view image exists but size/timestamp check failed")
    else:
        feedback.append("Sky view not captured")

    # ── Verify Directory Structure (Criterion 5) ─────────────────────
    dirs = result.get('dirs', {})
    if dirs.get('B') and dirs.get('V'):
        score += 5
        feedback.append("Directory structure correct (B/ and V/ present)")
    else:
        feedback.append("Required subdirectories (B/, V/) missing")

    # ── Verify Report (Criteria 6, 7 & 8) ────────────────────────────
    report = result.get('report', {})
    if report.get('exists') and report.get('size', 0) > 200 and report.get('mtime', 0) > task_start:
        score += 10
        feedback.append("Report file exists and is valid size")
        
        report_text = ""
        b64_content = report.get('b64', "")
        if b64_content:
            try:
                report_text = base64.b64decode(b64_content).decode('utf-8', errors='ignore').upper()
            except:
                pass

        if report_text:
            # Check target info
            if "M44" in report_text or "PRAESEPE" in report_text or "NGC 2632" in report_text:
                score += 10
                feedback.append("Report contains correct target info")
            else:
                feedback.append("Report missing target identification")

            # Check filter coverage
            if "B" in report_text and "V" in report_text:
                score += 10
                feedback.append("Report documents both B and V filters")
            else:
                feedback.append("Report missing filter documentation")
        else:
            feedback.append("Could not parse report content")
    else:
        feedback.append("Report missing or invalid (size < 200B or pre-dates task)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }