#!/usr/bin/env python3
"""
Verifier for lunar_eclipse_event_planner task.

Scoring (100 points total, Pass threshold: 70):
1. Location Configuration (20 pts)
   - Latitude/Longitude near New York City
2. Display Configuration (30 pts)
   - Atmosphere disabled (10 pts)
   - Azimuthal grid enabled (10 pts)
   - Constellation lines enabled (10 pts)
3. Screenshot Captured (20 pts)
   - At least 1 new screenshot in the folder
4. Event Guide Written (30 pts)
   - File exists and created during task (15 pts)
   - Contains required keywords: New York, Date, Target (15 pts)
"""

import json
import os
import math
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_lunar_eclipse_event_planner(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    task_name = "lunar_eclipse_event_planner"
    metadata = task_info.get('metadata', {})
    
    expected_lat = metadata.get('expected_lat_rad', 0.71052)
    expected_lon = metadata.get('expected_lon_rad', -1.29154)
    tolerance = metadata.get('lat_lon_tolerance', 0.10)
    
    score = 0
    feedback_parts = []
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
            
        copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
        
        with open(tmp_path, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load task results: {str(e)}"
        }
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
            
    config = result.get('config', {})
    screenshots = result.get('screenshots', {})
    guide_file = result.get('guide_file', {})
    
    # ── 1. Location Configuration (20 points) ──
    lat_rad = config.get('lat_rad')
    lon_rad = config.get('lon_rad')
    
    location_passed = False
    if lat_rad is not None and lon_rad is not None:
        lat_diff = abs(lat_rad - expected_lat)
        lon_diff = abs(lon_rad - expected_lon)
        
        if lat_diff <= tolerance and lon_diff <= tolerance:
            score += 20
            location_passed = True
            feedback_parts.append(f"Location set correctly (lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°)")
        else:
            feedback_parts.append(f"Incorrect location. Expected near NY (40.71°N, 74.00°W), got lat={math.degrees(lat_rad):.2f}°, lon={math.degrees(lon_rad):.2f}°")
    else:
        feedback_parts.append("Location configuration not found.")

    # ── 2. Display Configuration (30 points) ──
    flag_atmosphere = config.get('flag_atmosphere')
    if flag_atmosphere is False:
        score += 10
        feedback_parts.append("Atmosphere successfully disabled.")
    else:
        feedback_parts.append("Atmosphere was not disabled.")
        
    flag_azimuthal = config.get('flag_azimuthal_grid')
    if flag_azimuthal is True:
        score += 10
        feedback_parts.append("Azimuthal grid enabled.")
    else:
        feedback_parts.append("Azimuthal grid not enabled.")
        
    flag_constellation = config.get('flag_constellation_drawing')
    if flag_constellation is True:
        score += 10
        feedback_parts.append("Constellation lines enabled.")
    else:
        feedback_parts.append("Constellation lines not enabled.")

    # ── 3. Screenshot Captured (20 points) ──
    new_shots = screenshots.get('new_count', 0)
    if new_shots > 0:
        score += 20
        feedback_parts.append(f"Captured {new_shots} screenshot(s).")
    else:
        feedback_parts.append("No new screenshots captured.")

    # ── 4. Event Guide Written (30 points) ──
    guide_exists = guide_file.get('exists', False)
    guide_created = guide_file.get('created_during_task', False)
    
    guide_passed = False
    if guide_exists and guide_created:
        score += 15
        feedback_parts.append("Event guide file created.")
        
        has_ny = guide_file.get('has_new_york', False)
        has_date = guide_file.get('has_date', False)
        has_target = guide_file.get('has_target', False)
        
        content_score = 0
        if has_ny: content_score += 5
        if has_date: content_score += 5
        if has_target: content_score += 5
        
        score += content_score
        
        if content_score == 15:
            guide_passed = True
            feedback_parts.append("Event guide contains all required details.")
        else:
            missing = []
            if not has_ny: missing.append("Location (New York)")
            if not has_date: missing.append("Date (March 14)")
            if not has_target: missing.append("Target (Moon/Eclipse)")
            feedback_parts.append(f"Event guide missing: {', '.join(missing)}")
    else:
        feedback_parts.append("Event guide not created during task session.")

    # ── VLM Trajectory Check (Optional reinforcement) ──
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            # We log VLM checks but don't strictly fail the robust programmatic score.
            # This confirms the agent actually drove the UI.
            feedback_parts.append(f"[VLM: {len(frames)} trajectory frames available for audit]")
    except Exception as e:
        logger.debug(f"VLM trajectory sampling skipped: {e}")

    # Pass threshold is 70, plus must have done the text file & location broadly right to be considered "completed"
    key_criteria_met = location_passed and guide_exists
    passed = (score >= 70) and key_criteria_met
    
    if not key_criteria_met and score >= 70:
        feedback_parts.append("Failed: Missing critical criteria (Location or Event Guide) despite high score.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }