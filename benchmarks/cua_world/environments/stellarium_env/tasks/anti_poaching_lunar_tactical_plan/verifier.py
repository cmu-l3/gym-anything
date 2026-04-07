#!/usr/bin/env python3
"""
Verifier for anti_poaching_lunar_tactical_plan task.

Scoring (100 points):
- Location Skukuza (-24.99°, 31.59°): 20 pts
- Display toggles (Ground OFF: 10, Atmosphere OFF: 10, Azimuthal Grid ON: 10): 30 pts
- Screenshots (>= 3 captured during task): 15 pts
- Tactical Schedule written with correct keywords/formats: 20 pts
- VLM Trajectory (shows dynamic observation of moon/time tracking): 15 pts
"""

import json
import tempfile
import os
import math
import re
import logging
import sys

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)

# Skukuza Coordinates
SKUKUZA_LAT_RAD = math.radians(-24.99)
SKUKUZA_LON_RAD = math.radians(31.59)
LAT_LON_TOLERANCE_RAD = 0.05

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent simulating the Moon's path in Stellarium planetarium software to measure rise and set times.

Review the sequence chronologically and assess:
1. Did the agent manipulate time? (Does the position of the stars/moon, or the time display, change across frames?)
2. Is the Moon visible in at least some of the frames?
3. Did the agent enable the Azimuthal Grid (the blue/green curved altitude and azimuth reference lines)?

Respond in JSON format:
{
    "time_progressed": true/false,
    "moon_visible": true/false,
    "grid_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Briefly explain what you see in the frames."
}"""

def verify_anti_poaching_lunar_tactical_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "anti_poaching_lunar_tactical_plan"
    score = 0
    feedback_parts = []
    
    # 1. Read exported JSON results
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_json_path = tmp.name

        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp_json_path)
            with open(tmp_json_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_json_path):
                os.unlink(tmp_json_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}

    # 2. Location Check (20 pts)
    lat_rad = result.get('lat_rad')
    lon_rad = result.get('lon_rad')
    if lat_rad is not None and lon_rad is not None:
        lat_diff = abs(lat_rad - SKUKUZA_LAT_RAD)
        lon_diff = abs(lon_rad - SKUKUZA_LON_RAD)
        if lat_diff <= LAT_LON_TOLERANCE_RAD and lon_diff <= LAT_LON_TOLERANCE_RAD:
            score += 20
            feedback_parts.append(f"Location set to Skukuza (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
        else:
            feedback_parts.append(f"Wrong location: lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
    else:
        feedback_parts.append("Location not found in config")

    # 3. Display Toggles (30 pts)
    if result.get('flag_landscape') is False:
        score += 10
        feedback_parts.append("Ground disabled")
    else:
        feedback_parts.append("Ground still enabled")

    if result.get('flag_atmosphere') is False:
        score += 10
        feedback_parts.append("Atmosphere disabled")
    else:
        feedback_parts.append("Atmosphere still enabled")

    if result.get('flag_azimuthal_grid') is True:
        score += 10
        feedback_parts.append("Azimuthal grid enabled")
    else:
        feedback_parts.append("Azimuthal grid not enabled")

    # 4. Screenshots (15 pts)
    ss_count = result.get('new_screenshot_count', 0)
    if ss_count >= 3:
        score += 15
        feedback_parts.append(f"{ss_count} screenshots captured")
    elif ss_count > 0:
        score += (ss_count * 5)
        feedback_parts.append(f"Only {ss_count} screenshots captured (needed 3)")
    else:
        feedback_parts.append("No screenshots captured")

    # 5. Tactical Schedule (20 pts)
    schedule_exists = result.get('schedule_exists', False)
    if schedule_exists:
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
                tmp_txt_path = tmp.name
            
            copy_from_env(task_info['metadata']['schedule_path'], tmp_txt_path)
            with open(tmp_txt_path, 'r') as f:
                schedule_content = f.read().lower()
                
            os.unlink(tmp_txt_path)
            
            content_score = 0
            if "rise" in schedule_content: content_score += 4
            if "transit" in schedule_content: content_score += 4
            if "set" in schedule_content: content_score += 4
            
            # Check for valid time formats HH:MM
            times = re.findall(r'\b(?:[01]?\d|2[0-3]):[0-5]\d\b', schedule_content)
            if len(times) >= 3:
                content_score += 8
            elif len(times) > 0:
                content_score += 4
                
            score += content_score
            feedback_parts.append(f"Schedule evaluation: {content_score}/20 pts (Found {len(times)} times)")
            
        except Exception as e:
            feedback_parts.append(f"Failed to read schedule file: {e}")
    else:
        feedback_parts.append("Schedule file not created")

    # 6. VLM Trajectory Verification (15 pts)
    try:
        frames = sample_trajectory_frames(traj, n=6)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                vlm_score = 0
                if parsed.get("time_progressed"): vlm_score += 5
                if parsed.get("moon_visible"): vlm_score += 5
                if parsed.get("grid_visible"): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM verified trajectory ({vlm_score}/15 pts)")
            else:
                feedback_parts.append("VLM verification failed to parse")
        else:
            feedback_parts.append("No trajectory frames for VLM")
    except Exception as e:
        logger.warning(f"VLM Exception: {e}")
        feedback_parts.append("VLM verification skipped (error)")

    # 7. Final Assessment
    passed = score >= 70 and (ss_count >= 1) and schedule_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }