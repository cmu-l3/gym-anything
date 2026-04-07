#!/usr/bin/env python3
"""
Verifier for agn_reverberation_mapping task.

Occupation: Astrophysicist
Context: Reverberation mapping of Seyfert 1 galaxy NGC 4151.

Criteria (100 pts total, pass >= 60):
1. V-band Continuum Frames (≥10 valid FITS in V/ dir, 60s exposure) - 20 pts
2. H-alpha BLR Frames (≥8 valid FITS in Ha/ dir, 120s exposure) - 20 pts
3. Telescope pointed at NGC 4151 (within 20 arcmin) - 20 pts
4. Strict Directory Isolation (No Ha frames in V/, no V in Ha/) - 15 pts
5. Reference Sky Capture (generated via script) - 15 pts
6. Observation Log (contains target and filter keywords) - 10 pts

Anti-gaming: 
- 3 stale V-band images from 2023 exist. Verification strictly uses mtime > task_start.
- Requires both filter frames to pass.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# NGC 4151 J2000 Coordinates
TARGET_RA = 12.1755    # 12h 10m 32s
TARGET_DEC = 39.4058   # +39d 24m 21s
COORD_TOL_ARCMIN = 20.0


def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))


def verify_agn_reverberation_mapping(traj, env_info, task_info):
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

    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    # --- Directory Validation & Isolation ---
    v_frames = [f for f in valid_fits if f.get('dir') == 'V']
    ha_frames = [f for f in valid_fits if f.get('dir') == 'Ha']

    isolation_failed = False
    
    # Check V-band attributes
    v_correct = 0
    for f in v_frames:
        exptime = f.get('exptime', 0)
        # Accept if near 60s
        if 55 <= exptime <= 65:
            v_correct += 1
        else:
            isolation_failed = True

    # Check Ha-band attributes
    ha_correct = 0
    for f in ha_frames:
        exptime = f.get('exptime', 0)
        # Accept if near 120s
        if 115 <= exptime <= 125:
            ha_correct += 1
        else:
            isolation_failed = True

    # 1. V-Band Continuum Frames (20 pts)
    if v_correct >= 10:
        score += 20
        feedback.append(f"V-band: {v_correct} frames successfully captured")
    elif v_correct >= 5:
        score += 10
        feedback.append(f"V-band: {v_correct}/10 frames captured")
    elif v_correct > 0:
        score += 5
        feedback.append(f"V-band: only {v_correct} frames captured")
    else:
        feedback.append("V-band: No valid 60s frames found in V/ dir")

    # 2. H-alpha BLR Frames (20 pts)
    if ha_correct >= 8:
        score += 20
        feedback.append(f"H-alpha: {ha_correct} frames successfully captured")
    elif ha_correct >= 4:
        score += 10
        feedback.append(f"H-alpha: {ha_correct}/8 frames captured")
    elif ha_correct > 0:
        score += 5
        feedback.append(f"H-alpha: only {ha_correct} frames captured")
    else:
        feedback.append("H-alpha: No valid 120s frames found in Ha/ dir")

    # 3. Telescope Position (20 pts)
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
            feedback.append(f"Telescope correctly pointed at NGC 4151 (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 10
            feedback.append(f"Telescope near NGC 4151 field (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at NGC 4151 (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read telescope coordinates")

    # 4. Strict Directory Isolation (15 pts)
    if not isolation_failed and v_correct > 0 and ha_correct > 0:
        score += 15
        feedback.append("Directory isolation maintained (no filter crossover detected)")
    elif isolation_failed:
        feedback.append("Directory isolation failed (mixed exposure times/filters detected)")
    else:
        feedback.append("Directory isolation: Insufficient frames to verify")

    # 5. Reference Sky Capture (15 pts)
    ref_exists = result.get('reference_exists', False)
    if ref_exists:
        score += 15
        feedback.append("Reference sky capture generated")
    else:
        feedback.append("Reference sky capture missing or pre-dates task")

    # 6. Observation Log (10 pts)
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)
    log_b64 = result.get('log_b64', '')
    
    if log_exists and log_mtime > task_start:
        log_text = ""
        try:
            log_text = base64.b64decode(log_b64).decode('utf-8', errors='ignore').upper()
        except:
            pass
        
        has_target = "NGC 4151" in log_text or "NGC4151" in log_text
        has_v = " V " in f" {log_text} " or "V-BAND" in log_text
        has_ha = "H-ALPHA" in log_text or " HA " in f" {log_text} " or "HA-BAND" in log_text

        if has_target and (has_v or has_ha):
            score += 10
            feedback.append("Observation log valid and contains required keywords")
        else:
            score += 5
            feedback.append("Observation log exists but missing target/filter keywords")
    else:
        feedback.append("Observation log not found or pre-dates task")

    passed = score >= 60 and v_correct > 0 and ha_correct > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }