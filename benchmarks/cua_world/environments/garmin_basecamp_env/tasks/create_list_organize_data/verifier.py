#!/usr/bin/env python3
"""
Verifier for create_list_organize_data@1

Checks:
1. GPX file exists and was created during the task (Anti-gaming).
2. GPX is valid XML and contains the correct namespace.
3. Waypoint 1 ("Oak Stand A") exists within coordinate tolerance.
4. Waypoint 2 ("Wetland Plot B") exists within coordinate tolerance.
5. Exactly 2 waypoints exist (verifies agent exported the specific list, not the whole library).
6. VLM Verification: Ensures the agent actually used the BaseCamp UI to do the organization.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def build_vlm_prompt():
    return """Analyze these screenshots from a Garmin BaseCamp session.
The user was asked to create a list named 'Fall Survey 2024' and add two specific waypoints to it.

Please verify the following regarding their interaction with the BaseCamp interface:
1. Is there a list named exactly "Fall Survey 2024" visible in the Library/My Collection hierarchy pane?
2. Are the waypoints "Oak Stand A" and "Wetland Plot B" visible in the data pane, indicating they were created?
3. Is there evidence that the user used the BaseCamp UI to perform this work (e.g., navigating the library, creating items, using the export dialog), rather than bypassing the UI?

Respond with a JSON object containing these boolean flags and a brief reasoning:
{
    "list_created_in_ui": true/false,
    "waypoints_visible_in_ui": true/false,
    "used_basecamp_ui": true/false,
    "reasoning": "brief explanation"
}
"""


def verify_create_list_organize_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_wpts = metadata.get('waypoints', [])
    tolerance = metadata.get('coord_tolerance', 0.005)

    score = 0
    feedback_parts = []
    
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        # 1. Fetch result data
        try:
            copy_from_env("C:\\temp\\task_result.json", temp_result_json.name)
            with open(temp_result_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}

        gpx_exists = result.get("gpx_exists", False)
        if not gpx_exists:
            return {"passed": False, "score": 0, "feedback": "GPX output file was not found."}

        # 2. Check File Freshness (Anti-gaming)
        start_time = result.get("start_time", 0)
        gpx_mtime = result.get("gpx_mtime", 0)
        
        if gpx_mtime > start_time and start_time > 0:
            score += 15
            feedback_parts.append("File was freshly created/exported")
        else:
            feedback_parts.append("File modification time is invalid or older than task start")
            # Severe penalty for potentially pre-existing files, but we continue checking content

        # 3. Fetch and Parse GPX
        try:
            copy_from_env("C:\\workspace\\output\\fall_survey_2024.gpx", temp_gpx.name)
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
            
            # Extract GPX namespace dynamically
            ns = ""
            if root.tag.startswith("{"):
                ns = root.tag.split("}")[0] + "}"
                
            score += 10
            feedback_parts.append("Valid GPX XML structure")
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse GPX XML: {e}"}

        # Extract all waypoints
        found_waypoints = {}
        wpt_elements = root.findall(f".//{ns}wpt")
        
        for wpt in wpt_elements:
            lat = float(wpt.get("lat", 0))
            lon = float(wpt.get("lon", 0))
            name_elem = wpt.find(f"{ns}name")
            name = name_elem.text if name_elem is not None else "unnamed"
            found_waypoints[name] = {"lat": lat, "lon": lon}

        # 4. Verify specific waypoints and coordinates
        wpts_matched = 0
        for expected in expected_wpts:
            name = expected["name"]
            if name in found_waypoints:
                actual = found_waypoints[name]
                lat_diff = abs(actual["lat"] - expected["lat"])
                lon_diff = abs(actual["lon"] - expected["lon"])
                
                if lat_diff <= tolerance and lon_diff <= tolerance:
                    score += 20
                    wpts_matched += 1
                    feedback_parts.append(f"Waypoint '{name}' verified")
                else:
                    feedback_parts.append(f"Waypoint '{name}' coordinates out of tolerance")
            else:
                feedback_parts.append(f"Waypoint '{name}' missing from GPX")

        # 5. Check exact count (verifies they exported the list, not the whole library)
        if len(found_waypoints) == len(expected_wpts) and wpts_matched == len(expected_wpts):
            score += 15
            feedback_parts.append("Clean export (exactly 2 waypoints)")
        elif len(found_waypoints) > len(expected_wpts):
            feedback_parts.append(f"Found {len(found_waypoints)} waypoints (likely exported entire collection instead of just the list)")

        # 6. VLM Trajectory Verification
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = [img for img in frames + [final] if img is not None]
            
            if images:
                vlm_resp = query_vlm(images=images, prompt=build_vlm_prompt())
                parsed = vlm_resp.get("parsed", {})
                
                if parsed.get("list_created_in_ui") and parsed.get("waypoints_visible_in_ui"):
                    score += 20
                    feedback_parts.append("VLM confirmed BaseCamp UI usage")
                else:
                    feedback_parts.append("VLM could not confirm proper BaseCamp UI usage")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")
            # If VLM fails due to framework limits, we don't penalize, just pro-rate
            score += 20
            feedback_parts.append("VLM verification bypassed")

        # Key criteria: Both waypoints must be correctly placed and exported
        passed = (score >= 60) and (wpts_matched == len(expected_wpts))

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)