#!/usr/bin/env python3
"""
Verifier for configure_custom_activity_profile task.
Evaluates Garmin BaseCamp Activity Profile settings and GPX export logic.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to inspect the trajectory for proper UI usage
VLM_PROMPT = """You are evaluating an agent's trajectory in Garmin BaseCamp.

TASK: The agent needs to create a custom Activity Profile named "SAR-ATV" with the "Shorter Distance" routing preference, and then draw a route on the map.

Examine the provided screenshots (which represent steps over time) and determine:
1. Did the agent open the "Options" or "Preferences" dialog (usually via Edit > Options)?
2. Did the agent navigate to the "Activity Profile" tab/settings?
3. Is there evidence that the agent adjusted routing preferences (like "Route Preference: Shorter Distance")?
4. Did the agent activate the "New Route" tool and click on the map interface to draw a route?

Return your response in pure JSON format:
{
    "opened_options_dialog": true/false,
    "navigated_to_activity_profiles": true/false,
    "adjusted_routing_preference": true/false,
    "drew_route_on_map": true/false
}
"""

def query_vlm_trajectory(traj, env_info):
    """Uses the provided VLM hook to analyze the trajectory."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=6)
        
        if not frames:
            return None
            
        result = query_vlm(images=frames, prompt=VLM_PROMPT)
        if result and result.get("success") and "parsed" in result:
            return result["parsed"]
    except Exception as e:
        logger.warning(f"VLM trajectory analysis failed or is unavailable: {e}")
    
    return None

def verify_custom_activity_profile(traj, env_info, task_info):
    """
    Verifies the configure_custom_activity_profile task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_gpx_path = metadata.get('expected_output_path', 'C:\\workspace\\sar_patrol_route.gpx')
    expected_profile = metadata.get('expected_profile_name', 'SAR-ATV')
    min_points = metadata.get('min_route_points', 3)
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch the JSON export result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate file creation
    output_exists = result.get("output_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)

    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GPX output file was not found. The agent failed to export the file to the correct location."
        }
        
    if file_created_during_task:
        score += 15
        feedback_parts.append("File created successfully during task (+15)")
    else:
        feedback_parts.append("Warning: File timestamp predates task start (Possible gaming)")

    # 2. Fetch and parse the exported GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env(expected_gpx_path, temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse GPX XML: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # BaseCamp outputs with these namespaces
    ns = {
        'gpx': 'http://www.topografix.com/GPX/1/1',
        'gpxx': 'http://www.garmin.com/xmlschemas/GpxExtensions/v3'
    }

    routes = root.findall('.//gpx:rte', ns)
    if not routes:
        # Fallback if default namespace wasn't mapped
        routes = root.findall('.//{http://www.topografix.com/GPX/1/1}rte')

    if len(routes) == 0:
        feedback_parts.append("Exported GPX does not contain any routes.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    route = routes[0] # Evaluate the first route
    
    # Check Route Geometry (Number of points)
    route_points = route.findall('gpx:rtept', ns)
    if not route_points:
        route_points = route.findall('.//{http://www.topografix.com/GPX/1/1}rtept')
        
    num_points = len(route_points)
    if num_points >= min_points:
        score += 20
        feedback_parts.append(f"Route geometry valid ({num_points} points) (+20)")
    elif num_points > 0:
        score += 10
        feedback_parts.append(f"Route geometry incomplete ({num_points} points) (+10)")
    else:
        feedback_parts.append("Route has no valid coordinate points.")

    # Check Route Profile Metadata (CRITICAL for this task)
    profile_found = False
    profile_matches = False
    engine_authenticity = False
    
    # Search for Garmin Profile Extension
    profile_elem = route.find('.//gpxx:Profile', ns)
    if profile_elem is None:
        profile_elem = route.find('.//{http://www.garmin.com/xmlschemas/GpxExtensions/v3}Profile')
        
    if profile_elem is not None:
        profile_found = True
        actual_profile = profile_elem.text
        if actual_profile and actual_profile.strip() == expected_profile:
            profile_matches = True
            score += 40
            feedback_parts.append("Custom Activity Profile 'SAR-ATV' successfully injected (+40)")
        else:
            feedback_parts.append(f"Profile found but incorrect: '{actual_profile}' instead of '{expected_profile}'")
    else:
        feedback_parts.append("No BaseCamp Profile extensions found in the route.")

    # Check for engine authenticity (garmin proprietary tags usually generated upon real export)
    # such as RoutePointExtension or Subclass
    subclass_elem = route.find('.//gpxx:Subclass', ns)
    if subclass_elem is None:
        subclass_elem = route.find('.//{http://www.garmin.com/xmlschemas/GpxExtensions/v3}Subclass')
        
    if subclass_elem is not None or profile_found:
        engine_authenticity = True
        score += 10
        feedback_parts.append("Engine authenticity verified (+10)")

    # 3. VLM Verification of Trajectory
    vlm_stats = query_vlm_trajectory(traj, env_info)
    if vlm_stats:
        ui_score = 0
        if vlm_stats.get("opened_options_dialog"): ui_score += 3
        if vlm_stats.get("navigated_to_activity_profiles"): ui_score += 4
        if vlm_stats.get("adjusted_routing_preference"): ui_score += 4
        if vlm_stats.get("drew_route_on_map"): ui_score += 4
        
        score += ui_score
        feedback_parts.append(f"VLM visual workflow verification ({ui_score}/15 pts)")
    else:
        # If VLM is missing but XML is perfect, grant default proxy points
        if profile_matches and num_points >= min_points:
            score += 15
            feedback_parts.append("VLM unavailable, auto-granted visual points based on perfect output (+15)")

    # Evaluate Final Pass/Fail
    # To pass: File must exist, Route must have points, and Profile must match exactly.
    key_criteria_met = file_created_during_task and (num_points >= min_points) and profile_matches
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }