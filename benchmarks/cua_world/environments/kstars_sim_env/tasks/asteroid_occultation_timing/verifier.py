#!/usr/bin/env python3
"""
Verifier for asteroid_occultation_timing task.

Occupation: Astronomer / IOTA Occultation Observer
Context: Rapid-cadence photometric monitoring of an asteroid occultation ((52) Europa)

Criteria (100 pts total, pass >= 60):
1. FITS images captured (≥40 in correct dir, newly created)  - 25 pts
2. Rapid cadence confirmed (40 frames implies short exptime) - 15 pts
3. Telescope pointed at target star (within 15 arcmin)       - 20 pts
4. Clear filter selected (slot 1)                            - 5 pts
5. Sky view captured (exists & size > 50KB)                  - 10 pts
6. IOTA report file created during task                      - 10 pts
7. Report content valid (mentions target & parameters)       - 15 pts
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target TYC 6815-00874-1 coordinates
TARGET_RA = 17.2117    # hours
TARGET_DEC = -24.8583  # degrees
COORD_TOLERANCE_ARCMIN = 15.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    """Calculate angular separation in degrees between equatorial coordinates."""
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_asteroid_occultation_timing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 40)
    req_filter_slot = metadata.get('required_filter_slot', 1)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 15.0)

    # Load result file
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

    # ── Criteria 1 & 2: FITS images and Cadence (25 pts + 15 pts) ──────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files 
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    # FITS existence points
    if valid_count >= min_fits:
        score += 25
        feedback.append(f"captured {valid_count} valid FITS images (full requirement)")
    elif valid_count >= 20:
        score += 15
        feedback.append(f"captured {valid_count}/{min_fits} FITS images (partial)")
    elif valid_count >= 5:
        score += 5
        feedback.append(f"captured {valid_count}/{min_fits} FITS images (insufficient sequence)")
    else:
        feedback.append("no valid FITS images captured in target directory")

    # Rapid cadence points (achieving 40+ frames inside the timeout requires short exposures)
    if valid_count >= min_fits:
        score += 15
        feedback.append("rapid-cadence confirmed via frame count threshold")

    # ── Criterion 3: Telescope at Target (20 pts) ────────────────────────
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
            feedback.append(f"telescope pointed at target star (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= coord_tol_arcmin * 3:
            score += 10
            feedback.append(f"telescope near target area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at target star (sep {sep_arcmin:.1f}' away)")
    else:
        feedback.append("could not verify telescope coordinates")

    # ── Criterion 4: Clear Filter Selected (5 pts) ───────────────────────
    filter_slot = result.get('current_filter_slot', -1)
    # Check headers of captured files as fallback
    used_filters = set([str(f.get('filter', '')).upper() for f in valid_fits if f.get('filter')])
    
    filter_ok = False
    if filter_slot == req_filter_slot:
        filter_ok = True
    elif any(f in ('CLEAR', 'LUM', 'L', 'LUMINANCE') for f in used_filters):
        filter_ok = True

    if filter_ok:
        score += 5
        feedback.append("clear/luminance filter correctly used")
    else:
        feedback.append("clear/luminance filter use not verified")

    # ── Criterion 5: Sky View Captured (10 pts) ──────────────────────────
    sky_exists = result.get('sky_capture_exists', False)
    sky_size = result.get('sky_capture_size', 0)

    if sky_exists and sky_size > 50000:  # >50KB ensures it's a real image
        score += 10
        feedback.append("sky view image captured successfully")
    elif sky_exists:
        score += 5
        feedback.append("sky view image exists but file size suspiciously small")
    else:
        feedback.append("sky view image not found")

    # ── Criterion 6: Report File Exists (10 pts) ─────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)

    if report_exists and report_mtime > task_start:
        score += 10
        feedback.append("IOTA report file created during task")
    elif report_exists:
        feedback.append("report file exists but pre-dates task start")
    else:
        feedback.append("IOTA report file not found")

    # ── Criterion 7: Report Content Valid (15 pts) ───────────────────────
    report_b64 = result.get('report_content_b64', '')
    if report_b64 and report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            
            has_target = "(52) EUROPA" in report_text
            has_star = "TYC 6815" in report_text
            has_exposure = "EXPOSURE" in report_text or "2S" in report_text
            has_frames = "NUM_FRAMES" in report_text or "40" in report_text
            
            if has_target and has_star:
                score += 10
                feedback.append("report identifies correct event targets")
                if has_exposure and has_frames:
                    score += 5
                    feedback.append("report includes required exposure/frame metadata")
                else:
                    feedback.append("report missing exposure/frame fields")
            else:
                feedback.append("report content does not correctly identify the event")
        except Exception:
            feedback.append("could not decode report content")
    else:
        if not report_exists:
            feedback.append("cannot verify report content (file missing)")

    # ── Final Verdict ──────────────────────────────────────────────────
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }