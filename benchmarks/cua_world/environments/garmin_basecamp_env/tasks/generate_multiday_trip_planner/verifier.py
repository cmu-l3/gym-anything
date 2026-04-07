#!/usr/bin/env python3
"""Verifier for generate_multiday_trip_planner task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km using Haversine formula."""
    R = 6371.0  
    dLat = math.radians(lat2 - lat1)
    dLon = math.radians(lon2 - lon1)
    a = math.sin(dLat/2)**2 + \
        math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dLon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def verify_generate_multiday_trip_planner(traj, env_info, task_info):
    """
    Verify the Trip Planner generated a multi-day route.
    Uses programmatic checks of the exported GPX and VLM verification over trajectories.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    boston_lat = metadata.get('boston_lat', 42.3400)
    boston_lon = metadata.get('boston_lon', -71.0400)
    chicago_lat = metadata.get('chicago_lat', 41.8100)
    chicago_lon = metadata.get('chicago_lon', -87.6300)

    # 1. Load export results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("Output file exists")
        if file_created_during_task:
            feedback_parts.append("File created/modified during task")
        else:
            feedback_parts.append("File was NOT created during task (anti-gaming violation)")
    else:
        feedback_parts.append("Output GPX file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Parse exported GPX
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    route_count = 0
    try:
        copy_from_env("C:\\workspace\\output\\freight_itinerary.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
        
        # Strip namespaces for easier tag finding
        for elem in root.iter():
            if '}' in elem.tag:
                elem.tag = elem.tag.split('}', 1)[1]
                
        routes = root.findall('.//rte')
        route_count = len(routes)
        
        if route_count >= 2:
            score += 35
            feedback_parts.append(f"Found {route_count} routes (Trip Planner segmentation successful)")
        elif route_count == 1:
            feedback_parts.append("Found only 1 route. Trip Planner 8-hour daily segmentation not applied.")
        else:
            feedback_parts.append("No routes found in exported GPX file.")
            
        # Check start and end points of the segmented trip
        if route_count > 0:
            first_route_pts = routes[0].findall('.//rtept')
            last_route_pts = routes[-1].findall('.//rtept')
            
            if first_route_pts:
                start_lat = float(first_route_pts[0].get('lat', 0))
                start_lon = float(first_route_pts[0].get('lon', 0))
                if get_distance(start_lat, start_lon, boston_lat, boston_lon) < 50:  # within 50km
                    score += 15
                    feedback_parts.append("Start point correctly matches Boston")
                else:
                    feedback_parts.append(f"Start point mismatch ({start_lat:.2f}, {start_lon:.2f})")
                    
            if last_route_pts:
                end_lat = float(last_route_pts[-1].get('lat', 0))
                end_lon = float(last_route_pts[-1].get('lon', 0))
                if get_distance(end_lat, end_lon, chicago_lat, chicago_lon) < 50:
                    score += 15
                    feedback_parts.append("End point correctly matches Chicago")
                else:
                    feedback_parts.append(f"End point mismatch ({end_lat:.2f}, {end_lon:.2f})")
    except Exception as e:
        feedback_parts.append(f"Failed to parse GPX: {e}")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # 3. VLM Trajectory Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        prompt = '''You are evaluating a Garmin BaseCamp Trip Planner task.
Task goal: Create a trip from Boston to Chicago with a maximum of 8 hours of driving per day.
Please examine these trajectory frames.
Did the user open the "Trip Planner" dialog wizard?
Did they set an 8-hour travel limit in the planner properties?
Reply in JSON format:
{
  "trip_planner_opened": true/false,
  "travel_limit_set": true/false
}'''
        
        if frames:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("trip_planner_opened") and parsed.get("travel_limit_set"):
                    score += 20
                    feedback_parts.append("VLM confirmed Trip Planner 8-hour driving limit usage")
                else:
                    feedback_parts.append("VLM did not confirm Trip Planner 8-hour limit usage in trajectory frames")
    except ImportError:
        logger.warning("gym_anything.vlm not available for trajectory verification.")
        # Graceful fallback: Give points if programmatical segmentation succeeded
        if route_count >= 2:
            score += 20
            feedback_parts.append("VLM skipped but route segmentation strongly implies Trip Planner usage")
    except Exception as e:
        feedback_parts.append(f"VLM error: {e}")

    # Final logic: Need key criteria and at least an 80 score 
    passed = score >= 80 and route_count >= 2 and file_created_during_task
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }