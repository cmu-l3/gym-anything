#!/usr/bin/env python3
"""
Verifier for navigate_to_coordinates task.

Strategies:
1. VLM Analysis (Primary): Does the final screen show the Golden Gate Bridge area?
2. Trajectory Analysis: Did the agent input the coordinates?
3. State Check (Secondary): Did the app save the last location near target?
"""

import json
import tempfile
import os
import logging
import re
import math
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_prefs_location(prefs_path):
    """Extract lat/lon from Avare preferences XML if available."""
    try:
        tree = ET.parse(prefs_path)
        root = tree.getroot()
        # Look for keys like "last_location", "map_center_lat", etc.
        # Avare typically stores state, but keys vary. We look for floats.
        data = {}
        for child in root:
            name = child.attrib.get('name', '')
            # Common patterns for map apps
            if 'lat' in name.lower() or 'lon' in name.lower():
                try:
                    data[name] = float(child.attrib.get('value', 0))
                except:
                    pass
        return data
    except Exception as e:
        logger.warning(f"Failed to parse prefs: {e}")
        return {}

def verify_navigate_to_coordinates(traj, env_info, task_info):
    """
    Verify agent navigated to specific coordinates.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task constants
    TARGET_LAT = task_info['metadata']['target_lat']
    TARGET_LON = task_info['metadata']['target_lon']
    TOLERANCE = task_info['metadata']['tolerance_degrees']
    
    # 1. Setup temporary files
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    prefs_path = os.path.join(temp_dir, "final_prefs.xml")
    
    score = 0
    feedback_parts = []
    
    try:
        # 2. Retrieve files from environment
        copy_from_env("/sdcard/task_result.json", result_json_path)
        
        # Try copying prefs (might fail if export failed)
        try:
            copy_from_env("/sdcard/final_prefs.xml", prefs_path)
            prefs_available = True
        except:
            prefs_available = False

        # Load JSON result
        with open(result_json_path, 'r') as f:
            res_data = json.load(f)

        if not res_data.get("app_running", False):
            feedback_parts.append("App crashed or was closed.")
        else:
            score += 10
            feedback_parts.append("App is running.")

        # 3. Trajectory Verification (Did they type coordinates?)
        # We assume `traj` contains action history or we use VLM on frames
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        if not final_screen:
            return {"passed": False, "score": 0, "feedback": "No screenshots available"}

        # 4. VLM Verification
        # Check trajectory for input
        traj_prompt = f"The user is supposed to enter coordinates '{TARGET_LAT} {TARGET_LON}'. Look at these steps. Did the user open a search/find dialog and type these numbers?"
        traj_check = query_vlm(images=frames, prompt=traj_prompt)
        
        input_confirmed = False
        if traj_check['success'] and "yes" in traj_check['response'].lower():
            score += 30
            input_confirmed = True
            feedback_parts.append("Coordinate input detected in trajectory.")
        else:
            feedback_parts.append("Could not confirm coordinate input visually.")

        # Check final location
        final_prompt = """
        Analyze this map screenshot. 
        1. Is it centered on the Golden Gate Bridge in San Francisco? (Look for the bridge spanning the bay entrance, Presidio to the south, Marin headlands to the north).
        2. Are there any coordinates visible on screen? If so, what are they?
        3. Is there a red crosshair or map center indicator?
        """
        final_check = query_vlm(images=[final_screen], prompt=final_prompt)
        
        visual_pass = False
        if final_check['success']:
            resp = final_check['response'].lower()
            if "golden gate" in resp or "bridge" in resp:
                score += 60
                visual_pass = True
                feedback_parts.append("Visual verification: Golden Gate Bridge identified.")
            else:
                feedback_parts.append("Visual verification: Target location NOT clearly identified.")
        
        # 5. Fallback: Prefs check (if available and parseable)
        # This is high-precision if it works, but app might not save to disk immediately
        if prefs_available and not visual_pass:
            loc_data = parse_prefs_location(prefs_path)
            # Hypothertical keys - logic checks for any key close to target
            lat_found = False
            lon_found = False
            
            for key, val in loc_data.items():
                if abs(val - TARGET_LAT) < TOLERANCE:
                    lat_found = True
                if abs(val - TARGET_LON) < TOLERANCE:
                    lon_found = True
            
            if lat_found and lon_found:
                score += 60
                feedback_parts.append("Internal state confirms correct coordinates.")
                visual_pass = True

        passed = visual_pass and (input_confirmed or score >= 70)

        return {
            "passed": passed,
            "score": min(100, score),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)