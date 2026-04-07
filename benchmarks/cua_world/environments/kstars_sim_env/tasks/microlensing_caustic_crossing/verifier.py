#!/usr/bin/env python3
"""
Verifier for microlensing_caustic_crossing task.

Criteria (100 pts total, pass >= 60):
1. Telescope Unparked & Tracking (10 pts)
2. Telescope pointed at Galactic Bulge target (20 pts)
3. ≥15 valid FITS files in correct directory (15 pts)
4. FITS files use R-band (Slot 4) and 15s exposures (15 pts)
5. Response log created correctly (15 pts)
6. Sky View field captured (10 pts)
7. VLM Trajectory Process Verification (15 pts)
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_RA = 17.90888
TARGET_DEC = -30.2125
COORD_TOL_ARCMIN = 30.0

VLM_TRAJECTORY_PROMPT = """You are verifying an agent operating KStars/Ekos for astronomical imaging.
Look at these chronological trajectory frames. Did the agent:
1. Open and interact with the Ekos observatory control interface?
2. Unpark the telescope and slew it?
3. Configure and run a CCD capture sequence?

Respond ONLY in valid JSON format exactly like this:
{
    "ekos_used": true/false,
    "telescope_slewed": true/false,
    "capture_run": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_microlensing_caustic_crossing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    min_fits = metadata.get('min_fits_count', 15)
    req_exp = metadata.get('required_exposure_sec', 15)

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

    # ── 1. Unparked & Tracking (10 pts) ──────────────────────────────
    unpark_state = result.get('unpark_state', '')
    track_state = result.get('track_state', '')
    
    if unpark_state == "On" and track_state == "On":
        score += 10
        feedback.append("Telescope unparked and tracking enabled")
    elif unpark_state == "On":
        score += 5
        feedback.append("Telescope unparked, but tracking not explicitly on")
    else:
        feedback.append("Telescope remained parked")

    # ── 2. Coordinates (20 pts) ──────────────────────────────────────
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
            feedback.append(f"Telescope pointed correctly (sep {sep_arcmin:.1f}')")
        elif sep_arcmin <= COORD_TOL_ARCMIN * 3:
            score += 10
            feedback.append(f"Telescope near target area (sep {sep_arcmin:.1f}')")
        else:
            feedback.append(f"Telescope not at target (sep {sep_arcmin:.1f}')")
    else:
        feedback.append("Could not read telescope coordinates")

    # ── 3. FITS Count (15 pts) & 4. FITS Settings (15 pts) ───────────
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]
    valid_count = len(valid_fits)

    if valid_count >= min_fits:
        score += 15
        feedback.append(f"Captured {valid_count} FITS images")
    elif valid_count >= 5:
        score += 8
        feedback.append(f"Captured {valid_count}/{min_fits} FITS images")
    else:
        feedback.append(f"Insufficient FITS images ({valid_count})")

    if valid_count > 0:
        # Check exposure and filter of the FIRST valid frame
        first_frame = valid_fits[0]
        filt = first_frame.get('filter', '').upper()
        exp = first_frame.get('exptime', -1)
        
        settings_ok = 0
        if 'R' in filt or filt == 'R-BAND' or filt == 'SLOT4':
            settings_ok += 7
            feedback.append("R-band filter verified")
        else:
            feedback.append(f"Wrong filter used: {filt}")
            
        if abs(exp - req_exp) < 1.0:
            settings_ok += 8
            feedback.append("15s exposure verified")
        else:
            feedback.append(f"Wrong exposure used: {exp}s")
            
        score += settings_ok

    # ── 5. Response Log (15 pts) ─────────────────────────────────────
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    if report_exists and report_mtime > task_start:
        report_b64 = result.get('report_content_b64', '')
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            if "OGLE-2026-BLG-0042" in report_text:
                score += 15
                feedback.append("Valid response log found")
            else:
                score += 5
                feedback.append("Response log missing OGLE designation")
        except:
            feedback.append("Could not decode response log")
    else:
        feedback.append("Response log missing or pre-dates task")

    # ── 6. Sky View (10 pts) ─────────────────────────────────────────
    if result.get('sky_capture_exists', False):
        score += 10
        feedback.append("Sky view captured")
    else:
        feedback.append("Sky view missing")

    # ── 7. VLM Trajectory (10 pts) ───────────────────────────────────
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and hasattr(traj, 'get_frames'):
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                vlm_res = query_vlm(prompt=VLM_TRAJECTORY_PROMPT, images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('ekos_used'): vlm_score += 3
                    if parsed.get('telescope_slewed'): vlm_score += 3
                    if parsed.get('capture_run'): vlm_score += 4
                    feedback.append(f"VLM verified trajectory (+{vlm_score} pts)")
                else:
                    logger.warning("VLM evaluation failed to parse JSON")
        except Exception as e:
            logger.warning(f"VLM Evaluation error: {e}")
            
    score += vlm_score

    # Determine pass/fail
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }