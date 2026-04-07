#!/usr/bin/env python3
"""
Verifier for project_waypoint_bearing_distance task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Validates that the output GPX file was created during the task timeframe (Anti-gaming).
2. Parses GPX to confirm both 'Origin-Landmark' and 'Sample-Plot-Alpha' exist.
3. Calculates the Haversine distance to ensure they are ~450m apart.
4. Calculates the initial Forward Azimuth to ensure the projection bearing was ~135°.
5. Uses VLM (optional layer) to examine the trajectory and visually confirm BaseCamp GUI interaction.

Pass threshold: 75% (requires programmatic spatial checks to succeed)
"""

import os
import json
import math
import tempfile
import logging

logger = logging.getLogger(__name__)

def get_distance(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance between two points on earth in meters."""
    R = 6371000  # Radius of Earth in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def get_bearing(lat1, lon1, lat2, lon2):
    """Calculate the initial forward azimuth (bearing) from point 1 to point 2."""
    lat1, lon1 = math.radians(lat1), math.radians(lon1)
    lat2, lon2 = math.radians(lat2), math.radians(lon2)
    dLon = lon2 - lon1
    x = math.sin(dLon) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - (math.sin(lat1) * math.cos(lat2) * math.cos(dLon))
    return (math.degrees(math.atan2(x, y)) + 360) % 360

def verify_project_waypoint_bearing_distance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        # 1. Fetch JSON execution results
        copy_from_env("C:/workspace/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        if result.get('output_exists'):
            score += 10
            feedback.append("Output GPX exists.")
            
            # Anti-gaming timestamp check
            task_start = result.get('task_start', 0)
            modified_time = result.get('modified_time', 0)
            if modified_time >= task_start:
                score += 10
                feedback.append("File created/modified during task.")
            else:
                feedback.append("File timestamp is older than task start.")
                
            # 2. Copy and parse the GPX file
            copy_from_env("C:/workspace/output/projected_plot.gpx", temp_gpx.name)
            
            import xml.etree.ElementTree as ET
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
            
            # Strip namespaces for easier parsing
            for elem in root.iter():
                if '}' in elem.tag:
                    elem.tag = elem.tag.split('}', 1)[1]
                    
            waypoints = {}
            for wpt in root.findall('wpt'):
                name_elem = wpt.find('name')
                if name_elem is not None and name_elem.text:
                    lat = float(wpt.get('lat', 0))
                    lon = float(wpt.get('lon', 0))
                    waypoints[name_elem.text.strip()] = (lat, lon)
                    
            origin = waypoints.get("Origin-Landmark")
            sample = waypoints.get("Sample-Plot-Alpha")
            
            if origin:
                score += 10
                feedback.append("Origin-Landmark found.")
            else:
                feedback.append("Origin-Landmark missing.")
                
            if sample:
                score += 10
                feedback.append("Sample-Plot-Alpha found.")
            else:
                feedback.append("Sample-Plot-Alpha missing.")
                
            # 3. Geodetic spatial verification checks
            if origin and sample:
                dist = get_distance(origin[0], origin[1], sample[0], sample[1])
                bearing = get_bearing(origin[0], origin[1], sample[0], sample[1])
                
                if abs(dist - 450) <= 15: # 15 meters projection error tolerance
                    score += 20
                    feedback.append(f"Distance accurate: {dist:.1f}m")
                else:
                    feedback.append(f"Distance incorrect: {dist:.1f}m (expected ~450m)")
                    
                if abs(bearing - 135) <= 5: # 5 degrees bearing tolerance
                    score += 20
                    feedback.append(f"Bearing accurate: {bearing:.1f}°")
                else:
                    feedback.append(f"Bearing incorrect: {bearing:.1f}° (expected ~135°)")
        else:
            feedback.append("Output GPX file not found.")

        # 4. Trajectory VLM Verification Layer
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = """Analyze these screenshots from a user session in Garmin BaseCamp.
Did the user interact with the BaseCamp interface to project a waypoint (e.g., using waypoint properties, 'project waypoint' tool, or manipulating the UI elements for mapping)?
Answer in JSON format: {"used_basecamp": true/false, "reason": "brief explanation"}"""
                vlm_result = query_vlm(images=frames, prompt=prompt)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('used_basecamp'):
                        score += 20
                        feedback.append("VLM confirmed BaseCamp GUI usage.")
                    else:
                        feedback.append("VLM did not detect BaseCamp interaction.")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    except Exception as e:
        feedback.append(f"Verification error encountered: {e}")
    finally:
        # Safely remove temp copies
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)
            
    passed = score >= 75
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}