#!/usr/bin/env python3
"""
Verifier for telescope_collimation_star_test task.

Evaluates multi-device coordination and state logging through prefixes.
"""

import json
import base64
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CAPELLA_RA = 5.278   # hours
CAPELLA_DEC = 45.998 # degrees
COORD_TOL_DEG = 1.0  # 1 degree tolerance

def angular_separation_deg(ra1_h, dec1_deg, ra2_h, dec2_deg):
    ra1 = math.radians(ra1_h * 15.0)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_h * 15.0)
    dec2 = math.radians(dec2_deg)
    cos_sep = (math.sin(dec1) * math.sin(dec2) +
               math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2))
    cos_sep = max(-1.0, min(1.0, cos_sep))
    return math.degrees(math.acos(cos_sep))

def verify_vlm_trajectory(traj, env_info):
    """Fallback VLM validation on trajectory to ensure GUI tools were used."""
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
    except ImportError:
        logger.warning("VLM utility not available, skipping visual validation")
        return 0, "VLM utilities unavailable"

    if not frames:
        return 0, "No trajectory frames captured"

    prompt = """You are verifying an optical maintenance task in a telescope simulator.
Look at this sequence of screenshots. We need to verify that the agent actively operated the software.
Do you see ANY of the following:
1. KStars planetarium view centered on a star.
2. The Ekos or INDI control panel adjusting Focuser, Filter, or CCD settings.
3. FITS viewer or file manager showing captured "focus_50000_" or similar files.
Respond with a JSON object containing a boolean key 'workflow_completed' indicating if there is clear visual evidence of this process."""

    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return 0, "VLM querying function unavailable"
        
    try:
        result = query_vlm(prompt=prompt, images=frames)
        if result.get("success") and result.get("parsed", {}).get("workflow_completed"):
            return 20, "VLM detected active software interaction"
        return 0, "VLM did not detect expected interaction workflow"
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
        return 0, "VLM check failed"

def verify_collimation_star_test(traj, env_info, task_info):
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

    # 1. Hardware Pointing Check (10 pts)
    try:
        final_ra = float(result.get('final_ra', -1))
        final_dec = float(result.get('final_dec', -999))
    except (ValueError, TypeError):
        final_ra, final_dec = -1.0, -999.0

    if final_ra > 0 and final_dec > -900:
        sep_deg = angular_separation_deg(final_ra, final_dec, CAPELLA_RA, CAPELLA_DEC)
        if sep_deg <= COORD_TOL_DEG:
            score += 10
            feedback.append(f"Telescope pointing OK (sep {sep_deg:.2f}°)")
        else:
            feedback.append(f"Telescope not pointing at Capella (sep {sep_deg:.2f}°)")
    else:
        feedback.append("Failed to read telescope pointing")

    # 2. Filter Configuration Check (10 pts)
    filter_slot = result.get('current_filter_slot', -1)
    if filter_slot == 2:
        score += 10
        feedback.append("V-band filter selected")
    else:
        feedback.append(f"Wrong filter selected (slot {filter_slot})")

    # Parse FITS files
    fits_files = result.get('fits_files', [])
    valid_fits = [f for f in fits_files if f.get('mtime', 0) > task_start and f.get('size', 0) > 1024]
    
    def has_prefixed_fits(prefix):
        return any(f.get('name', '').startswith(prefix) for f in valid_fits)

    # 3. Nominal Focus Image (10 pts)
    if has_prefixed_fits("focus_50000_"):
        score += 10
        feedback.append("Nominal FITS found")
    else:
        feedback.append("Nominal FITS (focus_50000_) missing")

    # 4. Intra-Focal Image (10 pts)
    if has_prefixed_fits("focus_40000_"):
        score += 10
        feedback.append("Intra-focal FITS found")
    else:
        feedback.append("Intra-focal FITS (focus_40000_) missing")

    # 5. Extra-Focal Image (10 pts)
    if has_prefixed_fits("focus_60000_"):
        score += 10
        feedback.append("Extra-focal FITS found")
    else:
        feedback.append("Extra-focal FITS (focus_60000_) missing")

    # 6. Context Image Capture (10 pts)
    if result.get('context_exists', False) and result.get('context_mtime', 0) > task_start and result.get('context_size', 0) > 10240:
        score += 10
        feedback.append("Context image successfully generated")
    else:
        feedback.append("Context image missing or invalid")

    # 7. Report File check (10 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_b64 = result.get('report_b64', '')
    
    if report_exists and report_mtime > task_start:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore').upper()
            if "CAPELLA" in report_text:
                score += 10
                feedback.append("Report generated with correct content")
            else:
                score += 5
                feedback.append("Report exists but missing 'Capella'")
        except:
            feedback.append("Failed to decode report text")
    else:
        feedback.append("Report missing or has old timestamp")

    # 8. VLM Trajectory (20 pts)
    v_score, v_feed = verify_vlm_trajectory(traj, env_info)
    score += v_score
    feedback.append(v_feed)

    # Pass logic: Base mechanics (Images, pointing) matter most. Need 70 points.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }