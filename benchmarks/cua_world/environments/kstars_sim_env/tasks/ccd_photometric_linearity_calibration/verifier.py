#!/usr/bin/env python3
"""
Verifier for ccd_photometric_linearity_calibration task.

Occupation: Instrument Engineer
Context: Measuring CCD full-well capacity via a geometric exposure progression.

Criteria (100 pts total, pass >= 65):
1. V-Band Sequence (25 pts): 1s, 2s, 4s, 8s, 16s, 32s FITS in V/ dir
2. B-Band Sequence (25 pts): 1s, 2s, 4s, 8s, 16s, 32s FITS in B/ dir
3. Telescope Pointing (20 pts): Pointed near M67
4. Sky Capture (15 pts): m67_reference.png created during task
5. Engineering Report (15 pts): Report exists, created during task, mentions M67

Anti-Gaming Check:
- Stale files (from year 2024) in V/ are excluded by the mtime > task_start filter.
- FITS must be > 2048 bytes to avoid zero-byte stubs.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# M67 true coordinates
M67_RA = 8.855    # hours (08h 51m 18s)
M67_DEC = 11.8    # degrees (11d 48m 00s)
COORD_TOLERANCE_ARCMIN = 30.0

REQUIRED_EXPTIMES = {1.0, 2.0, 4.0, 8.0, 16.0, 32.0}

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    """Return angular separation in degrees between two equatorial coordinates."""
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_ccd_linearity_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

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

    # ── 1. & 2. Analyze Geometric Sequences (25 pts each) ─────────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    v_exps = set()
    b_exps = set()
    
    for f in valid_fits:
        dname = str(f.get('dir', '')).upper()
        fname = str(f.get('filter', '')).upper()
        expt = round(float(f.get('exptime', -1.0)), 1)
        
        if dname == 'V' or 'V' in fname:
            v_exps.add(expt)
        if dname == 'B' or 'B' in fname:
            b_exps.add(expt)

    # Evaluate V-Band
    v_hits = REQUIRED_EXPTIMES.intersection(v_exps)
    v_score = len(v_hits) * 4
    if len(v_hits) == len(REQUIRED_EXPTIMES):
        v_score = 25  # +1 bonus for full set
    score += v_score
    feedback.append(f"V-band sequence: {len(v_hits)}/{len(REQUIRED_EXPTIMES)} exptimes found")

    # Evaluate B-Band
    b_hits = REQUIRED_EXPTIMES.intersection(b_exps)
    b_score = len(b_hits) * 4
    if len(b_hits) == len(REQUIRED_EXPTIMES):
        b_score = 25  # +1 bonus for full set
    score += b_score
    feedback.append(f"B-band sequence: {len(b_hits)}/{len(REQUIRED_EXPTIMES)} exptimes found")

    # ── 3. Telescope Pointing (20 pts) ────────────────────────────────
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, M67_RA, M67_DEC)
        sep_arcmin = sep_deg * 60.0
        if sep_arcmin <= COORD_TOLERANCE_ARCMIN:
            score += 20
            feedback.append(f"Telescope pointing OK (sep {sep_arcmin:.1f}' from M67)")
        elif sep_arcmin <= COORD_TOLERANCE_ARCMIN * 3:
            score += 8
            feedback.append(f"Telescope near M67 area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope NOT at M67 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read telescope coordinates")

    # ── 4. Sky Capture Image (15 pts) ─────────────────────────────────
    ref_exists = result.get('ref_image_exists', False)
    ref_mtime = result.get('ref_image_mtime', 0)
    
    if ref_exists and ref_mtime > task_start:
        score += 15
        feedback.append("Sky capture reference image successfully generated")
    elif ref_exists:
        feedback.append("Sky capture exists but has old timestamp")
    else:
        feedback.append("Sky capture reference image not found")

    # ── 5. Engineering Report (15 pts) ────────────────────────────────
    rep_exists = result.get('report_exists', False)
    rep_mtime = result.get('report_mtime', 0)
    rep_b64 = result.get('report_content_b64', '')
    
    if rep_exists and rep_mtime > task_start:
        try:
            content = base64.b64decode(rep_b64).decode('utf-8', errors='ignore').upper()
            if 'M67' in content:
                score += 15
                feedback.append("Engineering report created and mentions M67")
            else:
                score += 8
                feedback.append("Engineering report created but missing M67 reference")
        except Exception:
            score += 5
            feedback.append("Engineering report created but unreadable")
    elif rep_exists:
        feedback.append("Report exists but has old timestamp")
    else:
        feedback.append("Engineering report not found")

    # ── Final Evaluation ──────────────────────────────────────────────
    # A pass requires sequences to be heavily populated and telescope at correct position
    passed = score >= 65 and (len(v_hits) >= 4) and (len(b_hits) >= 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "v_exptimes_found": list(v_hits),
            "b_exptimes_found": list(b_hits),
            "final_ra": final_ra,
            "final_dec": final_dec
        }
    }