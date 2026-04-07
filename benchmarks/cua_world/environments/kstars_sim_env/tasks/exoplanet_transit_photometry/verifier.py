#!/usr/bin/env python3
"""
Verifier for exoplanet_transit_photometry task.

Criteria (100 pts total, pass >= 60):
1. FITS images captured (≥15 frames, >0s exp, in correct dir)  - 25 pts
2. V-band filter used (INDI slot or FITS header)               - 10 pts
3. Telescope pointed at HD 189733 (within 15 arcmin)           - 20 pts
4. Focuser defocused (~30500)                                  - 10 pts
5. Sky view captured (sky_view.png)                            - 10 pts
6. Transit log exists                                          - 10 pts
7. Transit log valid content (HD 189733, V, HD 189585, etc)    - 15 pts

Anti-gaming protections check file timestamps against task start time.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# HD 189733 true coordinates
TARGET_RA = 20.01214   # hours
TARGET_DEC = 22.71086  # degrees

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_exoplanet_transit_photometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 15)
    req_filter_slot = metadata.get('required_filter_slot', 2)
    req_focus = metadata.get('required_defocus_position', 30500)
    focus_tol = metadata.get('defocus_tolerance', 200)
    coord_tol_arcmin = metadata.get('coordinate_tolerance_arcmin', 15.0)

    # ── Load result file ──────────────────────────────────────────────
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

    # ── Criterion 1: FITS images (25 pts) ─────────────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files 
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    if valid_count >= min_fits:
        score += 25
        feedback.append(f"Captured {valid_count} FITS images (goal: ≥{min_fits})")
    elif valid_count >= 10:
        score += 15
        feedback.append(f"Captured {valid_count} FITS images (partial credit)")
    elif valid_count >= 1:
        score += 5
        feedback.append(f"Captured only {valid_count} FITS image(s)")
    else:
        feedback.append(f"No valid FITS images found in upload directory")

    # ── Criterion 2: V-band filter used (10 pts) ──────────────────────
    filter_slot = result.get('current_filter_slot', -1)
    
    # Check headers of captured files if slot check fails
    filter_in_header = any('V' in str(f.get('filter', '')).upper() for f in valid_fits)
    
    if filter_slot == req_filter_slot or filter_in_header:
        score += 10
        feedback.append("V-band filter correctly used")
    else:
        feedback.append(f"V-band filter not verified (slot={filter_slot})")

    # ── Criterion 3: Telescope pointed at HD 189733 (20 pts) ──────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    coord_ok = False
    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, TARGET_RA, TARGET_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= coord_tol_arcmin:
            score += 20
            feedback.append(f"Telescope pointed at HD 189733 (sep {sep_arcmin:.1f}')")
            coord_ok = True
        elif sep_arcmin <= coord_tol_arcmin * 3:
            score += 10
            feedback.append(f"Telescope near HD 189733 area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at HD 189733 (sep {sep_arcmin:.1f}' from target)")
    else:
        feedback.append("Could not read telescope coordinates")

    # ── Criterion 4: Focuser defocused (10 pts) ───────────────────────
    try:
        current_focus = float(result.get('current_focus', -1))
    except (ValueError, TypeError):
        current_focus = -1.0
        
    if abs(current_focus - req_focus) <= focus_tol:
        score += 10
        feedback.append(f"Focuser correctly defocused ({current_focus})")
    elif current_focus == 30000:
        feedback.append("Focuser left at nominal 30000 position (not defocused)")
    else:
        feedback.append(f"Focuser position incorrect ({current_focus})")

    # ── Criterion 5: Sky view captured (10 pts) ───────────────────────
    sky_capture_exists = result.get('sky_capture_exists', False)
    sky_mtime = result.get('sky_capture_mtime', 0)
    
    if sky_capture_exists and sky_mtime > task_start:
        score += 10
        feedback.append("Sky view PNG correctly captured")
    else:
        feedback.append("Sky view PNG missing or pre-dates task")

    # ── Criterion 6 & 7: Transit log file (25 pts total) ──────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_during_task = report_exists and (report_mtime > task_start)

    if report_during_task:
        score += 10
        feedback.append("Transit log created during task")
        
        # Verify Content (15 pts)
        report_b64 = result.get('report_content_b64', '')
        if report_b64:
            try:
                report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
                
                has_target = '189733' in report_text
                has_filter = 'FILTER' in report_text and 'V' in report_text
                has_comp = '189585' in report_text
                
                content_pts = 0
                if has_target: content_pts += 5
                if has_filter: content_pts += 5
                if has_comp: content_pts += 5
                
                score += content_pts
                feedback.append(f"Transit log content score: {content_pts}/15")
            except Exception as e:
                feedback.append(f"Could not parse transit log: {e}")
        else:
            feedback.append("Transit log is empty")
    else:
        feedback.append("Transit log missing or not created during task")

    passed = score >= 60 and coord_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }