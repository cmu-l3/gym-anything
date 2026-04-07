#!/usr/bin/env python3
"""
Verifier for polar_night_lighting_ref task.

Scoring System (100 points total):
- Location latitude correct (15 pts) - ~69.65°N / 1.2156 rad
- Location longitude correct (10 pts) - ~18.96°E / 0.3309 rad
- Atmosphere enabled (10 pts)
- Ground/landscape disabled (10 pts)
- Constellation lines enabled (8 pts)
- Constellation names enabled (7 pts)
- Azimuthal grid enabled (8 pts)
- Cardinal points enabled (7 pts)
- 3+ screenshots captured and VLM verification of interaction (15 pts)
- Lighting notes file valid (10 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import math
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth values for Tromsø, Norway
TROMSO_LAT_RAD = 1.21561   # 69.6492 degrees N
TROMSO_LON_RAD = 0.33083   # 18.9553 degrees E
LAT_LON_TOLERANCE_RAD = 0.05  # ~2.8 degrees tolerance (generous for city area)

def verify_polar_night_lighting_ref(traj, env_info, task_info):
    """
    Verify the agent successfully configured the polar night lighting reference.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env("/tmp/task_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []
        
        # ── 1. Location Latitude (15 pts) & Longitude (10 pts) ──────────────
        lat_rad = result.get('lat_rad')
        lon_rad = result.get('lon_rad')

        # Check if user actually changed from Guereins default (~46N)
        if lat_rad is not None and lon_rad is not None:
            lat_diff = abs(lat_rad - TROMSO_LAT_RAD)
            lon_diff = abs(lon_rad - TROMSO_LON_RAD)

            if lat_diff <= LAT_LON_TOLERANCE_RAD:
                score += 15
                feedback_parts.append(f"Latitude correct ({math.degrees(lat_rad):.2f}° N)")
            else:
                feedback_parts.append(f"Latitude wrong: expected ~69.65°N, got {math.degrees(lat_rad):.2f}°")

            if lon_diff <= LAT_LON_TOLERANCE_RAD:
                score += 10
                feedback_parts.append(f"Longitude correct ({math.degrees(lon_rad):.2f}° E)")
            else:
                feedback_parts.append(f"Longitude wrong: expected ~18.96°E, got {math.degrees(lon_rad):.2f}°")
        else:
            feedback_parts.append("Location data missing")

        # ── 2. Display Flags Configuration (50 pts total) ───────────────────
        flags = {
            "flag_atmosphere": (True, 10, "Atmosphere ON"),
            "flag_landscape": (False, 10, "Landscape OFF"),
            "flag_constellation_drawing": (True, 8, "Constellation lines ON"),
            "flag_constellation_name": (True, 7, "Constellation names ON"),
            "flag_azimuthal_grid": (True, 8, "Azimuthal grid ON"),
            "flag_cardinal_points": (True, 7, "Cardinal points ON")
        }

        for flag_name, (expected, pts, msg) in flags.items():
            actual = result.get(flag_name)
            if actual is expected:
                score += pts
                feedback_parts.append(msg)
            else:
                feedback_parts.append(f"Failed {msg} (was {actual})")

        # ── 3. Screenshots Evaluation (15 pts) ──────────────────────────────
        # To get full 15 points, agent must have created 3+ screenshots
        new_ss = result.get('new_screenshot_count', 0)
        
        # We also want to integrate VLM verification on trajectory to ensure no spoofing
        vlm_passed = False
        if 'query_vlm' in env_info:
            from gym_anything.vlm import sample_trajectory_frames
            try:
                frames = sample_trajectory_frames(traj, n=3)
                if frames:
                    vlm_prompt = (
                        "Look at these screenshots of a user interacting with Stellarium. "
                        "Did the user configure the interface to look at the sky with a dark blue/twilight color, "
                        "and are there visible UI elements like grids, star labels, or constellation lines? "
                        "Reply purely with YES or NO."
                    )
                    vlm_response = env_info['query_vlm'](images=frames, prompt=vlm_prompt)
                    if vlm_response and "YES" in str(vlm_response).upper():
                        vlm_passed = True
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")

        if new_ss >= 3:
            if vlm_passed or 'query_vlm' not in env_info:
                score += 15
                feedback_parts.append(f"{new_ss} screenshots captured & visually verified")
            else:
                score += 8  # Partial points if VLM couldn't verify visual changes
                feedback_parts.append(f"{new_ss} screenshots captured (VLM visual confirmation failed/skipped)")
        elif new_ss > 0:
            score += 5
            feedback_parts.append(f"Only {new_ss} screenshots captured (expected 3)")
        else:
            feedback_parts.append("No screenshots captured")

        # ── 4. Notes File Evaluation (10 pts) ───────────────────────────────
        notes_exists = result.get('notes_exists', False)
        if notes_exists:
            matches = 0
            if result.get('notes_has_tromso', False): matches += 1
            if result.get('notes_has_date', False): matches += 1
            if result.get('notes_has_targets', False): matches += 1
            
            if matches >= 2:
                score += 10
                feedback_parts.append("Valid production notes file written")
            elif matches == 1:
                score += 5
                feedback_parts.append("Notes file written but missing expected target details")
            else:
                feedback_parts.append("Notes file exists but lacks required keywords")
        else:
            feedback_parts.append("Production notes file not created")

        # ── Final Determination ─────────────────────────────────────────────
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification script error: {str(e)}"
        }