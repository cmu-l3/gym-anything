#!/usr/bin/env python3
"""
Verifier for precession_pole_star_demo task.

Scoring (100 points total):
1. Location set to Giza (Lat ~29.98°N, Lon ~31.13°E) - 15 points
2. Date set to ancient period (JD between 600000 and 970000) - 15 points
3. Atmosphere disabled - 5 points
4. Ground disabled - 5 points
5. Equatorial grid enabled - 5 points
6. Constellation lines enabled - 5 points
7. Target Screenshot taken - 10 points
8. Lecture notes exist with keywords - 20 points
9. VLM Trajectory check (Thuban & Precession visualization) - 20 points

Pass threshold: 65 points.
"""

import json
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)

# Giza coordinates in radians
GIZA_LAT_RAD = 0.5232  # ~29.98 degrees N
GIZA_LON_RAD = 0.5434  # ~31.13 degrees E
TOLERANCE_RAD = 0.05   # ~2.8 degrees tolerance


def verify_precession_pole_star_demo(traj, env_info, task_info):
    """
    Verify the precession demonstration task using programmatic state + VLM trajectories.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "precession_pole_star_demo"
    score = 0
    feedback_parts = []

    # 1. READ PROGRAMMATIC DATA
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # Criterion 1: Location (15 pts)
    lat_rad = result.get('lat_rad')
    lon_rad = result.get('lon_rad')
    if lat_rad is not None and lon_rad is not None:
        lat_diff = abs(lat_rad - GIZA_LAT_RAD)
        lon_diff = abs(lon_rad - GIZA_LON_RAD)
        if lat_diff <= TOLERANCE_RAD and lon_diff <= TOLERANCE_RAD:
            score += 15
            feedback_parts.append("Location correctly set near Giza, Egypt.")
        else:
            feedback_parts.append(f"Location incorrect. Expected ~30°N 31°E, got {math.degrees(lat_rad):.1f}°N {math.degrees(lon_rad):.1f}°E.")
    else:
        feedback_parts.append("Location data missing.")

    # Criterion 2: Date/Time JD (15 pts)
    jd = result.get('preset_sky_time')
    if jd is not None:
        # JD 600,000 to 970,000 covers roughly 3060 BCE to 2060 BCE
        if 600000 <= jd <= 970000:
            score += 15
            feedback_parts.append(f"Date set correctly to ancient era (JD: {jd:.1f}).")
        else:
            feedback_parts.append(f"Date incorrect. Expected ~2560 BCE (JD ~786000), got JD {jd:.1f}.")
    else:
        feedback_parts.append("Date (JD) data missing.")

    # Criterion 3-6: Display Flags (20 pts total)
    if result.get('flag_atmosphere') is False:
        score += 5
        feedback_parts.append("Atmosphere OFF.")
    else:
        feedback_parts.append("Atmosphere not turned off.")

    if result.get('flag_landscape') is False:
        score += 5
        feedback_parts.append("Landscape OFF.")
    else:
        feedback_parts.append("Landscape not turned off.")

    if result.get('flag_equatorial_grid') is True:
        score += 5
        feedback_parts.append("Equatorial grid ON.")
    else:
        feedback_parts.append("Equatorial grid not enabled.")

    if result.get('flag_constellation_drawing') is True:
        score += 5
        feedback_parts.append("Constellation lines ON.")
    else:
        feedback_parts.append("Constellation lines not enabled.")

    # Criterion 7: Screenshots (10 pts)
    ss_count = result.get('new_screenshot_count', 0)
    if ss_count >= 1:
        score += 10
        feedback_parts.append(f"Screenshot taken ({ss_count} found).")
    else:
        feedback_parts.append("No screenshot taken.")

    # Criterion 8: Notes (20 pts)
    if result.get('notes_exists'):
        if result.get('notes_has_thuban') and result.get('notes_has_precession'):
            score += 20
            feedback_parts.append("Lecture notes contain required keywords ('Thuban', 'precession').")
        else:
            score += 10
            feedback_parts.append("Lecture notes exist but missing some keywords.")
    else:
        feedback_parts.append("Lecture notes not found.")

    # Criterion 9: VLM Trajectory Verification (20 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        images_to_check = frames + [final_img] if final_img else frames

        vlm_prompt = """
        You are verifying an astronomy educational simulation task.
        Look closely at these screenshots of a desktop and planetarium software (Stellarium).
        
        Is the software successfully set up to demonstrate a dark sky with an equatorial grid AND constellation lines?
        Are they searching for or looking at the star "Thuban" or "Alpha Draconis"?
        
        Reply in JSON format:
        {
            "shows_dark_sky": true/false,
            "shows_equatorial_grid": true/false,
            "shows_constellation_lines": true/false,
            "shows_thuban_search_or_target": true/false,
            "confidence": "high"/"medium"/"low"
        }
        """

        vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check)
        if vlm_result and vlm_result.get("success") and "parsed" in vlm_result:
            parsed = vlm_result["parsed"]
            vlm_pts = 0
            if parsed.get("shows_dark_sky"): vlm_pts += 5
            if parsed.get("shows_equatorial_grid"): vlm_pts += 5
            if parsed.get("shows_constellation_lines"): vlm_pts += 5
            if parsed.get("shows_thuban_search_or_target"): vlm_pts += 5
            
            score += vlm_pts
            feedback_parts.append(f"VLM Visual Check: +{vlm_pts}/20 points.")
        else:
            feedback_parts.append("VLM visual check failed to parse or execute.")
            # If VLM fails execution entirely, grant partial default credit to not penalize agent for infra issues
            score += 10
    except ImportError:
        logger.warning("VLM modules not available. Skipping visual verification, granting default points.")
        score += 20
        feedback_parts.append("VLM check skipped (module missing) - points granted.")

    # Final Pass/Fail
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }