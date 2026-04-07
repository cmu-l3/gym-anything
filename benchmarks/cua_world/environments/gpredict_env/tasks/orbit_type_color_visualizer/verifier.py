#!/usr/bin/env python3
"""
Verifier for orbit_type_color_visualizer task.

Uses multi-signal verification:
1. Programmatic Config Parsing: Verifies QTH and Mod creation, layout, satellites, and hex colors.
2. VLM Trajectory Verification: Confirms visual UI interaction to prevent blind-scripting bypasses.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def check_dominant_color(hex_str, target_channel):
    """
    Parses a hex color string (e.g. #FF0000, #FFFF00000000) and checks if the 
    target channel (R, G, or B) is mathematically dominant.
    """
    if not hex_str:
        return False
        
    hex_str = hex_str.strip().lstrip('#')
    try:
        if len(hex_str) == 6:
            r, g, b = int(hex_str[0:2], 16), int(hex_str[2:4], 16), int(hex_str[4:6], 16)
        elif len(hex_str) == 12: # GdkColor 16-bit per channel
            r, g, b = int(hex_str[0:4], 16)>>8, int(hex_str[4:8], 16)>>8, int(hex_str[8:12], 16)>>8
        elif len(hex_str) == 3: # Shorthand
            r, g, b = int(hex_str[0]*2, 16), int(hex_str[1]*2, 16), int(hex_str[2]*2, 16)
        else:
            return False
    except ValueError:
        return False

    if target_channel == 'R':
        return r > g and r > b and r > 50
    elif target_channel == 'G':
        return g > r and g > b and g > 50
    elif target_channel == 'B':
        return b > r and b > g and b > 50
        
    return False

def verify_orbit_type_color_visualizer(traj, env_info, task_info):
    """
    Verify the educational orbit visualization task.

    Scoring (100 points):
    - Ground Station Creation: 15 pts
    - Module Base Configuration: 15 pts
    - Module Layout (Split View): 10 pts
    - Satellites Added: 15 pts
    - ISS (25544) Color is Red: 15 pts
    - NOAA 19 (33591) Color is Blue: 15 pts
    - GOES 16 (43013) Color is Green: 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    # Copy task result safely
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/orbit_task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file missing or invalid: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # Copy start time for anti-gaming checks
    start_time_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/task_start_time.txt", start_time_file.name)
        with open(start_time_file.name, 'r') as f:
            start_time = float(f.read().strip())
    except Exception:
        start_time = 0
    finally:
        if os.path.exists(start_time_file.name):
            os.unlink(start_time_file.name)

    score = 0
    feedback = []

    # Check 1: Ground Station exists and is accurate (15 pts)
    if result.get('qth_exists'):
        # Anti-gaming: Ensure it was created during the task
        if result.get('qth_mtime', 0) >= start_time:
            lat_ok = _close_enough(result.get('lat', ''), metadata.get('target_lat', 40.4259), 0.1)
            lon_ok = _close_enough(result.get('lon', ''), metadata.get('target_lon', -86.9081), 0.1)
            alt_ok = _close_enough(result.get('alt', ''), metadata.get('target_alt', 187), 10)
            
            if lat_ok and lon_ok and alt_ok:
                score += 15
                feedback.append("Ground Station Purdue_Lab configured perfectly.")
            else:
                score += 5
                feedback.append("Ground Station Purdue_Lab exists but coordinates are inaccurate.")
        else:
            feedback.append("Purdue_Lab.qth existed before task start (Anti-gaming triggered).")
    else:
        feedback.append("Ground Station Purdue_Lab.qth not found.")

    # Check 2: Module Base Config (15 pts)
    if result.get('mod_exists'):
        if result.get('mod_mtime', 0) >= start_time:
            qth_assigned = result.get('qthfile', '').lower() == "purdue_lab.qth"
            if qth_assigned:
                score += 15
                feedback.append("Module Orbit_Types correctly bound to Purdue_Lab.")
            else:
                score += 5
                feedback.append("Module Orbit_Types exists but is bound to wrong ground station.")
                
            # Check 3: Module Layout (10 pts)
            layout = result.get('layout', '')
            if layout == "4":  # Layout 4 is standard Map+Polar
                score += 10
                feedback.append("Module Layout correctly set to Split View.")
            else:
                feedback.append(f"Module Layout incorrect (Expected '4', found '{layout}').")

            # Check 4: Satellites added (15 pts)
            satellites = result.get('satellites', '')
            has_iss = "25544" in satellites
            has_noaa = "33591" in satellites
            has_goes = "43013" in satellites
            
            sat_count = sum([has_iss, has_noaa, has_goes])
            score += (sat_count * 5)
            if sat_count == 3:
                feedback.append("All 3 required satellites added to module.")
            else:
                feedback.append(f"Module contains {sat_count}/3 required satellites.")
                
            # Check 5: Colors (15 pts each)
            colors = result.get('colors', {})
            
            # ISS (25544) -> Red
            c_iss = colors.get("25544", "")
            if has_iss and check_dominant_color(c_iss, 'R'):
                score += 15
                feedback.append(f"ISS color successfully changed to Red ({c_iss}).")
            elif has_iss:
                feedback.append(f"ISS color incorrect or default ({c_iss}).")

            # NOAA 19 (33591) -> Blue
            c_noaa = colors.get("33591", "")
            if has_noaa and check_dominant_color(c_noaa, 'B'):
                score += 15
                feedback.append(f"NOAA 19 color successfully changed to Blue ({c_noaa}).")
            elif has_noaa:
                feedback.append(f"NOAA 19 color incorrect or default ({c_noaa}).")

            # GOES 16 (43013) -> Green
            c_goes = colors.get("43013", "")
            if has_goes and check_dominant_color(c_goes, 'G'):
                score += 15
                feedback.append(f"GOES 16 color successfully changed to Green ({c_goes}).")
            elif has_goes:
                feedback.append(f"GOES 16 color incorrect or default ({c_goes}).")
                
        else:
            feedback.append("Orbit_Types.mod existed before task start (Anti-gaming triggered).")
    else:
        feedback.append("Module Orbit_Types.mod not found.")

    # VLM Trajectory Check (Anti-gaming: Verify UI interaction occurred)
    if score >= 60:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            You are verifying a computer agent's task.
            The agent was supposed to use a desktop application (GPredict) to configure a satellite tracker.
            Look at these trajectory screenshots. 
            Do you see ANY evidence that the agent actually interacted with the application UI (e.g., clicking menus, typing in dialog boxes, opening color pickers, or editing configurations)?
            If it just shows an empty desktop or a completely static screen without evidence of workflow progression, answer false.
            Respond strictly in JSON format: {"interacted": true} or {"interacted": false}.
            """
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('interacted') is False:
                    score = 0
                    feedback.append("VLM Verification FAILED: Trajectory shows no evidence of actual UI interaction. Potential script injection / gaming attempt.")
                else:
                    feedback.append("VLM Verification passed: UI interaction confirmed.")
            except Exception as e:
                logger.warning(f"VLM trajectory verification failed, proceeding with programmatic score: {e}")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }