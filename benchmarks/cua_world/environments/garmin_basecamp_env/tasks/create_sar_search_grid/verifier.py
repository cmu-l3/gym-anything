#!/usr/bin/env python3
"""
Verifier for create_sar_search_grid task.

Verification Strategy:
1. Programmatic Checks:
   - GPX file exists and was created after task start (Anti-gaming).
   - Valid GPX XML.
   - Contains exactly 6 waypoints.
   - Waypoint names strictly match requirements.
   - Waypoint coordinates are within 0.001 degrees of target.
   - Symbols contain "Flag" and "Blue".
2. VLM Checks:
   - Analyzes trajectory frames to ensure the agent interacted with the GUI
     to create the 'SAR Grid - Fells' list and input coordinates.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_gpx_file(filepath):
    """Safely parse a GPX file ignoring namespaces."""
    try:
        # Read raw content to strip namespaces for easier parsing
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Super simple namespace strip for ElementTree
        import re
        content = re.sub(r'\sxmlns="[^"]+"', '', content, count=1)
        root = ET.fromstring(content)
        
        waypoints = []
        for wpt in root.findall('.//wpt'):
            lat = float(wpt.get('lat', 0))
            lon = float(wpt.get('lon', 0))
            
            name_elem = wpt.find('name')
            name = name_elem.text.strip() if name_elem is not None and name_elem.text else ""
            
            sym_elem = wpt.find('sym')
            sym = sym_elem.text.strip() if sym_elem is not None and sym_elem.text else ""
            
            waypoints.append({
                "lat": lat,
                "lon": lon,
                "name": name,
                "sym": sym
            })
        return {"success": True, "waypoints": waypoints}
    except Exception as e:
        logger.error(f"Error parsing GPX: {e}")
        return {"success": False, "error": str(e)}

def verify_create_sar_search_grid(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    expected_wpts = metadata.get('expected_waypoints', {})
    coord_tolerance = metadata.get('coord_tolerance', 0.001)

    score = 0
    max_score = 100
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, 'task_result.json')
    gpx_file_path = os.path.join(temp_dir, 'sar_grid.gpx')
    
    # 1. Fetch the task result summary
    try:
        copy_from_env("/workspace/output/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # Anti-gaming: Ensure file exists and was created during task
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "GPX file was not exported to C:\\workspace\\output\\sar_grid.gpx"}
        
    if not task_result.get("file_created_during_task", False):
        feedback_parts.append("WARNING: GPX file timestamp is older than task start. Possible cheating.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    score += 10
    feedback_parts.append("GPX file successfully exported")

    # 2. Fetch and parse the exported GPX file
    try:
        copy_from_env("/workspace/output/sar_grid.gpx", gpx_file_path)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve GPX file: {e}"}

    gpx_data = parse_gpx_file(gpx_file_path)
    if not gpx_data["success"]:
        feedback_parts.append(f"Invalid GPX XML format: {gpx_data.get('error')}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append("GPX file is valid XML")
    
    found_waypoints = gpx_data["waypoints"]
    if len(found_waypoints) == 6:
        score += 10
        feedback_parts.append("Correct number of waypoints (6)")
    elif len(found_waypoints) > 0:
        score += 5
        feedback_parts.append(f"Incorrect number of waypoints: {len(found_waypoints)} (Expected 6)")
    else:
        feedback_parts.append("GPX file contains no waypoints")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Verify Coordinates, Names, and Symbols
    matched_names = 0
    accurate_coords = 0
    correct_symbols = 0
    
    for fw in found_waypoints:
        name = fw["name"]
        lat = fw["lat"]
        lon = fw["lon"]
        sym = fw["sym"].lower()
        
        if name in expected_wpts:
            matched_names += 1
            expected_lat, expected_lon = expected_wpts[name]
            
            # Check accuracy
            lat_diff = abs(lat - expected_lat)
            lon_diff = abs(lon - expected_lon)
            if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
                accurate_coords += 1
                
        if "flag" in sym and "blue" in sym:
            correct_symbols += 1

    # Scoring Names
    if matched_names == 6:
        score += 15
        feedback_parts.append("All 6 waypoint names matched exactly")
    elif matched_names > 0:
        score += int(15 * (matched_names / 6.0))
        feedback_parts.append(f"{matched_names}/6 waypoint names matched")
        
    # Scoring Coordinates
    if accurate_coords == 6:
        score += 20
        feedback_parts.append("All 6 waypoint coordinates accurate")
    elif accurate_coords > 0:
        score += int(20 * (accurate_coords / 6.0))
        feedback_parts.append(f"{accurate_coords}/6 waypoint coordinates accurate")
        
    # Scoring Symbols
    if correct_symbols == 6:
        score += 10
        feedback_parts.append("All 6 waypoint symbols set to Flag, Blue")
    elif correct_symbols > 0:
        score += int(10 * (correct_symbols / 6.0))
        feedback_parts.append(f"{correct_symbols}/6 waypoint symbols correct")

    # 4. VLM Trajectory Verification
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if frames:
            prompt = """
            You are evaluating an AI agent operating Garmin BaseCamp. 
            The goal was to create a list named 'SAR Grid - Fells', populate it with waypoints, and export it.
            
            Review these screenshots from the agent's session and determine:
            1. Did the agent interact with the Library panel to create a list called 'SAR Grid - Fells'?
            2. Are there dialogs or map views showing multiple waypoints being created in a grid pattern?
            3. Did the agent open the Export dialog?
            
            Respond strictly in JSON format:
            {
                "list_created": true/false,
                "waypoint_activity_visible": true/false,
                "export_dialog_visible": true/false
            }
            """
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("list_created"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed 'SAR Grid - Fells' list creation")
                if parsed.get("waypoint_activity_visible"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed waypoint creation activity")
                if parsed.get("export_dialog_visible"):
                    vlm_score += 5
                    feedback_parts.append("VLM confirmed export dialog usage")
            else:
                feedback_parts.append("VLM query failed or returned invalid response.")
    except Exception as e:
        logger.error(f"VLM Verification failed: {e}")
        feedback_parts.append(f"VLM verification error: {e}")

    score += vlm_score

    # Final pass logic
    # Requires base GPX elements and at least 60 points total
    key_criteria_met = task_result.get("file_created_during_task", False) and matched_names >= 4 and accurate_coords >= 4
    passed = (score >= 60) and key_criteria_met
    
    if not key_criteria_met:
        feedback_parts.append("FAILED: Core requirements (file creation time, min names, min coords) not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }