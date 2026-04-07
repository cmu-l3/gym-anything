#!/usr/bin/env python3
"""
Verifier for grb_too_response task.

Occupation: Observatory Operator
Context: Target-of-Opportunity (ToO) protocol for GRB 221009A

Criteria (100 pts total, pass >= 60):
1. Confirmation images (>=3 in confirmation/, exptime ~10s)    - 15 pts
2. Science images (>=10 in science/, exptime ~30s)             - 25 pts
3. Luminance filter used (Slot 1)                              - 10 pts
4. Telescope pointed at GRB (within 15 arcmin)                 - 20 pts
5. GCN report file exists and created during task              - 10 pts
6. GCN report content valid (contains target, RA/Dec, counts)  - 15 pts
7. Sky view image captured (>= 50KB)                           - 5 pts
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# GRB 221009A coordinates
GRB_RA = 19.2176
GRB_DEC = 19.7733
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


def verify_grb_too_response(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_conf_frames = metadata.get('min_conf_frames', 3)
    min_sci_frames = metadata.get('min_sci_frames', 10)
    req_filter_slot = metadata.get('required_filter_slot', 1)

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
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # ── Criterion 1 & 2: Confirmation and Science Frames ───────────────
    conf_count = sum(1 for f in valid_fits if f.get('dir') == 'confirmation')
    sci_count = sum(1 for f in valid_fits if f.get('dir') == 'science')

    # Verify exposure times if available
    conf_exptimes_ok = all(abs(f.get('exptime', 10) - 10) < 2 for f in valid_fits if f.get('dir') == 'confirmation')
    sci_exptimes_ok = all(abs(f.get('exptime', 30) - 30) < 2 for f in valid_fits if f.get('dir') == 'science')

    # Confirmation Score (15 pts)
    if conf_count >= min_conf_frames:
        if conf_exptimes_ok:
            score += 15
            feedback.append(f"confirmation phase: {conf_count} frames (correct exposure)")
        else:
            score += 10
            feedback.append(f"confirmation phase: {conf_count} frames (exposure times varied)")
    elif conf_count > 0:
        score += 5
        feedback.append(f"confirmation phase: incomplete ({conf_count}/{min_conf_frames} frames)")
    else:
        feedback.append("confirmation phase: no frames found in confirmation/")

    # Science Score (25 pts)
    if sci_count >= min_sci_frames:
        if sci_exptimes_ok:
            score += 25
            feedback.append(f"science phase: {sci_count} frames (correct exposure)")
        else:
            score += 15
            feedback.append(f"science phase: {sci_count} frames (exposure times varied)")
    elif sci_count > 0:
        score += 10
        feedback.append(f"science phase: incomplete ({sci_count}/{min_sci_frames} frames)")
    else:
        feedback.append("science phase: no frames found in science/")

    # ── Criterion 3: Filter (10 pts) ───────────────────────────────────
    filter_slot = result.get('current_filter_slot', -1)
    filter_headers = [str(f.get('filter', '')).upper() for f in valid_fits if f.get('filter')]
    
    filter_ok = False
    if filter_slot == req_filter_slot:
        filter_ok = True
    elif any('LUMINANCE' in fh or 'CLEAR' in fh or fh == 'L' for fh in filter_headers):
        filter_ok = True

    if filter_ok:
        score += 10
        feedback.append("Clear/Luminance filter used")
    else:
        feedback.append(f"Clear/Luminance filter not verified (slot {filter_slot})")

    # ── Criterion 4: Telescope Coordinates (20 pts) ────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, GRB_RA, GRB_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 20
            feedback.append(f"telescope at GRB target (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 8
            feedback.append(f"telescope near GRB target (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at GRB target (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── Criterion 5 & 6: GCN Report (10 + 15 pts) ──────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    report_created = report_exists and report_mtime > task_start

    if report_created:
        score += 10
        feedback.append("GCN circular file created")
        
        # Check Content
        content_score = 0
        try:
            text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            if '221009A' in text:
                content_score += 5
            if '19H' in text or '19:13' in text or '288.' in text or '19.2' in text:
                content_score += 5  # Has RA
            if 'CONFIRMATION' in text or 'SCIENCE' in text or '10S' in text or '30S' in text:
                content_score += 5  # Has protocol details
                
            score += content_score
            feedback.append(f"GCN content valid ({content_score}/15 pts)")
        except Exception:
            feedback.append("Failed to parse GCN content")
    else:
        feedback.append("GCN circular not found or not created during task")

    # ── Criterion 7: Sky View (5 pts) ──────────────────────────────────
    sky_exists = result.get('sky_view_exists', False)
    sky_size = result.get('sky_view_size', 0)
    
    if sky_exists and sky_size >= 50000:
        score += 5
        feedback.append("sky view captured successfully")
    elif sky_exists:
        feedback.append("sky view captured but file too small (invalid)")
    else:
        feedback.append("sky view not captured")

    # ── Final Evaluation ───────────────────────────────────────────────
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "conf_count": conf_count,
            "sci_count": sci_count,
            "report_created": report_created,
            "sky_captured": sky_exists
        }
    }