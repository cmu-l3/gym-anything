#!/usr/bin/env python3
"""
Verifier for create_user_waypoint task.

Criteria:
1. UDW.csv file must exist and contain the new waypoint.
2. Waypoint Name must match "LKPK" (case-insensitive).
3. Latitude/Longitude must be within tolerance.
4. VLM verification of the trajectory (UI usage).
"""

import json
import os
import tempfile
import csv
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_waypoint(traj, env_info, task_info):
    """
    Verify creation of User Defined Waypoint in Avare.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'LKPK')
    expected_lat = metadata.get('expected_lat', 37.475)
    expected_lon = metadata.get('expected_lon', -122.170)
    tolerance = metadata.get('tolerance_deg', 0.01)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Artifacts
    # =========================================================
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    udw_csv_path = os.path.join(temp_dir, "task_result_UDW.csv")
    
    try:
        copy_from_env("/sdcard/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        udw_found = result_data.get('udw_file_found', False)
        
        if udw_found:
            copy_from_env("/sdcard/task_result_UDW.csv", udw_csv_path)
            
    except Exception as e:
        logger.error(f"Failed to retrieve task artifacts: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error retrieving verification data: {str(e)}"}

    # =========================================================
    # 2. Analyze CSV Data (Primary Verification)
    # =========================================================
    waypoint_verified = False
    coord_error = False
    
    if os.path.exists(udw_csv_path):
        try:
            with open(udw_csv_path, 'r', encoding='utf-8', errors='ignore') as f:
                # Avare UDW format is typically just values, or Name,Type,Lat,Lon... 
                # We will scan lines for the name and then check surrounding values.
                content = f.read()
                
            lines = content.splitlines()
            for line in lines:
                if expected_name.lower() in line.lower():
                    # Found the name, now parse coords
                    # Naive CSV parse: split by comma
                    parts = line.split(',')
                    # Look for float values in the parts
                    lat_found = None
                    lon_found = None
                    
                    for part in parts:
                        try:
                            val = float(part.strip())
                            # Check if this float looks like our lat or lon
                            if abs(val - expected_lat) < 5.0: # Rough check to identify
                                lat_found = val
                            if abs(val - expected_lon) < 5.0:
                                lon_found = val
                        except ValueError:
                            continue
                            
                    if lat_found is not None and lon_found is not None:
                        lat_diff = abs(lat_found - expected_lat)
                        lon_diff = abs(lon_found - expected_lon)
                        
                        if lat_diff <= tolerance and lon_diff <= tolerance:
                            waypoint_verified = True
                            score += 50
                            feedback_parts.append(f"✅ Found waypoint '{expected_name}' with correct coordinates ({lat_found}, {lon_found}).")
                            break
                        else:
                            coord_error = True
                            feedback_parts.append(f"⚠️ Found name '{expected_name}' but coordinates mismatch. Got ({lat_found}, {lon_found}), expected ({expected_lat}, {expected_lon}).")
                    elif lat_found is None and lon_found is None:
                         feedback_parts.append(f"⚠️ Found name '{expected_name}' but could not parse coordinates from line: {line}")
        except Exception as e:
            feedback_parts.append(f"Error parsing UDW file: {e}")
    else:
        feedback_parts.append("❌ UDW.csv file not found on device.")

    # =========================================================
    # 3. VLM Verification (Process & Visual Confirmation)
    # =========================================================
    # Check if the agent actually used the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = f"""
    You are verifying an agent's task on an Android aviation app (Avare).
    The Goal: Create a User Defined Waypoint named '{expected_name}'.
    
    Review the screenshots.
    1. Did the agent navigate to a "Plan", "Find", or "Waypoints" screen?
    2. Did the agent enter the text "{expected_name}"?
    3. Did the agent enter coordinates (around {expected_lat}, {expected_lon})?
    4. Does the final screen show "{expected_name}" in a list or on the map?
    
    Return JSON:
    {{
      "ui_navigation": true/false,
      "text_entry_seen": true/false,
      "waypoint_visible_final": true/false,
      "reasoning": "..."
    }}
    """
    
    vlm_result = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('ui_navigation'):
            vlm_score += 15
        if parsed.get('text_entry_seen'):
            vlm_score += 15
        if parsed.get('waypoint_visible_final'):
            vlm_score += 20
        
        score += vlm_score
        feedback_parts.append(f"VLM Analysis: {parsed.get('reasoning', 'No reasoning provided')}")
    else:
        feedback_parts.append("⚠️ VLM verification failed to run.")

    # =========================================================
    # 4. Final Scoring
    # =========================================================
    # Cleanup
    import shutil
    shutil.rmtree(temp_dir)
    
    # Pass logic: Must have data verified (50 pts) AND some visual evidence (>=15 pts) OR very strong visual evidence if file fails (unlikely)
    # Strictly: If file is correct, that's the gold standard.
    
    if waypoint_verified:
        # If file is perfect, we are lenient on VLM (maybe it was done very fast)
        # But we want to ensure it wasn't just a shell command injection if possible.
        # However, shell injection of a complex CSV format is hard without knowing the format.
        # We'll trust the file verification heavily.
        if score < 60: score = 60 # Ensure pass if data is correct
    
    passed = score >= 60 and (waypoint_verified or (vlm_score > 40))

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }