#!/usr/bin/env python3
"""
Verifier for agn_blazar_outburst_monitoring task.

Occupation: Astronomer / Observatory Operator
Context: Time-domain astronomy, rapid Target of Opportunity (ToO) response for a flaring blazar.

Criteria (100 pts total, pass >= 70):
1. Telescope pointed at Markarian 421 (RA 11h 04m 27s, Dec +38d 12m 32s)  - 20 pts
2. B-band data captured (≥5 FITS files with filter B)                     - 15 pts
3. V-band data captured (≥5 FITS files with filter V)                     - 15 pts
4. R-band data captured (≥5 FITS files with filter R)                     - 15 pts
5. Context image created (xray_context.png exists and created in-task)    - 15 pts
6. ATel response drafted (mentions Mrk 421, B, V, R)                      - 20 pts

Anti-gaming: files must be created after task start.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Mrk 421 true coordinates
MRK421_RA = 11.0741   # hours
MRK421_DEC = 38.2089  # degrees
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


def verify_agn_blazar_outburst_monitoring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_per_filter', 5)

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

    # ── 1. Telescope Pointing (20 pts) ──────────────────────────────────
    coord_ok = False
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, MRK421_RA, MRK421_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOL_ARCMIN:
            score += 20
            coord_ok = True
            feedback.append(f"telescope at Mrk 421 (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 8
            feedback.append(f"telescope near Mrk 421 area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"telescope not at Mrk 421 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("could not read telescope coordinates")

    # ── 2, 3, 4. FITS Filter Counts (15 pts each) ──────────────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_by_filter(filter_name):
        return sum(1 for f in valid_fits if f.get('filter', '').strip().upper() == filter_name)

    b_count = count_by_filter('B')
    v_count = count_by_filter('V')
    r_count = count_by_filter('R')

    for name, count, full_pts in [('B', b_count, 15), ('V', v_count, 15), ('R', r_count, 15)]:
        if count >= min_fits:
            score += full_pts
            feedback.append(f"{name}-band: {count} valid frames")
        elif count >= 2:
            score += full_pts // 2
            feedback.append(f"{name}-band: {count}/{min_fits} frames")
        elif count >= 1:
            score += full_pts // 3
            feedback.append(f"{name}-band: only {count} frame")
        else:
            feedback.append(f"{name}-band: no frames found")

    # ── 5. Context Image (15 pts) ───────────────────────────────────────
    context_exists = result.get('context_exists', False)
    context_mtime = result.get('context_mtime', 0)
    
    if context_exists and context_mtime > task_start:
        score += 15
        feedback.append("context sky image captured")
    elif context_exists:
        feedback.append("context image exists but has pre-task timestamp (gaming attempt)")
    else:
        feedback.append("context sky image not found")

    # ── 6. ATel Response Draft (20 pts) ─────────────────────────────────
    response_exists = result.get('response_exists', False)
    response_mtime = result.get('response_mtime', 0)
    response_b64 = result.get('response_b64', '')
    
    has_target = False
    has_b = False
    has_v = False
    has_r = False

    if response_exists and response_mtime > task_start:
        if response_b64:
            try:
                text = base64.b64decode(response_b64).decode('utf-8', errors='ignore').upper()
                has_target = '421' in text or 'MRK' in text or 'MARKARIAN' in text
                
                # Check for explicit mention of filters (e.g. 'B', 'V', 'R' or 'B-BAND' etc)
                # Pad text to safely check for isolated characters
                padded_text = f" {text} "
                has_b = ' B ' in padded_text or ' B,' in padded_text or ' B-' in padded_text or 'B BAND' in padded_text
                has_v = ' V ' in padded_text or ' V,' in padded_text or ' V-' in padded_text or 'V BAND' in padded_text
                has_r = ' R ' in padded_text or ' R,' in padded_text or ' R-' in padded_text or 'R BAND' in padded_text
            except Exception:
                pass
        
        if has_target and has_b and has_v and has_r:
            score += 20
            feedback.append("ATel response drafted correctly (mentions Mrk 421, B, V, R)")
        elif has_target:
            score += 10
            feedback.append("ATel response mentions target but missing B,V,R confirmation")
        else:
            score += 5
            feedback.append("ATel response exists but lacks target details")
    else:
        feedback.append("ATel response draft not found or pre-dates task")

    # ── Final Assessment ────────────────────────────────────────────────
    # Pass requires >= 70 score, must be pointing at target, and have at least 1 filter completed
    passed = score >= 70 and coord_ok and (b_count >= 5 or v_count >= 5 or r_count >= 5)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }